###############################################################################
#                          CITY OF BRYAN, TEXAS                               #
#                     PUBLIC WORKS, TRAFFIC OPERATIONS                        #
###############################################################################
#                                                                             #
#                TrafficSignalControllerToAzureUpload.ps1                     #
#                                                                             #
#  This Powershell shell script is designed to run as Windows Task.           #
#  It will only run on Windows since PerfLogTranslate.exe is a dependency     #
#  Must be Powershell 5.1 or higher but NOT 7+ (this will break FTP)          #
#                                                                             #
#                                                                             #
#  Default home for this script is C:\users\%user%\Documents\Signals          #
#                                                                             #
#  Dependencies, all files to be collocated (in exact same directory):        #
#                                                                             #
#    1.  TrafficSignalIPAddresses.csv with columns ID, Name, Switch,          #
#        Controller and Battery for the respective IP Addresses               #
#    2.  AzCopy.exe this must run at least once before executing this script  #
#        Remember to enter the current Windows Login User (NOT Azure Login)   #  
#        And in order for that the Windows user must authenticate as          #
#        local organization (City of Bryan) and also be added as appropriate  #
#        (Blob Storage) Data Contributor in Azure, otherwise this will fail.  #
#        After the initial login and credentials storage, will work in batch  #  
#    3.  Public Private Key Files - default.ppk, ATCnx4.4_rsa.ppk             #     
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
$ErrorActionPreference = "Stop"

# --- 0. PLATFORM CHECK ---
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.1 or higher."
    exit 1
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

# Fallback if specific user folder doesn't exist, use current location
if (-not (Test-Path $ScriptHome)) {
    $ScriptHome = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ScriptHome)) { $ScriptHome = "." }
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
if ($MissingDeps.Count -gt 0) {
    Write-Log "FATAL: Missing dependencies in $ScriptHome : $($MissingDeps -join ', ')" "Red"
    exit 1
}

# Check WinSCP
$WinSCPPath = "C:\Program Files (x86)\WinSCP\WinSCP.com"
$SCP = $false
if (Test-Path $WinSCPPath) { $SCP = $true } 
else { Write-Log "WARNING: WinSCP not found. SFTP will not be possible." "Yellow" }
# Load WinSCP Assembly for .NET usage
$WinSCPDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
if (Test-Path $WinSCPDll) { Add-Type -Path $WinSCPDll } else { $SCP = $false; Write-Log "WARNING: WinSCPnet.dll not found." "Yellow" }

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
    exit 1
}

# --- 3. PARSE IDS & LOAD CSV ---
$SignalList = @()
$MasterList = Import-Csv $TrafficCsv -Header "ID","Name","Switch","Controller","Battery"

# CRITICAL FIX: Filter out the Header row (where ID="ID") or empty rows
$MasterList = $MasterList | Where-Object { $_.ID -match '^\d+$' }

# If $IDs provided, parse. Else use all from CSV.
if (-not [string]::IsNullOrWhiteSpace($IDs)) {
    $RawIDs = @()
    # Parse "1, 3..5" syntax
    $Parts = $IDs -split ','
    foreach ($P in $Parts) {
        $Clean = $P.Trim()
        if ($Clean -match '(\d+)\.\.(\d+)') {
            $Start=[int]$matches[1]; $End=[int]$matches[2]
            if ($Start -le $End) { $RawIDs += ($Start..$End) } else { $RawIDs += ($Start..$End) }
        } elseif ($Clean -match '^\d+$') { $RawIDs += [int]$Clean }
    }
    $RawIDs = $RawIDs | Select-Object -Unique | Sort-Object
    
    foreach ($RId in $RawIDs) {
        $Found = $MasterList | Where-Object { [int]$_.ID -eq $RId }
        if ($Found) { $SignalList += $Found }
    }
} else {
    $SignalList = $MasterList
}

Write-Log "Processing $($SignalList.Count) signals..." "Cyan"

# --- HELPER FUNCTIONS ---

