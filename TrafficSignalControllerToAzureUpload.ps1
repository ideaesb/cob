###############################################################################
#                          CITY OF BRYAN, TEXAS                               #
#                     PUBLIC WORKS, TRAFFIC OPERATIONS                        #
###############################################################################
#                                                                             #
#                TrafficSignalControllerToAzureUpload.ps1                     #
#                                                                             #
#  This Powershell shell script is designed to run as Windows Task.           #
#                                                                             #
#  It will only run on Windows since PerfLogTranslate.exe is a dependency     #
#  Must be Powershell 5.1 or higher but NOT 7+  since WinSCP is needed        #
#  for SFTP and its .NET libraries clash with Powershell 7 .NET               #
#                                                                             #
#  Default home for this script is C:\users\%user%\Documents\Signals          #
#                                                                             #
#  Dependencies, all files to be collocated (in exact same directory):        #
#                                                                             #
#    1.  TrafficSignalIPAddresses.csv with columns ID, Name, Switch,          #
#        Controller and Battery for the respective IP Addresses               #
#    2.  AzCopy.exe this must be executed once before executing this script   #
#        Remember to enter the current Windows Login User (NOT Azure Login)   #  
#        And in order for that, the Windows user must authenticate as         #
#        local organization (City of Bryan) and also be added as appropriate  #
#        (Blob Storage) Data Contributor in Azure, otherwise this AzCopy fail #
#        After the initial login and credentials storage, AzCopy will work    #
#        in batch mode.                                                       #  
#    3.  Public Private Key Files from Siemens, default.ppk, ATCnx4.4_rsa.ppk #     
#        WinSCP must be installed in its default directory, otherwise its     #
#        location of WinSCP.com must be specified by parameter $winscp        #
#        This dependency is required to SFTP using default.ppk provided       #
#        by Siemens which has a trusted certificate on the M60 controllers.   #
#        Most other tools such as Posh use open SSH and will require a        #
#        corresponding server certificate in EVERY controller.  Because of    # 
#        WinSCP .NET issues, need Powershell 5.1 (not Version 7)              #  
#    4.  PerfLogTranslate.exe - this must be provided by Siemens along with   #
#        it is user manual PIM223-008.pdf.  In this script it is used very    #
#        simply as PerfLogTranslate.exe -i *.dat (no multi-threaded calls!)   #
#        because we will be translating very few files, mostly just one from  #
#        the last hour                                                        #
#    5.  (Optional, only need if Windows Task Scheduler and Batch Processes   #
#        are blocked by IT policy from running when user session is inactive) #
#        PsExec64.exe and the cron job cronHourly.ps1. Usage from Windows     #
#        command shell (not Powershell):                                      #
#        psexec64.exe -d powershell.exe -NoProfile -File ".\ cronHourly.ps1"  #
#        Notice Powershell invoked as powershell.exe for 5.1 (for 7, pwsh.exe)#
#                                                                             #
###############################################################################
#                                                                             #
#   Version/History                                                           #
#                                                                             #
#   [Uday S. Kari 25-Jan-2026]  Initial Version                               #
#   [Uday S. Kari 28-Jan-2026]  More error traps and logging                  #
#                                                                             #
###############################################################################
# Requires -Version 5.1
<#
.SYNOPSIS
    Azure Sync for Traffic Signal High Resolution Data
.DESCRIPTION
    Robust end-to-end synchronization tool:
    1. Checks Azure for latest file.
    2. Checks Archive (R:) for newer files to populate Staging.
    3. Downloads remaining files from Controller (FTP/SFTP).
    4. Translates data to CSV.
    5. Transforms CSV (IP Replacement + Timezone Fix).
    6. Uploads to Azure.
    7. Archives files to Network Drive.
#>

# --- PARAMETERS ---
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [Alias("ID")]
    [string]$IDs,

    [Parameter(Mandatory=$false)]
    [string]$archiveRoot = "\\cfs\Data\Public Works\Traffic Operations\SIGNALS\Signal Controller Logs",

    [Parameter(Mandatory=$false)]
    [string]$ftpUser = "admin",

    [Parameter(Mandatory=$false)]
    [string]$ftpPassword = "`$adm*kon2"
)

$ScriptStart = Get-Date

$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop"

function Get-OneLineError {
    param([object]$Err)

    # Works for caught exceptions and error records
    $msg = $null
    try { $msg = $Err.Exception.Message } catch {}
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "$Err" }

    # collapse whitespace/newlines
    $msg = ($msg -replace '\s+', ' ').Trim()
    return $msg
}

# --- 0. PLATFORM CHECK ---
if ($PSVersionTable.PSVersion -lt [version]"5.1") {
    throw "This script requires PowerShell 5.1 or higher."
}
if ($PSVersionTable.PSVersion.Major -ge 7) {
    throw "This script must NOT run in PowerShell 7+ (pwsh.exe). Use Windows PowerShell 5.1 (powershell.exe)."
}

# --- 1. ENVIRONMENT SETUP ---

# --- PRE-RUN CLEANUP ---
Write-Host "Ensuring no previous AzCopy instances are running..." -ForegroundColor Gray
$AzProcesses = Get-Process -Name "azcopy" -ErrorAction SilentlyContinue
if ($AzProcesses) {
    Write-Host "Found $($AzProcesses.Count) stuck process(es). Terminating..." -ForegroundColor Yellow
    $AzProcesses | Stop-Process -Force
    Start-Sleep -Seconds 2 # Give Windows time to release file locks
}



$User = [Environment]::UserName
$ScriptHome = "C:\Users\$User\Documents\Signals"
Write-Host ("Checking Script Home = {0}" -f $ScriptHome) -ForegroundColor Gray

