$exePath = "C:\Users\ukari\Downloads\PerfLogTranslate.exe"

function Get-Filename {
  param(
    [DateTime]$dateTime
  )

  $year  = $dateTime.Year
  $month = "{0:D2}" -f $dateTime.Month
  $day   = "{0:D2}" -f $dateTime.Day
  


  return "C:\Users\ukari\Documents\044_E29thBriarcrest_Staging\Backup\4\SIEM_10.105.1.35_" + $year + "_" + $month + "_" + $day + "*.dat"

}


$begin_timestamp = Get-Date "2021-04-12"
$end_timestamp   = Get-Date "2025-03-18"
$currentDate = $begin_timestamp

while ($currentDate -le $end_timestamp) {


$fileNamePattern = Get-Filename -dateTime $currentDate

Start-Process -FilePath $exePath -ArgumentList "-i", $fileNamePattern -WindowStyle Hidden

Write-Host $fileNamePattern

$currentDate = $currentDate.AddDays(1)
}


