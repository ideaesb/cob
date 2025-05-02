#####################################################################
# Counts the number of datetime stamps (upper limit of files)
# This is used to determine how many threads to spawn for 
# a realistic processing time
#####################################################################
# PowerShell’s DateTime type inherently accounts for 
# Day transitions (e.g., 23:00 to 00:00 next day).
# Month/year transitions.
# Leap years (e.g., February 29 in 2020, 2024, etc.).
#

$begin_timestamp = Get-Date "2021-02-19 15:00"
$end_timestamp   = Get-Date "2021-03-19 15:00"


# Initialize current date to start date
$currentDate = $begin_timestamp

$count = 0
while ($currentDate -le $end_timestamp) {

  $count = $count + 1
  $currentDate = $currentDate.AddHours(1)
}

$processTime = (($count * 4) / 60) / 24

Write-Host "Count (number of timestamps between " $begin_timestamp " and " $end_timestamp " is = " $count
Write-Host "At the rate of 4 files per hour timestamp, will take "  $processTime  " days"