# Fallback if specific user folder doesn't exist, use current location
if (-not (Test-Path $ScriptHome)) {
    $ScriptHome = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ScriptHome)) { $ScriptHome = "." }
    Write-Host ("Script Home {0}\Documents\Signals Not Found, using current directory {1}" -f $User, $ScriptHome) -ForegroundColor Yellow
}

$LogFile = Join-Path $ScriptHome "PushTrafficSignalHighResolutionToAzure.log"
$StagingBase = Join-Path $ScriptHome "Staging"
$TrafficCsv = Join-Path $ScriptHome "TrafficSignalIPAddresses.csv"

# Ensure Log Exists
if (-not (Test-Path $LogFile)) { New-Item $LogFile -ItemType File -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Color="White", [switch]$NoConsole)
    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $LogLine = "[$TimeStamp] $Message"
    try { Add-Content -Path $LogFile -Value $LogLine -Force } catch {}
    if (-not $NoConsole) { Write-Host $Message -ForegroundColor $Color }
}

Write-Log "--- Sync Started ---" "Cyan"
Write-Log "Home: $ScriptHome" "Gray"

# --- 2. DEPENDENCY CHECK ---
$Deps = @("PerfLogTranslate.exe", "AzCopy.exe", "default.ppk", "ATCnx4.4_rsa.ppk", "TrafficSignalIPAddresses.csv")
$MissingDeps = @()
foreach ($file in $Deps) {
    if (-not (Test-Path (Join-Path $ScriptHome $file))) { $MissingDeps += $file }
}
# Missing deps
if ($MissingDeps.Count -gt 0) {
    Write-Log "FATAL: Missing dependencies in $ScriptHome : $($MissingDeps -join ', ')" "Red"
    throw "Missing dependencies: $($MissingDeps -join ', ')"
}

# Check WinSCP
$WinSCPPath = "C:\Program Files (x86)\WinSCP\WinSCP.com"
$SCP = $false
if (Test-Path $WinSCPPath) { $SCP = $true } 
else { Write-Log "WARNING: WinSCP not found. SFTP will not be possible." "Yellow" }
# Load WinSCP Assembly for .NET usage
$WinSCPDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
if (Test-Path $WinSCPDll) {
    try { Add-Type -Path $WinSCPDll -ErrorAction Stop }
    catch { $SCP = $false; Write-Log ("WARNING: Failed to load WinSCPnet.dll: {0}" -f (Get-OneLineError $_)) "Yellow" }


    if ($SCP) {
        try { [void][WinSCP.Session] } catch { $SCP = $false; Write-Log "WARNING: WinSCP types not available after Add-Type. Disabling SFTP." "Yellow" }
    }
}
if (-not $SCP) { Write-Log "WARNING: SFTP will not be possible." "Yellow" }


# CRITICAL: Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check Azure Access (TCP Method)
$AzureHost = "cob77803.blob.core.windows.net"
$AzureBase = "https://$AzureHost/siglog"
Write-Log "Checking Azure Connectivity..." "Gray"
try {
    $TcpTest = Test-NetConnection -ComputerName $AzureHost -Port 443 -InformationLevel Quiet
    if (-not $TcpTest) { throw "TCP Connect failed" }
} catch {
    Write-Log "FATAL: Cannot reach Azure Storage ($AzureHost). Check network." "Red"
    throw "Cannot reach Azure Storage ($AzureHost): $($_.Exception.Message)"
}

# --- 3. PARSE IDS & LOAD CSV ---
$SignalList = @()

# Import from CSV file that could have comments
$Headers = @("ID","Name","Switch","Controller","Battery")
$MasterList = @()

foreach ($line in Get-Content -Path $TrafficCsv) {
    if (-not $line) { continue }
    $t = $line.Trim()
    if ($t.Length -eq 0) { continue }

    # Ignore header row (commented or not)
    if ($t -match '^(#\s*)?ID\s*,') { continue }

    # Excluded structured row: "# 123,Name,Switch,Controller,Battery"
    if ($t -match '^\s*#\s*\d+\s*,') {
        $clean = ($t -replace '^\s*#\s*', '')
        try {
            $obj = $clean | ConvertFrom-Csv -Header $Headers
            $obj | Add-Member -NotePropertyName Excluded -NotePropertyValue $true -Force
            $obj.ID = ($obj.ID -replace '\D', '')
            $MasterList += $obj
        } catch {
            # ignore malformed commented rows
        }
        continue
    }

    # Normal structured row: "123,Name,Switch,Controller,Battery"
    if ($t -match '^\s*\d+\s*,') {
        try {
            $obj = $t | ConvertFrom-Csv -Header $Headers
            $obj | Add-Member -NotePropertyName Excluded -NotePropertyValue $false -Force
            $obj.ID = ($obj.ID -replace '\D', '')   # keep consistent with commented rows
            $MasterList += $obj
        } catch {
            # ignore malformed rows
        }
        continue
    }

    # Anything else is a junk/comment line; ignore
}

# Keep only rows with numeric IDs (active or excluded)
$MasterList = $MasterList | Where-Object { $_.ID -match '^\d+$' }

# --- CLI Override Set (IDs explicitly requested) ---
$CliIDSet = $null

