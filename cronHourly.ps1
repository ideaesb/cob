if (-not $PSScriptRoot) { throw "PSScriptRoot not set. Script must be run from a file." }
if (-not (Test-Path $PSScriptRoot)) { throw "Script root path not found: $PSScriptRoot" }

Set-Location $PSScriptRoot
$cronLog = Join-Path $PSScriptRoot "cronHourly.log"

function LogCron($msg) {

  # generate nice timestamp for logger function 
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

  try
  {
    # this will trap any $ts = null error 
    Add-Content -Path $cronLog -Value "[$ts] $msg" -ErrorAction Stop
  } catch {
    # swallow logging errors so the loop doesn't die
    Write-Host "Log Write Failed at $ts"
  }

}
LogCron "cronHourly started. User=$([Environment]::UserName) Host=$env:COMPUTERNAME PWD=$PWD"



while ($true) {

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Stop"

    try {

        LogCron "Loop tick. Now=$(Get-Date -Format s)"

        # Calculate "5 minutes past the next hour"
        $Now = Get-Date
        $NextRunTime = $Now.Date.AddHours($Now.Hour + 1).AddMinutes(5)

        $TimeUntilNextRun = [math]::Ceiling(($NextRunTime - $Now).TotalSeconds)
        if ($TimeUntilNextRun -lt 0) { $TimeUntilNextRun = 0 }

        Write-Output "Waiting for next run at $NextRunTime. Sleeping for $TimeUntilNextRun seconds..."
        LogCron      "Waiting for next run at $NextRunTime. Sleeping for $TimeUntilNextRun seconds..."

        Start-Sleep -Seconds $TimeUntilNextRun

        Write-Output "Starting TrafficSignalControllerToAzureUpload.ps1 execution at $(Get-Date)..."
        LogCron      "Starting TrafficSignalControllerToAzureUpload.ps1 execution..."

        & (Join-Path $PSScriptRoot "TrafficSignalControllerToAzureUpload.ps1")

        Write-Output "Execution finished at $(Get-Date). LASTEXITCODE=$LASTEXITCODE"
        LogCron "Execution finished. LASTEXITCODE=$LASTEXITCODE"
    }
    catch {
        $msg = $_.Exception.Message
        Write-Error "cronHourly error: $msg"
        LogCron      "Error: $msg"
        if ($_.ScriptStackTrace) { LogCron "Stack: $($_.ScriptStackTrace)" }
        LogCron ("ErrorFull: " + ($_.Exception | Out-String).Trim())
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}
