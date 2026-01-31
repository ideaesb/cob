# Requires -Version 5.1
<#
  last_hour_ingest.ps1
  City of Bryan - Signal High-Res "last completed hour" ingest into Postgres
#>

[CmdletBinding()]
param(
  # Accept either:
  #  -ID "2,12,55"
  #  -ID 2,12,55          (PowerShell array)
  #  -ID "3,52..56,10"
  [Alias("ID")]
  [string[]]$IDs,

  [switch]$OnlyEventsNeeded = $true
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ---------------------------
# USER-CONFIG (Header)
# ---------------------------
$PsqlExe     = "C:\PostgreSQL\17\bin\psql.exe"
$PgHost      = "localhost"
$PgPort      = 5432
$PgUser      = "postgres"
$PgPassword  = "postgres"   # requested: no prompts
$DbName      = "cob"

$AzureBase   = "https://cob77803.blob.core.windows.net/siglog"

# If you're running from C:\Users\ukari\Documents\Signals, this resolves:
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = (Get-Location).Path }

$SignalsCsv  = Join-Path $ScriptDir "TrafficSignalIDandName.csv"

# Temp working files
$TempDir     = Join-Path $ScriptDir "tmp_ingest"
$TempCopyCsv = Join-Path $TempDir "high_res_copy.csv"

# ---------------------------
# Helpers
# ---------------------------
function Assert-Exists([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "$Label not found: $Path" }
}

function Run-Psql([string]$Db, [string]$Sql) {
  # Use env var so psql never prompts for password
  $env:PGPASSWORD = $PgPassword

  $args = @(
    "-h", $PgHost,
    "-p", "$PgPort",
    "-U", $PgUser,
    "-d", $Db,
    "-v", "ON_ERROR_STOP=1",
    "-q",
    "-c", $Sql
  )

  & $PsqlExe @args
  if ($LASTEXITCODE -ne 0) { throw "psql failed (exit $LASTEXITCODE) running SQL: $Sql" }
}

function Truncate-ToHour([datetime]$dt) {
  return (Get-Date -Year $dt.Year -Month $dt.Month -Day $dt.Day -Hour $dt.Hour -Minute 0 -Second 0 -Millisecond 0)
}

function Test-AzureFileExists([string]$Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 10
    return ($r.StatusCode -eq 200)
  } catch {
    return $false
  }
}

function Download-File([string]$Url, [string]$OutFile) {
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 | Out-Null
}

function Csv-Escape([string]$s) {
  if ($null -eq $s) { return "" }
  if ($s -match '[,"\r\n]') {
    return '"' + ($s -replace '"','""') + '"'
  }
  return $s
}

# Parse "3, 52..56,10" or "3,52-56,10" into a distinct sorted int[]
function Parse-IdSpec([string[]]$spec) {
  if ($null -eq $spec -or $spec.Count -eq 0) { return @() }

  # Join array inputs into one string (handles: -ID 2,12,55 => "2 12 55")
  $joined = ($spec -join ",")

  if ([string]::IsNullOrWhiteSpace($joined)) { return @() }

  $out = New-Object System.Collections.Generic.List[int]

  # Split on commas OR whitespace
  $tokens = ($joined -split '[,\s]+' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne "" }

  foreach ($t in $tokens) {
    if ($t -match '^(\d+)\.\.(\d+)$') {
      $a = [int]$Matches[1]; $b = [int]$Matches[2]
      if ($a -le $b) { $a..$b | ForEach-Object { $out.Add([int]$_) } }
      else { $b..$a | ForEach-Object { $out.Add([int]$_) } }
      continue
    }
    if ($t -match '^(\d+)-(\d+)$') {
      $a = [int]$Matches[1]; $b = [int]$Matches[2]
      if ($a -le $b) { $a..$b | ForEach-Object { $out.Add([int]$_) } }
      else { $b..$a | ForEach-Object { $out.Add([int]$_) } }
      continue
    }
    if ($t -match '^\d+$') {
      $out.Add([int]$t)
      continue
    }

    throw "Invalid -IDs token '$t'. Use examples like '3,52..56,10' or '3,52-56,10'."
  }

  return $out.ToArray() | Sort-Object -Unique
}

