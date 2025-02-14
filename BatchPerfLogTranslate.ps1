# run perflogtranslate in parallel windows
$scriptPath = "c:\Users\ukari\Documents\Signals\PerfLogTranslate.ps1"

$startId = 20
$endId = 22

for ($i = $startId; $i -le $endId; $i++) {
    $arguments = "-signalId", "$i"
    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "& { & '$scriptPath' $($arguments -join ' ') }"
}

$memory = Get-WmiObject Win32_OperatingSystem
$totalMemoryGB = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)
$freeMemoryGB = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
$usedMemoryGB = $totalMemoryGB - $freeMemoryGB

Write-Host "Total Memory: $totalMemoryGB GB"
Write-Host "Free Memory: $freeMemoryGB GB"
Write-Host "Used Memory: $usedMemoryGB GB"