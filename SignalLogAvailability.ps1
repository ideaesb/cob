#################################################################################################
# The following will count the expected number of files in the range  
# From 2024-01-01 00:00 to today

##################################################################################################
# Omit #35 Boonville/Miramont, #49 Braircrest/GreenValley, #59 College/Carson
# Omit #74..110 to allow TxDOT signals being numbered from 111 through 114  
$validSignals = 1..34 + 36..48 + 50..58 + 60..73 + 111..114

###################################################################################################
# Azure Link (or, if obsolete, equivalent File Repository Endpoint)
$azure = "https://cob77803.blob.core.windows.net/siglog/SIEM_192.168."
#         https://cob77803.blob.core.windows.net/siglog/SIEM_192.168.1.11_2024_09_03_1900.csv
# The actual URL looks this #######################################################################

####################################################################################################
# For SPM earliest know date for most signals is year 2024, so set the Epoch to 2024-01-01 Midnight
# (Exception is Signal Id 44 E29th and Briarcrest which has files from as early as February 2021)
# End timestamp must be set to one hour prior to when this script is run, which is the last possible
$epoch = Get-Date "2024-01-01"  
$today = Get-Date

##############################################################################################
# Function returns true if a link is reachable, false if not or error
#

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
        # Write-Host "Error checking URL '$Url': $($_.Exception.Message)"
        return $false
    }
}

##############################################################################################
# Function to generate complete Azure link to file given signal id and timestamp
#

function Get-Url {
  param(
    [DateTime]$dateTime,
    [int]$signalId 
  )

  $year  = $dateTime.Year
  $month = "{0:D2}" -f $dateTime.Month
  $day   = "{0:D2}" -f $dateTime.Day
  $hour  = "{0:D2}" -f $dateTime.Hour


  return $azure + $signalId + ".11_" + $year + "_" + $month + "_" + $day + "_" + $hour + "00.csv"

}


#####################################################################
# PowerShell’s DateTime type inherently accounts for 
# Day transitions (e.g., 23:00 to 00:00 next day).
# Month/year transitions.
# Leap years (e.g., February 29 in 2020, 2024, etc.).

# Initialize current date to start date
$currentDate = $epoch


foreach ($signal in $validSignals) {
 
  while ($currentDate -le $today) {

    ##################################################################################################
    # count of CSV files available for day, should be 24, and if not usually 0, but could be partial 
    # this could be REFINED to scan each CSV file for coverage of each hour to spot missed records
    # this is how many files there SHOULD be if there was full coverage for the day - 24 
    $fileCountForDay = 0
    $currentHour = $currentDate
    

    for ($i = 0;$i -le 23; $i++) {

      $url = Get-Url -dateTime $currentHour -signalId $signal

      # test the url
      if (Test-UrlReachable -Url $url -ErrorAction SilentlyContinue) {
        $fileCountForDay = $fileCountForDay + 1
      }
      else
      {
        # Write-Host "Cannot Find " $url
      }

      # increment by an hour
      $currentHour = $currentHour.AddHours(1)
    }

    if ($fileCountForDay -gt 0) {
      # Format the variables as comma-separated values
      $line = "$signal,$($currentDate.ToString('yyyy-MM-dd')),$fileCountForDay"
      # Append to a file
      # Add header if file is new
      if (-not (Test-Path "output.csv")) {
           "Signal,Date,FileCount" | Out-File -FilePath "output.csv"
      }
      $line | Out-File -FilePath "output.csv" -Append
    }
    
    $currentDate = $currentDate.AddDays(1)
  }
}