# ---------------------------
# PRECHECKS
# ---------------------------
Assert-Exists $PsqlExe "psql.exe"
Assert-Exists $SignalsCsv "TrafficSignalIDandName.csv"

# Parse -IDs (Idea 1)
$SelectedIds = Parse-IdSpec $IDs
if ($SelectedIds.Count -gt 0) {
  Write-Host ("Limiting run to Signal IDs: {0}" -f (($SelectedIds | Sort-Object) -join ", ")) -ForegroundColor Cyan
}

# Event filter (Idea 2)
$NeededEvents = @(1,43)
if ($OnlyEventsNeeded) {
  Write-Host ("Only ingesting needed events: {0}" -f ($NeededEvents -join ", ")) -ForegroundColor Cyan
} else {
  Write-Host "Ingesting ALL events (OnlyEventsNeeded disabled)..." -ForegroundColor Yellow
}

# ---------------------------
# Determine "last completed hour" bucket
# ---------------------------
$now = Get-Date
$bucket = Truncate-ToHour ($now.AddHours(-1))
$bucketTag = $bucket.ToString("yyyy_MM_dd_HH") + "00"
Write-Host ("Ingesting last completed hour bucket: {0} (tag {1})" -f $bucket.ToString("yyyy-MM-dd HH:mm"), $bucketTag) -ForegroundColor Cyan

# ---------------------------
# Step 1: Drop + Create DB
# ---------------------------
Write-Host "Step 1: Recreating database cob..." -ForegroundColor Cyan

Run-Psql "postgres" @"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DbName' AND pid <> pg_backend_pid();
"@

Run-Psql "postgres" "DROP DATABASE IF EXISTS $DbName;"
Run-Psql "postgres" "CREATE DATABASE $DbName;"

# ---------------------------
# Step 2: Create tables + import signals
# ---------------------------
Write-Host "Step 2: Creating tables + importing signals..." -ForegroundColor Cyan