# If $IDs provided, parse. Else use all from CSV.
if (-not [string]::IsNullOrWhiteSpace($IDs)) {

    $RawIDs = @()

    # Parse "1, 3..5" syntax
    $Parts = $IDs -split ','
    foreach ($P in $Parts) {
        $Clean = $P.Trim()
        if ($Clean -match '(\d+)\.\.(\d+)') {
            $Start = [int]$matches[1]
            $End   = [int]$matches[2]
            # (PowerShell range handles Start > End too, but keep explicit)
            if ($Start -le $End) { $RawIDs += ($Start..$End) } else { $RawIDs += ($Start..$End) }
        } elseif ($Clean -match '^\d+$') {
            $RawIDs += [int]$Clean
        }
    }

    $RawIDs = $RawIDs | Select-Object -Unique | Sort-Object

    # Build fast lookup for "explicit CLI IDs"
    $CliIDSet = @{}
    foreach ($x in $RawIDs) { $CliIDSet[[int]$x] = $true }

    # Build SignalList from CSV rows (including commented-out rows!)
    foreach ($RId in $RawIDs) {
        $Found = $MasterList | Where-Object { [int]$_.ID -eq [int]$RId }
        if ($Found) { $SignalList += $Found }
        else {
            # OPTIONAL: if user types an ID not present in CSV at all,
            # include a placeholder row so they get a clear "missing controller IP" skip later.
            $SignalList += [PSCustomObject]@{
                ID         = [string]$RId
                Name       = "Unknown (not in CSV)"
                Switch     = ""
                Controller = ""
                Battery    = ""
                Excluded   = $false
            }
        }
    }

} else {
    $SignalList = $MasterList
}

Write-Log "Processing $($SignalList.Count) signals..." "Cyan"


# --- HELPER FUNCTIONS ---

function Remove-TreeSafe {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) { return }

    for ($i=1; $i -le 3; $i++) 
    {
      try 
      {
        Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -ErrorAction Stop
        break
      } catch {
        Start-Sleep -Seconds 2
        if ($i -eq 3) { Write-Log "   Warning: Could not remove $Path after retries." "Yellow" }
     }
   }
}

function Get-AzureLastDate {
    <#
      Returns the latest hour-bucket datetime that exists in Azure for a given signal ID,
      based on file naming: SIEM_192.168.<SigID>.11_yyyy_MM_dd_HH00.csv

      - Fast: checks recent hours first (last ~72 hours)
      - Safe: never assumes something is missing unless we prove it
      - Robust: falls back to day-level then month-level probes if needed

      Output: [datetime] or $null if nothing found.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(1,999)]
        [int]$SigID,

        [Parameter(Mandatory=$false)]
        [int]$LookbackHours = 72,

        [Parameter(Mandatory=$false)]
        [datetime]$LimitDate = (Get-Date -Year 2025 -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0)
    )

    if ([string]::IsNullOrWhiteSpace($AzureBase)) {
        throw "Get-AzureLastDate requires `$AzureBase to be set (e.g. https://<account>.blob.core.windows.net/siglog)."
    }

    # --- Helpers ---
    $MkUrl = {
        param([datetime]$Dt)
        # normalize to hour bucket
        $dtHour = Get-Date -Year $Dt.Year -Month $Dt.Month -Day $Dt.Day -Hour $Dt.Hour -Minute 0 -Second 0 -Millisecond 0
        "$AzureBase/SIEM_192.168.$SigID.11_$($dtHour.ToString('yyyy_MM_dd_HH'))00.csv"
    }

    function Test-Url {
        param([string]$U)
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $U -Method Head -ErrorAction Stop
            return ($r.StatusCode -eq 200)
        } catch {
            $code = $null
            try { $code = $_.Exception.Response.StatusCode.Value__ } catch {}
            return ($code -in 401,403)  # exists but access denied
        }
   }


    function Trunc-ToHour {
        param([datetime]$dt)
        Get-Date -Year $dt.Year -Month $dt.Month -Day $dt.Day -Hour $dt.Hour -Minute 0 -Second 0 -Millisecond 0
    }

    # We only consider completed hours (avoid "current partial hour")
    $now = Get-Date
    $end = Trunc-ToHour ($now.AddHours(-1))

    # ---------- Phase 1: Hour-by-hour recent scan (fast & deterministic) ----------
    $start = $end.AddHours(-$LookbackHours)
    if ($start -lt $LimitDate) { $start = $LimitDate }

    for ($t = $end; $t -ge $start; $t = $t.AddHours(-1)) {
        if (Test-Url (& $MkUrl $t)) {
            return (Trunc-ToHour $t)
        }
    }

    # ---------- Phase 2: Day probes for older data (check last ~120 days) ----------
    $dayEnd = $start.AddHours(-1)
    if ($dayEnd -lt $LimitDate) { return $null }

    $maxDays = 120
    $d0 = Trunc-ToHour $dayEnd
    $dStart = $d0.AddDays(-$maxDays)
    if ($dStart -lt $LimitDate) { $dStart = $LimitDate }

    # Probe midday first (most likely to exist if any file exists that day), then a few other hours.
    $probeHours = @(12, 18, 8, 0, 23)

    $foundDayAnchor = $null

    for ($day = $d0.Date; $day -ge $dStart.Date; $day = $day.AddDays(-1)) {
        foreach ($h in $probeHours) {
            $t = (Get-Date -Year $day.Year -Month $day.Month -Day $day.Day -Hour $h -Minute 0 -Second 0 -Millisecond 0)
            if ($t -lt $LimitDate) { continue }
            if (Test-Url (& $MkUrl $t)) {
                $foundDayAnchor = $t
                break
            }
        }
        if ($foundDayAnchor) { break }
    }

    if (-not $foundDayAnchor) {
        # ---------- Phase 3: Month probes down to LimitDate ----------
        $m = Get-Date -Year $d0.Year -Month $d0.Month -Day 1 -Hour 12 -Minute 0 -Second 0 -Millisecond 0
        while ($m -ge $LimitDate) {
            if (Test-Url (& $MkUrl $m)) {
                $foundDayAnchor = $m
                break
            }
            $m = $m.AddMonths(-1)
        }
        if (-not $foundDayAnchor) { return $null }
    }

    # ---------- Phase 4: Find exact latest hour near the anchor ----------
    # We now know *something* exists at/near $foundDayAnchor, but not which hour is the latest.
    # Strategy:
    #   1) Find an upper bound hour that is missing by walking forward up to 48 hours.
    #   2) Binary search between last-known-good and first-known-missing.
    $low = Trunc-ToHour $foundDayAnchor
    if (-not (Test-Url (& $MkUrl $low))) {
        # If anchor hour itself doesn't exist (rare), walk backward a bit within the day to find a real low.
        $backFound = $false
        for ($i=1; $i -le 24; $i++) {
            $cand = $low.AddHours(-$i)
            if ($cand -lt $LimitDate) { break }
            if (Test-Url (& $MkUrl $cand)) { $low = $cand; $backFound = $true; break }
        }
        if (-not $backFound) { return $null }
    }

    $high = $low
    $missingFound = $false
    for ($i=1; $i -le 48; $i++) {
        $cand = $low.AddHours($i)
        # don't search into future (past completed hour)
        if ($cand -gt $end) { $high = $end.AddHours(1); $missingFound = $true; break }

        if (-not (Test-Url (& $MkUrl $cand))) {
            $high = $cand
            $missingFound = $true
            break
        }
    }
    if (-not $missingFound) {
        # Could not find a missing hour within +48; set a safe high bound (end+1)
        $high = $end.AddHours(1)
    }

    $best = $low

    while (($high - $low).TotalHours -gt 1) {
        $mid = $low.AddHours([math]::Floor((($high - $low).TotalHours) / 2))
        if ($mid -gt $end) { $high = $mid; continue }

        if (Test-Url (& $MkUrl $mid)) {
            $best = $mid
            $low = $mid
        } else {
            $high = $mid
        }
    }

    return (Trunc-ToHour $best)
}