function Get-AzureLastDate {
    param([int]$SigID)
    $MkUrl = { param($Dt) "$AzureBase/SIEM_192.168.$SigID.11_$($Dt.ToString('yyyy_MM_dd_HH'))00.csv" }
    function Test-Url ($U) { try { $R=Invoke-WebRequest -UseBasicParsing -Uri $U -Method Head -ErrorAction SilentlyContinue; return ($R.StatusCode -eq 200) } catch { return $false } }

    $Now = (Get-Date).Date.AddHours((Get-Date).Hour + 1)
    $Intervals = @(0, 1, 3, 7, 14, 30, 60)
    $FoundAnchor=$null; $MissAnchor=$null
    
    foreach ($D in $Intervals) {
        $Probe = $Now.AddDays(-$D); foreach ($H in @(12, 8, 18, 0)) { $T = $Probe.Date.AddHours($H); if (Test-Url (&$MkUrl $T)) { $FoundAnchor=$T; $PrevOff = if ($D -eq 0) {0} else { $Intervals[[Array]::IndexOf($Intervals, $D)-1] }; $MissAnchor=$Now.AddDays(-$PrevOff); break } }
        if ($FoundAnchor) { break }
    }
    
    $LimitDate = Get-Date -Year 2025 -Month 1 -Day 1
    if (-not $FoundAnchor) {
        $Deep = $Now.AddDays(-60)
        while ($Deep -ge $LimitDate) {
            $T = Get-Date -Year $Deep.Year -Month $Deep.Month -Day 1 -Hour 12
            if (Test-Url (&$MkUrl $T)) { $FoundAnchor=$T; $MissAnchor=$T.AddMonths(1); break }
            $Deep = $Deep.AddMonths(-1)
        }
    }
    
    if (-not $FoundAnchor) { return $null }

    $Low=$FoundAnchor; $High=$MissAnchor; $Best=$Low
    while (($High - $Low).TotalHours -gt 1) {
        $Mid = $Low.AddHours([Math]::Floor(($High - $Low).TotalHours / 2))
        if (Test-Url (&$MkUrl $Mid)) { $Low=$Mid; $Best=$Mid } else { $Prev = $Mid.AddHours(-1); if (Test-Url (&$MkUrl $Prev)) { $Best=$Prev; break } else { $High=$Mid } }
    }
    return $Best
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
    
    # Exclusions
    # FIX: Only apply exclusions if the user did NOT explicitly request specific IDs
    if ([string]::IsNullOrWhiteSpace($IDs)) {
        $Exclusions = @(17, 35, 39, 49, 59) + (74..115)
        if ($IDVal -in $Exclusions) { Write-Log "ID $IDVal skipped (Exclusion List)." "Gray"; continue }
    }
    
    $Name = if ($Sig.Name) { $Sig.Name } else { "Unknown" }
    Write-Log "----------------------------------------------------------------" "Gray"
    Write-Log "Processing ID ${IDVal}: $Name" "Cyan"


    $SwitchIP = $Sig.Switch
    $CtrlIP   = $Sig.Controller

    # Organize Folder Names
    $PaddedID = "{0:D3}" -f $IDVal
    $SafeName = $Name -replace '[\\/:*?"<>|&@]', '_'
    $SignalFolder = "${PaddedID}_${SafeName}"
    $StagingFolder = Join-Path $StagingBase $SignalFolder
    
    if (Test-Path $StagingFolder) { Remove-Item $StagingFolder -Recurse -Force | Out-Null }
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
        $Summary += [PSCustomObject]@{ID=$IDVal; Name=$Name; Status="Skipped (Up to date)"; Count=0}
        Remove-Item $StagingFolder -Force; continue
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
        $Strategies = @(
            @{ Type="FTP"; User=$ftpUser; Pass=$ftpPassword; Key=$null },
            @{ Type="SFTP"; User="admin"; Pass=$null; Key=(Join-Path $ScriptHome "default.ppk") },
            @{ Type="SFTP"; User="admin"; Pass=$null; Key=(Join-Path $ScriptHome "ATCnx4.4_rsa.ppk") }
        )
        
        $Connected = $false; $RemoteRoot = ""
        
        foreach ($Strat in $Strategies) {
            try {
                $Opt = New-Object WinSCP.SessionOptions
                $Opt.HostName=$CtrlIP; $Opt.UserName=$Strat.User; $Opt.TimeoutInMilliseconds=8000
                if ($Strat.Type -eq "FTP") { $Opt.Protocol=[WinSCP.Protocol]::Ftp; $Opt.Password=$Strat.Pass }
                else { $Opt.Protocol=[WinSCP.Protocol]::Sftp; $Opt.SshPrivateKeyPath=$Strat.Key; $Opt.GiveUpSecurityAndAcceptAnySshHostKey=$true }
                
                if ($Session.Opened) { $Session.Dispose(); $Session = New-Object WinSCP.Session }
                $Session.Open($Opt)
                
                if ($Session.FileExists("/mnt/sd")) { $RemoteRoot="/mnt/sd" }
                elseif ($Session.FileExists("/mount/sd")) { $RemoteRoot="/mount/sd" }
                elseif ($Session.FileExists("/media/sd")) { $RemoteRoot="/media/sd" }
                
                if ($RemoteRoot) {
                    $Connected = $true
                    Write-Log "   Connected via $($Strat.Type) ($($Strat.Key))." "Green"
                    break
                }
            } 
            catch 
            {
               Write-Log "Connection failed. Details: $_" "Red"
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
                } 
                catch 
                {
                   Write-Log "Connection failed. Details: $_" "Red"
                }
            }
            Write-Log "   Downloaded $DlCount files from Controller." "Cyan"
            $Session.Dispose()
        } else {
            # Ping check
            if ($SwitchIP) {
                $Ping = Test-Connection $SwitchIP -Count 1 -ErrorAction SilentlyContinue
                if ($Ping) { Write-Log "   Controller Unreachable, Switch OK (${Ping.ResponseTime}ms)" "Magenta" }
                else { Write-Log "   Switch Unreachable" "Red" }
            } else { Write-Log "   Controller Unreachable (No Switch IP)" "Red" }
        }
    }

    # Step 6: Verify Found Files
    if ($FoundCount -eq 0) {
        Write-Log "   No files found (Archive or Controller). Skipping." "Yellow"
        Remove-Item $StagingFolder -Force
        $Summary += [PSCustomObject]@{ID=$IDVal; Name=$Name; Status="Skipped (No Files)"; Count=0}
        continue
    }

    # Step 6b: Translate
    Write-Log "   Translating $FoundCount files..." "Cyan"
    Set-Location $StagingFolder
    $TransExe = Join-Path $ScriptHome "PerfLogTranslate.exe"
    # Execute natively within directory
    $Back = Get-Location; Set-Location $StagingFolder
    try { & $TransExe -i *.dat | Out-Null } catch { Write-Log "   Translate Error: $_" "Red" }
    Set-Location $Back
    
    # Step 7: Rename & Fix IP
    $Csvs = Get-ChildItem -Path $StagingFolder -Filter "*.csv"
    foreach ($C in $Csvs) {
        # Filename: SIEM_10.x.x.x_YYYY... -> SIEM_192.168.ID.11_YYYY...
        if ($C.Name -match "SIEM_.*_(\d{4}_\d{2}_\d{2}_\d{4})\.csv") {
            $TS = $matches[1]
            $FileYear=[int]$TS.Substring(0,4); $FileMonth=[int]$TS.Substring(5,2); $FileDay=[int]$TS.Substring(8,2); $FileHour=[int]$TS.Substring(11,2)
            $FileDate = Get-Date -Year $FileYear -Month $FileMonth -Day $FileDay -Hour $FileHour -Minute 0 -Second 0 -Millisecond 0
            
            $NewName = "SIEM_192.168.$IDVal.11_$TS.csv"
            $NewPath = Join-Path $StagingFolder $NewName
            
            $Content = Get-Content $C.FullName
            if ($Content.Count -gt 2) {
                # Fix Line 1
                $Content[0] = "192.168.$IDVal.11,,"
                
                # Fix Timezones (Line 3+)
                $HeaderLines = $Content[0..1]
                $DataLines = $Content[2..($Content.Count-1)]
                $UpdatedData = foreach ($Line in $DataLines) {
                    if ([string]::IsNullOrWhiteSpace($Line)) { $Line; continue }
                    $Cols = $Line -split ','
                    try {
                        $RowDt = [datetime]::ParseExact($Cols[0].Trim(), "MM-dd-yyyy HH:mm:ss.f", $null)
                        $RowBucket = Get-Date -Year $RowDt.Year -Month $RowDt.Month -Day $RowDt.Day -Hour $RowDt.Hour -Minute 0 -Second 0 -Millisecond 0
                        $Diff = $FileDate - $RowBucket; $HDiff = $Diff.TotalHours
                        
                        if ([Math]::Abs($HDiff) -ge 1 -and [Math]::Abs($HDiff) -le 7) {
                            $NewDt = $RowDt.AddHours($HDiff)
                            $Cols[0] = $NewDt.ToString("MM-dd-yyyy HH:mm:ss.f")
                            $Cols -join ','
                        } else { $Line }
                    } catch { $Line }
                }
                
                $Final = $HeaderLines + $UpdatedData
                $Final | Set-Content $NewPath -Force
                if ($NewName -ne $C.Name) { Remove-Item $C.FullName -Force }
            }
        }
    }

    # Step 8: Upload
    $AzCopyExe = Join-Path $ScriptHome "AzCopy.exe"
    $DestUrl = "https://cob77803.blob.core.windows.net/siglog"
    # --overwrite=true is key
    $AzArgs = "copy `"$StagingFolder\*.csv`" `"$DestUrl`" --overwrite=true --block-blob-tier=Cool --log-level=ERROR"
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
    Get-ChildItem $StagingFolder -Filter "*.dat" | Move-Item -Destination $DataArchDest -Force
    Get-ChildItem $StagingFolder -Filter "*.csv" | Move-Item -Destination $CsvArchDest -Force
    
    Set-Location $ScriptHome
    if ((Get-ChildItem $StagingFolder).Count -eq 0) {
        try {
            Remove-Item $StagingFolder -Force -ErrorAction Stop
        } catch {
            Write-Log "   Warning: Could not remove $StagingFolder because $($_.Exception.Message)" "Yellow"
        }
    } else {
        Write-Log "   Warning: Staging folder not empty." "Yellow"
    }
}

# Summary
Write-Log "--- FINAL SUMMARY ---" "Cyan"
$Summary | Format-Table -AutoSize | Out-String | Write-Host
$Summary | Format-Table -AutoSize | Out-File $LogFile -Append