Run-Psql $DbName @"
CREATE TABLE IF NOT EXISTS signals (
  id   INT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS high_res (
  signal_id   INT NOT NULL REFERENCES signals(id),
  ts          TIMESTAMP NOT NULL,
  event_code  INT NOT NULL,
  parameter   BIGINT NULL,
  source_file TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_high_res_lookup
  ON high_res(signal_id, event_code, parameter, ts);
"@

$SignalsCsvPg = $SignalsCsv.Replace("\","\\")
Run-Psql $DbName "\copy signals(id,name) FROM '$SignalsCsvPg' WITH (FORMAT csv, HEADER true);"

# ---------------------------
# Step 2b: Download + build COPY file for high_res
# ---------------------------
Write-Host "Step 2b: Fetching Azure CSVs for this hour and building bulk load file..." -ForegroundColor Cyan

if (Test-Path $TempDir) { Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

"signal_id,ts,event_code,parameter,source_file" | Set-Content -LiteralPath $TempCopyCsv -Encoding ASCII

# Build IDs to process (avoid parsing psql output entirely)
if ($SelectedIds.Count -gt 0) {
  # If user specified -ID/-IDs, use that directly
  $ids = $SelectedIds | Sort-Object -Unique
} else {
  # Otherwise use the CSV as the canonical list (headers expected: ID,Name)
  $ids = Import-Csv -LiteralPath $SignalsCsv |
    ForEach-Object { $_.ID } |
    Where-Object { $_ -match '^\d+$' } |
    ForEach-Object { [int]$_ } |
    Sort-Object -Unique
}

Write-Host ("Signals in scope: {0}" -f $ids.Count) -ForegroundColor Gray

# warn if ID provided is not not valid
if ($SelectedIds.Count -gt 0) {
  $known = New-Object "System.Collections.Generic.HashSet[int]"
  foreach ($x in (Import-Csv -LiteralPath $SignalsCsv | ForEach-Object { $_.ID } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })) {
    [void]$known.Add($x)
  }
  $missing = $SelectedIds | Where-Object { -not $known.Contains([int]$_) }
  if ($missing.Count -gt 0) {
    Write-Host ("WARNING: These requested IDs are not in TrafficSignalIDandName.csv: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow
  }
}


$downloaded = 0
$rowsOut = 0

$missingAzure = New-Object System.Collections.Generic.List[int]
$hadAzure     = New-Object System.Collections.Generic.HashSet[int]


foreach ($id in $ids) {

  $url = "$AzureBase/SIEM_192.168.$id.11_$bucketTag.csv"

  if (-not (Test-AzureFileExists $url)) {
  $missingAzure.Add([int]$id) | Out-Null
  continue
  }


  $local = Join-Path $TempDir ("SIEM_192.168.{0}.11_{1}.csv" -f $id, $bucketTag)
  try {

       Download-File $url $local
       $downloaded++
       [void]$hadAzure.Add([int]$id)


    $lines = Get-Content -LiteralPath $local -ErrorAction Stop
    if ($lines.Count -lt 2) { continue }

    for ($i=1; $i -lt $lines.Count; $i++) {
      $line = $lines[$i].Trim()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }

      $parts = $line -split ","
      if ($parts.Count -lt 3) { continue }

      $tsRaw = $parts[0].Trim()
      $evRaw = $parts[1].Trim()
      $paRaw = $parts[2].Trim()

      if ($evRaw -notmatch '^-?\d+$') { continue }
      $ev = [int]$evRaw

      # Idea 2: only keep event codes needed for delay calcs
      if ($OnlyEventsNeeded -and ($NeededEvents -notcontains $ev)) { continue }

      $dt = $null
      try {
        $dt = [datetime]::ParseExact($tsRaw, "MM-dd-yyyy HH:mm:ss.f", $null)
      } catch {
        try { $dt = [datetime]::Parse($tsRaw) } catch { continue }
      }

      $param = $null
      if ($paRaw -match '^-?\d+$') { $param = [int64]$paRaw }

      $tsIso = $dt.ToString("yyyy-MM-dd HH:mm:ss.fff")
      $sourceFile = [IO.Path]::GetFileName($local)

      $out = @(
        $id,
        (Csv-Escape $tsIso),
        $ev,
        ($param -as [string]),
        (Csv-Escape $sourceFile)
      ) -join ","

      Add-Content -LiteralPath $TempCopyCsv -Value $out -Encoding ASCII
      $rowsOut++
    }

  } catch {
    Write-Host ("WARNING: failed to process ID {0}: {1}" -f $id, $_.Exception.Message) -ForegroundColor Yellow
    continue
  }
}

Write-Host ("Azure files downloaded: {0}" -f $downloaded) -ForegroundColor Gray
Write-Host ("Rows prepared for COPY: {0}" -f $rowsOut) -ForegroundColor Gray

if ($rowsOut -le 0) {
  Write-Host "No high_res rows found for the last hour for the selected signals." -ForegroundColor Yellow

  # Report missing Azure signals (and those that existed but were empty/filtered out)
  $requested = $ids | Sort-Object
  $missing = $missingAzure.ToArray() | Sort-Object -Unique
  $present  = @()
  foreach ($x in $requested) { if ($hadAzure.Contains([int]$x)) { $present += [int]$x } }
  $present = $present | Sort-Object -Unique

  if ($missing.Count -gt 0) {
    Write-Host ("No Azure file found for: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow
  }
  if ($present.Count -gt 0) {
    Write-Host ("Azure file WAS found for (but produced 0 ingested rows): {0}" -f ($present -join ", ")) -ForegroundColor Yellow
    Write-Host "Likely causes: file empty, or OnlyEventsNeeded filtered everything out, or no matching 1/43 events in that hour." -ForegroundColor Gray
  }

  exit 0
}

Write-Host "Bulk loading into high_res via \copy..." -ForegroundColor Cyan
$TempCopyCsvPg = $TempCopyCsv.Replace("\","\\")
Run-Psql $DbName "\copy high_res(signal_id,ts,event_code,parameter,source_file) FROM '$TempCopyCsvPg' WITH (FORMAT csv, HEADER true);"

# ---------------------------
# Step 3: Queries (with optional ID filter)
# ---------------------------

# Build an optional SQL filter for both queries when -IDs was specified
$idFilterSql = ""
if ($SelectedIds.Count -gt 0) {
  $arr = ($SelectedIds | Sort-Object | ForEach-Object { $_.ToString() }) -join ","
  $idFilterSql = " AND g.signal_id = ANY(ARRAY[$arr]::int[]) "
}

Write-Host "Step 3: Top 10 worst phase wait times (Event 1 minus immediately previous Event 43)..." -ForegroundColor Cyan

Run-Psql $DbName @"
WITH waits AS (
  SELECT
    g.signal_id,
    s.name,
    g.parameter AS phase,
    g.ts AS green_ts,
    c.ts AS call_ts,
    EXTRACT(EPOCH FROM (g.ts - c.ts)) AS wait_seconds
  FROM high_res g
  JOIN signals s ON s.id = g.signal_id
  JOIN LATERAL (
    SELECT ts
    FROM high_res c
    WHERE c.signal_id = g.signal_id
      AND c.event_code = 43
      AND c.parameter = g.parameter
      AND c.ts < g.ts
    ORDER BY c.ts DESC
    LIMIT 1
  ) c ON TRUE
  WHERE g.event_code = 1
    AND g.parameter IS NOT NULL
    $idFilterSql
)
SELECT
  signal_id,
  name,
  phase,
  green_ts,
  call_ts,
  ROUND(wait_seconds::numeric, 3) AS wait_seconds
FROM waits
ORDER BY wait_seconds DESC
LIMIT 10;
"@

Write-Host "Top 10 worst signals (sum of waits across phases)..." -ForegroundColor Cyan

Run-Psql $DbName @"
WITH waits AS (
  SELECT
    g.signal_id,
    EXTRACT(EPOCH FROM (g.ts - c.ts)) AS wait_minutes
  FROM high_res g
  JOIN LATERAL (
    SELECT ts
    FROM high_res c
    WHERE c.signal_id = g.signal_id
      AND c.event_code = 43
      AND c.parameter = g.parameter
      AND c.ts < g.ts
    ORDER BY c.ts DESC
    LIMIT 1
  ) c ON TRUE
  WHERE g.event_code = 1
    AND g.parameter IS NOT NULL
    $idFilterSql
)
SELECT
  w.signal_id,
  s.name,
  ROUND((SUM(w.wait_minutes) / 60.0)::numeric, 3) AS total_wait_minutes,
  COUNT(*) AS num_wait_events
FROM waits w
JOIN signals s ON s.id = w.signal_id
GROUP BY w.signal_id, s.name
ORDER BY total_wait_minutes DESC
LIMIT 10;
"@

# End-of-run note: which signals lacked Azure data for this last hour (include names)
$missing = $missingAzure.ToArray() | Sort-Object -Unique
if ($missing.Count -gt 0) {
  $arr = ($missing | ForEach-Object { $_.ToString() }) -join ","
  Write-Host ("NOTE: No Azure file found for these signals for bucket {0}:" -f $bucketTag) -ForegroundColor Yellow

  Run-Psql $DbName @"
SELECT id, name
FROM signals
WHERE id = ANY(ARRAY[$arr]::int[])
ORDER BY id;
"@
} else {
  Write-Host ("NOTE: Azure file found for all requested signals for bucket {0}." -f $bucketTag) -ForegroundColor Gray
}