function Truncate-ToHour {
    param (
        [datetime]$DateTime = (Get-Date)  # The datetime to truncate, defaulting to the current time
    )
    # Truncate by setting minutes, seconds, and milliseconds to zero
    $TruncatedDateTime = Get-Date -Year $DateTime.Year -Month $DateTime.Month -Day $DateTime.Day -Hour $DateTime.Hour -Minute 0 -Second 0
    # This does not seem to be exact $TruncatedDateTime = $DateTime.Date.AddHours($DateTime.Hour)
    return $TruncatedDateTime
}

function Is-From-Less-Or-Equal-ByHour {
    param (
        [datetime]$FromDate,  # The earlier datetime
        [datetime]$ToDate     # The later datetime
    )

    # Truncate both dates to the hour for accurate comparison
    $FromDateByHour = $FromDate.Date.AddHours($FromDate.Hour)
    $ToDateByHour = $ToDate.Date.AddHours($ToDate.Hour)

    # Compare the truncated dates
    return $FromDateByHour -le $ToDateByHour
}


# --- 5. MAIN PROCESSING LOOP ---
$Summary = @()

foreach ($Sig in $SignalList) {

    # Validate ID
    if ($Sig.ID -notmatch '^\d+$') { Write-Log "Skipping invalid ID: $($Sig.ID)" "Yellow"; continue }
    $IDVal = [int]$Sig.ID
    if ($IDVal -lt 1 -or $IDVal -gt 999) { Write-Log "ID $IDVal out of range (1-999). Skipping." "Yellow"; continue }

    # --- CLI override vs CSV-commented row ---
    $IsExcluded = ($Sig.PSObject.Properties.Match("Excluded").Count -gt 0 -and [bool]$Sig.Excluded)
    $CliOverride = $false
    if ($CliIDSet) {
        try { $CliOverride = $CliIDSet.ContainsKey($IDVal) } catch { $CliOverride = $false }
    }

    # If excluded AND not explicitly requested, skip (original behavior)
    if ($IsExcluded -and -not $CliOverride) {
        $Name = if ($Sig.Name) { $Sig.Name } else { "Unknown" }
        Write-Log "----------------------------------------------------------------" "Gray"
        Write-Log ("ID {0}: {1} skipped (commented out in input CSV)." -f $IDVal, $Name) "DarkGray"
        $Summary += [PSCustomObject]@{
            ID     = $IDVal
            Name   = $Name
            Status = "Skipped (commented out in input)"
            From   = $null
            To     = $null
            Count  = 0
        }
        continue
    }

    # If excluded BUT CLI requested, process anyway
    if ($IsExcluded -and $CliOverride) {
        Write-Log ("NOTE: ID {0} is commented out in CSV, but processing anyway due to CLI override." -f $IDVal) "Yellow"
    }

    $Name = if ($Sig.Name) { $Sig.Name } else { "Unknown" }
    Write-Log "----------------------------------------------------------------" "Gray"
    Write-Log "Processing ID ${IDVal}: $Name" "Cyan"

    # (rest of your loop remains unchanged...)



    $SwitchIP = ("" + $Sig.Switch).Trim()   # safe for powershell 5.1
    $CtrlIP   = $Sig.Controller

    # --- VALIDATIONS ---
    # Do some cheap validation for known patterns in City of Bryan Traffic Signal Controller IP Addresses
    # Basically, Controller IP must be present and match the pattern 10.105.[0-5].y, whereby y is 0-255
    # In case wondering about cleaning Switch IP it is pattern free - we have BNS names for them like texas_villamaria-ie3000.cobnet.org, so could be entered into the csv files as such any string

    $ctrl = ("" + $CtrlIP).Trim() # safe for powershell 5.1

    $octetY  = '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'   # 0–255
    $ctrlPat = "^10\.105\.[0-5]\.$octetY$"

    if ([string]::IsNullOrWhiteSpace($ctrl)) {
        Write-Log "   Missing Controller IP in CSV. Skipping." "Yellow"
        $Summary += [PSCustomObject]@{
            ID=$IDVal; Name=$Name; Status="Skipped (Missing Controller IP)"; From=$null; To=$null; Count=0
        }
        if (-not [string]::IsNullOrWhiteSpace($StagingFolder)) { Remove-TreeSafe $StagingFolder }
        continue
    }

    if ($ctrl -notmatch $ctrlPat) {
        Write-Log ("   Invalid Controller IP in CSV: '{0}'. Expected 10.105.[0-5].y." -f $CtrlIP) "Yellow"
        $Summary += [PSCustomObject]@{
            ID=$IDVal; Name=$Name; Status="Skipped (Invalid Controller IP)"; From=$null; To=$null; Count=0
        }
        if (-not [string]::IsNullOrWhiteSpace($StagingFolder)) { Remove-TreeSafe $StagingFolder }
        continue
    }

    # Normalize after validation
    $CtrlIP = $ctrl




    # Organize Folder Names
    $PaddedID = "{0:D3}" -f $IDVal
    $SafeName = $Name -replace '[\\/:*?"<>|&@]', '_'
    $SignalFolder = "${PaddedID}_${SafeName}"
    $StagingFolder = Join-Path $StagingBase $SignalFolder
    
    if (Test-Path $StagingFolder) { Remove-TreeSafe $StagingFolder}
    New-Item $StagingFolder -ItemType Directory -Force | Out-Null
    
    # Archive Paths
    $ArchSigFolder = Get-ChildItem -Path $archiveRoot -Directory -Filter "${PaddedID}*" | Select-Object -First 1
    if (-not $ArchSigFolder) {
        $ArchPath = Join-Path $archiveRoot "${PaddedID}_$SafeName"
        New-Item $ArchPath -ItemType Directory -Force | Out-Null
        $ArchSigFolder = Get-Item $ArchPath
    }
    $DataArchDest = Join-Path $ArchSigFolder.FullName "data"
    $CsvArchDest  = Join-Path $ArchSigFolder.FullName "csv"
    if (-not (Test-Path $DataArchDest)) { New-Item $DataArchDest -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $CsvArchDest))  { New-Item $CsvArchDest -ItemType Directory -Force | Out-Null }

    # Step 1: Azure Date
    $LastAz = Get-AzureLastDate -SigID $IDVal
    if (-not $LastAz) {
        Write-Log "   No Azure files found. Starting from Jan 01, 2026." "Yellow"
        $LastAz = Get-Date -Year 2026 -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0
    } else {
        Write-Log "   Last Azure Date: $($LastAz.ToString('yyyy-MM-dd HH:mm'))" "Green"
    }

    # Calculate the Hypothetical Extraction Range 
    # from (and inclusive) Last Azure Date Plus One Hour to (inclusive of) One Hour Prior to Current ("Now") Top-of-the-Hour. 

    $OneHourAfterLastestAzureFileTimeStamp = Truncate-ToHour $LastAz.AddHours(1)
    Write-Log "   One Hour After Lastest Azure File TimeStamp: $($OneHourAfterLastestAzureFileTimeStamp.ToString('yyyy-MM-dd HH:mm'))" "Green"

    $Now = Get-Date
    Write-Log "   It is now: $($Now.ToString('yyyy-MM-dd HH:mm'))" "Green"


    $OneHourBeforeCurrentTopOfTheHour = Truncate-ToHour $Now.Date.AddHours($Now.Hour - 1)
    Write-Log "   One Hour Before Current Top Of The Hour: $($OneHourBeforeCurrentTopOfTheHour.ToString('yyyy-MM-dd HH:mm'))" "Green"
    
    # Build File List
    $FileList = [System.Collections.Generic.List[string]]::new()
    if ($OneHourAfterLastestAzureFileTimeStamp -le $OneHourBeforeCurrentTopOfTheHour) 
    {
       # this is the normal case - Azure timestamps are older that now, usually by much
       $Iter = Truncate-ToHour $OneHourAfterLastestAzureFileTimeStamp
       Write-Log "   Iterator Start : $($Iter.ToString('yyyy-MM-dd HH:mm'))" "Green"    

        while (Is-From-Less-Or-Equal-ByHour -FromDate $Iter -ToDate $OneHourBeforeCurrentTopOfTheHour) {
          $Tag = $Iter.ToString("yyyy_MM_dd_HH00")
          $FName = "SIEM_$($CtrlIP)_${Tag}.dat"
          [void]$FileList.Add($FName)
          Write-Log "   Add filename: $FName to Extraction List" "Green" 
          $Iter = Truncate-ToHour $Iter.AddHours(1)
          Write-Log "   Iterator Next: $($Iter.ToString('yyyy-MM-dd HH:mm'))" "Green" 
       }

       $TotalNeeded = $FileList.Count
       Write-Log "   Need $TotalNeeded files ($($FileList[0]) to $($FileList[$FileList.Count-1]))..." "Gray"
    }
    else 
    {
        Write-Log "   Up to date. Skipping." "Green"
        $Summary += [PSCustomObject]@{
           ID=$IDVal
           Name=$Name
           Status="Skipped (Up to date)"
           From=$LastAz
           To=$LastAz
           Count=0
        }

        Remove-TreeSafe $StagingFolder
        continue
    }



    $FoundCount = 0
    
    # Step 2: Check Archive First - this is how we add the files manually retreived from the controller (data diaper)
    foreach ($File in $FileList.ToArray()) {
        $ArchPath = Join-Path $DataArchDest $File
        if (Test-Path $ArchPath) {
            Copy-Item $ArchPath -Destination $StagingFolder -Force
            [void]$FileList.Remove($File)
            $FoundCount++
        }
    }

    if ($FoundCount -gt 0) { Write-Log "   Found $FoundCount files in Archive." "Cyan" }

    # Step 3: Controller Download
    if ($FileList.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($CtrlIP) -and $SCP) {

        $Session = New-Object WinSCP.Session
        $Connected = $false
        $RemoteRoot = ""

        try {
            $Strategies = @(
                @{ Type="FTP";  User=$ftpUser; Pass=$ftpPassword; Key=$null },
                @{ Type="SFTP"; User="admin";  Pass=$null;       Key=(Join-Path $ScriptHome "default.ppk") },
                @{ Type="SFTP"; User="admin";  Pass=$null;       Key=(Join-Path $ScriptHome "ATCnx4.4_rsa.ppk") }
            )

            foreach ($Strat in $Strategies) {
                try {
                    $Opt = New-Object WinSCP.SessionOptions
                    $Opt.HostName = $CtrlIP
                    $Opt.UserName = $Strat.User
                    $Opt.TimeoutInMilliseconds = 8000

                    if ($Strat.Type -eq "FTP") {
                        $Opt.Protocol = [WinSCP.Protocol]::Ftp
                        $Opt.Password = $Strat.Pass
                    } else {
                        $Opt.Protocol = [WinSCP.Protocol]::Sftp
                        $Opt.SshPrivateKeyPath = $Strat.Key
                        $Opt.GiveUpSecurityAndAcceptAnySshHostKey = $true
                    }

                    if ($Session.Opened) { $Session.Dispose(); $Session = New-Object WinSCP.Session }
                    $Session.Open($Opt)

                    if ($Session.FileExists("/mnt/sd"))      { $RemoteRoot="/mnt/sd" }
                    elseif ($Session.FileExists("/mount/sd")){ $RemoteRoot="/mount/sd" }
                    elseif ($Session.FileExists("/media/sd")){ $RemoteRoot="/media/sd" }

                    if ($RemoteRoot) {
                        $Connected = $true
                        Write-Log "   Connected via $($Strat.Type) ($($Strat.Key))." "Green"
                        break
                    }
                } catch {
                    $e = Get-OneLineError $_
                    Write-Log ("   Connection failed ({0}): {1}" -f $Strat.Type, $e) "Yellow"
                    # try next strategy
                    continue
                }
            }

            if ($Connected) {
                $DlCount = 0
                foreach ($File in $FileList.ToArray()) {
                    $RP = "$RemoteRoot/$File".Replace("//","/")
                    $LP = Join-Path $StagingFolder $File
                    try {
                        if ($Session.FileExists($RP)) {
                            $Session.GetFiles($RP, $LP).Check()
                            [void]$FileList.Remove($File)
                            $FoundCount++; $DlCount++
                        }
                    } catch {
                        $e = Get-OneLineError $_
                        Write-Log ("   Download check failed: {0}" -f $e) "Yellow"
                        if ($e -match 'unexpectedly closed|Lost connection|Timeout detected') {
                            Write-Log "   Session appears dead; abandoning remaining downloads this run." "Yellow"
                            break
                        }
                    }
                }
                Write-Log "   Downloaded $DlCount files from Controller." "Cyan"
            } else {
                # Ping check
                if ($SwitchIP) {
                    $Ping = Test-Connection $SwitchIP -Count 1 -ErrorAction SilentlyContinue
                    if ($Ping) { 
                        Write-Log ("   Controller Unreachable, Switch OK ({0}ms)" -f $Ping.ResponseTime) "Magenta" 
                    } else { Write-Log "   Switch Unreachable" "Red" }
                } else {
                    Write-Log "   Controller Unreachable (Cannot reach Switch $SwitchIP)" "Red"
                }
            }
        }
        finally {
            if ($Session) { $Session.Dispose() }
        }
    }


    # Step 6: Verify Found Files
    if ($FoundCount -eq 0) {
        Write-Log "   No files found (Archive or Controller). Skipping." "Yellow"
        Remove-TreeSafe $StagingFolder
        $Summary += [PSCustomObject]@{
          ID     = $IDVal
          Name   = $Name
          Status = "Skipped (No Files)"
          From   = $LastAz
          To     = $LastAz
          Count  = 0
        }
        continue
    }

    # Step 6b: Translate
    Write-Log "   Translating $FoundCount files..." "Cyan"
    # some cheap protection against Set-Location failure   
    try { Set-Location -LiteralPath $StagingFolder } catch {
      Write-Log ("   FATAL: Cannot Set-Location to StagingFolder: {0}" -f (Get-OneLineError $_)) "Red"
      continue
    }
    $TransExe = Join-Path $ScriptHome "PerfLogTranslate.exe"
    # Execute natively within Staging directory
    try { & $TransExe -i *.dat | Out-Null } catch { Write-Log "   Translate Error: $_" "Red" }
    # get out of there to then be able to delete Statging area later
    Set-Location $ScriptHome 
    
    # Step 7: Normalize CSVs (rename + fix line1 + optional timezone fix)
    $Csvs = Get-ChildItem -Path $StagingFolder -Filter "*.csv" -ErrorAction SilentlyContinue

    foreach ($C in $Csvs) {

        # Expect: SIEM_<anything>_yyyy_MM_dd_HH00.csv
        if ($C.Name -notmatch 'SIEM_.*_(\d{4}_\d{2}_\d{2}_\d{4})\.csv$') {
            Write-Log "   WARNING: Unexpected CSV name, skipping: $($C.Name)" "Yellow"
            continue
        }

        $TS = $matches[1]
        $NewName = "SIEM_192.168.$IDVal.11_$TS.csv"
        $NewPath = Join-Path $StagingFolder $NewName

        # Read all lines safely
        $Content = $null
        try {
            $Content = Get-Content -LiteralPath $C.FullName -ErrorAction Stop
        } catch {
            Write-Log ("   WARNING: Could not read CSV; deleting: {0} ({1})" -f $C.Name, (Get-OneLineError $_)) "Yellow"
            Remove-TreeSafe -Path $C.FullName
            continue
        }

        # If the translator produced an empty/garbage CSV, kill it so it cannot upload.
        if ($null -eq $Content -or $Content.Count -lt 1) {
            Write-Log "   WARNING: Empty/invalid CSV from translator; deleting: $($C.Name)" "Yellow"
            Remove-TreeSafe -Path $C.FullName
            continue
        }

        # Always fix Line 1 (even if file is short)
        $Content[0] = "192.168.$IDVal.11,,"

        # Only do timezone adjustment if we have at least 3 lines (your original logic)
        if ($Content.Count -gt 2) {

            # Parse file bucket date from TS
            $FileYear  = [int]$TS.Substring(0,4)
            $FileMonth = [int]$TS.Substring(5,2)
            $FileDay   = [int]$TS.Substring(8,2)
            $FileHour  = [int]$TS.Substring(11,2)
            $FileDate  = Get-Date -Year $FileYear -Month $FileMonth -Day $FileDay -Hour $FileHour -Minute 0 -Second 0 -Millisecond 0

            $HeaderLines = $Content[0..1]
            $DataLines   = $Content[2..($Content.Count-1)]

            $UpdatedData = foreach ($Line in $DataLines) {
                if ([string]::IsNullOrWhiteSpace($Line)) { $Line; continue }

                $Cols = $Line -split ','
                try {
                    $RowDt = [datetime]::ParseExact($Cols[0].Trim(), "MM-dd-yyyy HH:mm:ss.f", $null)
                    $RowBucket = Get-Date -Year $RowDt.Year -Month $RowDt.Month -Day $RowDt.Day -Hour $RowDt.Hour -Minute 0 -Second 0 -Millisecond 0

                    $Diff  = $FileDate - $RowBucket
                    $HDiff = $Diff.TotalHours
                    # usually if file content is on zulu time, HDiff will be +5 or +6 (CDT/CST)
                    # only adjust if within reasonable range
                    if ([Math]::Abs($HDiff) -ge 1 -and [Math]::Abs($HDiff) -le 7) {
                        $NewDt = $RowDt.AddHours($HDiff)
                        $Cols[0] = $NewDt.ToString("MM-dd-yyyy HH:mm:ss.f")
                        $Cols -join ','
                    } else {
                        $Line
                    }
                } catch {
                    $Line
                }
            }

            $Content = $HeaderLines + $UpdatedData
        }
        else {
            # Too short to be a real dataset — treat as failed conversion; delete so it can't upload.
            Write-Log "   WARNING: CSV has <3 lines (likely failed conversion); deleting: $($C.Name)" "Yellow"
            Remove-TreeSafe -Path $C.FullName
            continue
        }

        # Write normalized file (then delete old if different)
        try {
            $Content | Set-Content -LiteralPath $NewPath -Force

            if ($NewPath -ne $C.FullName) {
                Remove-TreeSafe -Path $C.FullName
            }

        } catch {
            Write-Log ("   WARNING: Failed to write normalized CSV; deleting both: {0} ({1})" -f $C.Name, (Get-OneLineError $_)) "Yellow"
            Remove-TreeSafe -Path $C.FullName
            Remove-TreeSafe -Path $NewPath
            continue
        }
    }


    # Step 8: Upload
    $AzCopyExe = Join-Path $ScriptHome "AzCopy.exe"
    $DestUrl = "https://cob77803.blob.core.windows.net/siglog"
    # --overwrite=true is key
    # This will tightly match only the files for this signal ID, prevents the “SIEM_10.105…” files from ever going up to Azure Cloud, even if something slips.
    $AzArgs = "copy `"$StagingFolder\SIEM_192.168.$IDVal.11_*.csv`" `"$DestUrl`" --overwrite=true --block-blob-tier=Cool --log-level=ERROR"
    $Proc = Start-Process -FilePath $AzCopyExe -ArgumentList $AzArgs -NoNewWindow -PassThru -Wait
    
    if ($Proc.ExitCode -eq 0) {
        Write-Log "   Upload Success." "Green"
        $Summary += [PSCustomObject]@{ID=$IDVal; Name=$Name; Status="Success"; From=$OneHourAfterLastestAzureFileTimeStamp; To=$OneHourBeforeCurrentTopOfTheHour; Count=$FoundCount}
    } else {
        Write-Log "   Upload Failed." "Red"
        $Summary += [PSCustomObject]@{ID=$IDVal; Name=$Name; Status="Failed Upload"; Count=$FoundCount}
    }

    # Step 9: Archive & Cleanup
    Write-Log "   Archiving..." "Gray"
    Get-ChildItem -Path $StagingFolder -Filter "*.dat" -ErrorAction SilentlyContinue | Move-Item -Destination $DataArchDest -Force
    Get-ChildItem -Path $StagingFolder -Filter "*.csv" -ErrorAction SilentlyContinue | Move-Item -Destination $CsvArchDest  -Force

    
    # Make sure get out of Staging Area before clean-up
    Set-Location $ScriptHome

    if (-not (Test-Path -LiteralPath $StagingFolder)) {
        # already gone
    }
    else {
        $items = @(Get-ChildItem -LiteralPath $StagingFolder -ErrorAction SilentlyContinue)
        if ($items.Count -eq 0) {
            Remove-TreeSafe $StagingFolder
        } else {
            Write-Log "   Warning: Staging folder not empty." "Yellow"
        }
    }


}

