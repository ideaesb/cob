# run perflogtranslate in parallel windows
$scriptPath = "c:\Users\ukari\Documents\Signals\PerfLogTranslate.ps1"

$startId = 72
$endId = 72

# signalId
$windows = 0
for ($i = $startId; $i -le $endId; $i++) {
  for ($j = 2024; $j -le 2024; $j++) {
    for ($k = 12; $k -le 12; $k++) {
     for ($l = 20;$l -le 20; $l++) {  

        $arguments = "-signalId", "'$i'", "-year", "'$j'", "-month", "'$k'", "-day", "'$l'"
        Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "& { & '$scriptPath' $($arguments -join ' ') }"

        $windows = $windows + 1
        Write-Host $arguments
      }   
    }
  }
}

Write-Host "Numbers of Windows Spawned = $windows" 

$memory = Get-WmiObject Win32_OperatingSystem
$totalMemoryGB = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)
$freeMemoryGB = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
$usedMemoryGB = $totalMemoryGB - $freeMemoryGB

Write-Host "Total Memory: $totalMemoryGB GB"
Write-Host "Free Memory: $freeMemoryGB GB"
Write-Host "Used Memory: $usedMemoryGB GB"
