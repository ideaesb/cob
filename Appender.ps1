$sourceDirectory = "C:\Users\ukari\Documents\044_E29thBriarcrest_Staging\Backup\4"
$fileNamePrefix = "SIEM_10.105.1.35_"


function Convert-IntegerToString {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Number
    )
    return $Number.ToString()
}

function Format-TwoDigit {
    param(
        [int]$Number
    )
    return "{0:00}" -f $Number
}

#####################################################################
# PowerShell’s DateTime type inherently accounts for 
# Day transitions (e.g., 23:00 to 00:00 next day).
# Month/year transitions.
# Leap years (e.g., February 29 in 2020, 2024, etc.).

$begin_timestamp = Get-Date "2021-02-19 15:00"
$end_timestamp   = Get-Date "2025-03-18 15:00"


# Initialize current date to start date
$currentDate = $begin_timestamp

while ($currentDate -le $end_timestamp) {
  
  $year  = Convert-IntegerToString -Number ($currentDate).Year
  $month = Format-TwoDigit -Number ($currentDate).Month
  $day   = Format-TwoDigit -Number ($currentDate).Day
  $hour  = Format-TwoDigit -Number ($currentDate).Hour
  $hour  = $hour + "00"

  $filePattern = $fileNamePrefix + $year + "_" + $month + "_" + $day + "_" + $hour + "*.csv"
  $fileName    = "SIEM_192.168.44.11_" + $year + "_" + $month + "_" + $day + "_" + $hour + ".csv"
  

  $count = 0
  Get-ChildItem -Path $sourceDirectory -File | Where-Object { $_.Name -like $filePattern } | Sort-Object Name | ForEach-Object { 
  
    $copyAction   = $_.Name + " was copied into " + $fileName
    $appendAction = $_.Name + " was header chopped and appended to " + $fileName

    if ($count -eq 0 ) 
    { 
      #Copy-Item -Path $_.FullName -Destination "./csv/$fileName"
      # Replace Line 1 with new IP
      $content = Get-Content -Path $_.FullName
      $content[0] = "192.168.44.11" + ",,"
      Set-Content -Path "./csv/$fileName" -Value $content

      #Write-Output $copyAction
    }
    else 
    {
      # Read A.csv, skip first two lines, and append to B.csv
      Get-Content -Path $_.FullName | Select-Object -Skip 2 | Add-Content -Path "./csv/$fileName"
      #Write-Output $appendAction
    }
    
    $count = $count + 1
  }

  $currentDate = $currentDate.AddHours(1)
  
}