# The following will count the expected number of files in the range  
# From 2024_01_09_1200 to 2025_04_10_0800

# these are parameters from command-line
$signalId = 28

#Azure Link (or equivalent File Repository Endpoint)
$azure = "https://cob77803.blob.core.windows.net/siglog/SIEM_192.168.$signalId.11_"

$begin    = "2024_01_09_1200"
$end      = "2025_04_10_0800" 

#these are to be computed 

$begin_year  = $begin.Substring(0, 4)
$begin_month = $begin.Substring(5, 2)
$begin_day   = $begin.Substring(8, 2)
$begin_hour  = $begin.Substring(11, 2)

$begin_timestamp_iso_format =  `
   $begin_year + "-" + $begin_month + "-" + $begin_day + " "+ $begin_hour  + ":00:00" 
                              

$end_year  = $end.Substring(0, 4)
$end_month = $end.Substring(5, 2)
$end_day   = $end.Substring(8, 2)
$end_hour  = $end.Substring(11, 2)

$end_timestamp_iso_format =  `
   $end_year + "-" + $end_month + "-" + $end_day + " "+ $end_hour  + ":00:00" 


function Test-UrlReachable {
    param(
        [string]$Url
    )

    try {
        $request = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -ErrorAction Stop
        if ($request.StatusCode -eq 200) {
            # Write-Host "URL '$Url' is reachable (Status Code: $($request.StatusCode))."
            return $true
        } else {
            # Write-Host "URL '$Url' is not reachable (Status Code: $($request.StatusCode))."
            return $false
        }
    } catch {
        Write-Host "Error checking URL '$Url': $($_.Exception.Message)"
        return $false
    }
}


function Get-Url {
  param(
    [DateTime]$dateTime,
    [string]$url 
  )

  $year  = $dateTime.Year
  $month = "{0:D2}" -f $dateTime.Month
  $day   = "{0:D2}" -f $dateTime.Day
  $hour  = "{0:D2}" -f $dateTime.Hour


  return $azure + $year + "_" + $month + "_" + $day + "_" + $hour + "00.csv"

}


#####################################################################
# PowerShell’s DateTime type inherently accounts for 
# Day transitions (e.g., 23:00 to 00:00 next day).
# Month/year transitions.
# Leap years (e.g., February 29 in 2020, 2024, etc.).

$begin_timestamp = Get-Date $begin_timestamp_iso_format
$end_timestamp   = Get-Date $end_timestamp_iso_format


# Define start and end years
# Initialize current date to start date
$currentDate = $begin_timestamp

# the overall count of dat files between two timestamp ranges
# this is how many files there SHOULD be if there was full coverage
$count = 0

# the count of files actually in filesystem 
$available = 0



while ($currentDate -le $end_timestamp) {

  $count = $count + 1

  $url = Get-Url -dateTime $currentDate -url $azure

  # test url


  if (Test-UrlReachable -Url $url -ErrorAction SilentlyContinue) {
      # Write-Host "$signalId,$timestamp,$j,1"
      $available = $available + 1
  } else {
      # Shockley - Not Raining in the Sahara 
      # Write-Host "$signalId,$timestamp,$j,0"
  }


  # increment by an hour
  $currentDate = $currentDate.AddHours(1)
}



Write-Host $available " available of possible " $count " files."
Write-Host "Begin Timestamp " $begin_timestamp ", End " $end_timestamp 
#$url = Get-Url -dateTime $currentDate -url $azure
#Write-Host "Url = " $url