# Final Summary
if (-not $Summary -or $Summary.Count -eq 0) {
    Write-Log "No summary rows were produced; nothing to print." "Yellow"
}
else 
{
        
    Write-Log "--- FINAL SUMMARY ---" "Cyan"

    # Define column widths (tuned to your data)
    function Get-MaxLen {
        param(
            [string]$Header,
            [string[]]$Values,
            [int]$Cap = 60
        )
        $lens = @($Header.Length)
        foreach ($v in $Values) {
            if ($null -eq $v) { continue }
            $lens += ([string]$v).Length
        }
        $m = ($lens | Measure-Object -Maximum).Maximum
        return [Math]::Min($Cap, [int]$m)
    }

    function Fit {
        param(
            [AllowNull()][object]$Value,
            [int]$Width
        )
        $s = if ($null -eq $Value) { "" } else { [string]$Value }
        if ($s.Length -le $Width) { return $s }
        if ($Width -le 3) { return $s.Substring(0, $Width) }
        return ($s.Substring(0, $Width - 3) + "...")
    }

    try
    {
        $display = foreach ($row in $Summary) {
            $when =
                if ($row.Status -like "Success*") {
                    "{0} -> {1}" -f
                        $row.From.ToString("M/d/yyyy h:mm tt"),
                        $row.To.ToString("M/d/yyyy h:mm tt")
                }
                elseif ($row.Status -like "Skipped (commented out in input)*") {
                    ""
                }
                elseif ($row.From -is [datetime]) {
                    "Last Azure: {0}" -f $row.From.ToString("M/d/yyyy h:mm tt")
                }
                else {
                    "Last Azure: unknown"
                }

            [PSCustomObject]@{
                ID     = [string]$row.ID
                Name   = [string]$row.Name
                Status = [string]$row.Status
                When   = [string]$when
                Count  = [string]$row.Count
            }
        }

        $maxCol = 60

        $wID     = Get-MaxLen -Header "ID"                    -Values ($display.ID)     -Cap $maxCol
        $wName   = Get-MaxLen -Header "Name"                  -Values ($display.Name)   -Cap $maxCol
        $wStatus = Get-MaxLen -Header "Status"                -Values ($display.Status) -Cap $maxCol
        $wWhen   = Get-MaxLen -Header "From / To / Last Azure" -Values ($display.When)   -Cap $maxCol
        $wCount  = Get-MaxLen -Header "Count"                 -Values ($display.Count)  -Cap $maxCol

        $fmt = "{0,$wID} {1,-$wName} {2,-$wStatus} {3,-$wWhen} {4,$wCount}"


        # Headers
        Write-Host ($fmt -f "ID","Name","Status","From / To / Last Azure","Count") -ForegroundColor Cyan
        Write-Host ($fmt -f ("-"*$wID), ("-"*$wName), ("-"*$wStatus), ("-"*$wWhen), ("-"*$wCount)) -ForegroundColor Cyan

        # Rows
        foreach ($row in $Summary) {

            $when =
                if ($row.Status -like "Success*") {
                    "{0} -> {1}" -f
                        $row.From.ToString("M/d/yyyy h:mm tt"),
                        $row.To.ToString("M/d/yyyy h:mm tt")
                }
                elseif ($row.Status -like "Skipped (commented out in input)*") {
                    ""
                }
                elseif ($row.From -is [datetime]) {
                    "Last Azure: {0}" -f $row.From.ToString("M/d/yyyy h:mm tt")
                }
                else {
                    "Last Azure: unknown"
                }

            $color =
                if ($row.Status -like "Success*") { "Green" }
                elseif ($row.Status -like "Skipped (Up to date)*") { "DarkGray" }
                elseif ($row.Status -like "Skipped (commented out in input)*") { "DarkGray" }
                elseif ($row.Status -like "Skipped (No Files)*") { "Yellow" }
                elseif ($row.Status -like "Failed*") { "Red" }
                else { "White" }

            Write-Host (
                $fmt -f
                    (Fit $row.ID     $wID),
                    (Fit $row.Name   $wName),
                    (Fit $row.Status $wStatus),
                    (Fit $when       $wWhen),
                    (Fit $row.Count  $wCount)
            ) -ForegroundColor $color
        }

        # Still write a clean, uncolored table to the log file
        $Summary | Format-Table -AutoSize | Out-File $LogFile -Append

        $ScriptEnd = Get-Date
        $Duration = New-TimeSpan -Start $ScriptStart -End $ScriptEnd

        Write-Host ""
        Write-Host ("Script Start : {0}" -f $ScriptStart.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Gray
        Write-Host ("Script End   : {0}" -f $ScriptEnd.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Gray
        Write-Host ("Elapsed Time : {0:hh\:mm\:ss}" -f $Duration) -ForegroundColor Cyan

        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value ("Script Start : {0}" -f $ScriptStart)
        Add-Content -Path $LogFile -Value ("Script End   : {0}" -f $ScriptEnd)
        Add-Content -Path $LogFile -Value ("Elapsed Time : {0}" -f $Duration)
    }
    catch 
    {
      Write-Log ("Summary section failed: {0}" -f (Get-OneLineError $_)) "Red"
    }
}
