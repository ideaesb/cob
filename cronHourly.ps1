if (-not $PSScriptRoot) {
    Write-Error "PSScriptRoot not set. Script must be run from a file."
    exit 1
}
Set-Location $PSScriptRoot


while ($true) {
    # Calculate "5 minutes past the next hour"
    $Now = Get-Date
    $NextRunTime = $Now.Date.AddHours($Now.Hour + 1).AddMinutes(5)

    $TimeUntilNextRun = ($NextRunTime - $Now).TotalSeconds
    Write-Output "Waiting for next run at $NextRunTime. Sleeping for $TimeUntilNextRun seconds..."

    # Sleep until the next run time
    Start-Sleep -Seconds $TimeUntilNextRun

    # Execute your synchronization script
    try 
    {
        Write-Output "Starting TrafficSignalControllerToAzureUpload.ps1 execution at $(Get-Date)..."
        & (Join-Path $PSScriptRoot "TrafficSignalControllerToAzureUpload.ps1")
        Write-Output "Execution finished at $(Get-Date)."
    } catch {
        Write-Error "Error in TrafficSignalControllerToAzureUpload.ps1: $_"
    }
    # Ensure no infinite errors and wait for the next run
}