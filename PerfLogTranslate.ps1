###############################################################################
#                            CITY OF BRYAN, TEXAS                             #
#                          PUBLIC WORKS, TRAFFIC OPERATIONS                   #
###############################################################################
#                                                                             #
#                          PerfLogTranslate.ps1                               #
#                                                                             #
#  This Powershell shell script is designed to run as Windows Task.           #
#                                                                             #
#  It scans (read-only) a directory with folders for each traffic signal      #
#  containing high resolution log files in binary data format.                #
#                                                                             #
#  For each file, it will apply PerfLogTranslate.exe decoder to convert       #
#  the dat file into commma separated value (CSV) files in a local directory. #
#                                                                             #
#  In this process, it will remove the signal controller IP address from      #
#  the filename and also its contents, replacing with a dummy IP to be        #
#  compatible with ATSPM post processing.                                     #
#                                                                             #
###############################################################################
#                                                                             #
#   Version/History                                                           #
#                                                                             #
#   [Uday S. Kari 11-Feb-2025]  Initial Version                               #
#   [Uday S. Kari 13-Feb-2025]  Multithreaded Calling (by SignalID) Enabled   #
#   [Uday S. Kari 14-Feb-2025]  Enable calling by Date for massively parallel #
#                                                                             #
#                                                                             #
###############################################################################


###############################################################################
## Command Line Parameters 

param (
 [switch] $debugMode,
 [int] $signalId,
 [int] $year,
 [int] $month,
 [int] $day 
)


###############################################################################
## Functions 


# Just adds new line, with timestamp (for now)
function debug-log {
  
   param (
     [string] $message
   )  

   Write-Host ""
   Write-Host $message
   Write-Host (Get-Date).ToLocalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK")

} # End of function debug-log


# if year, month or day were passed as parameters
# the data file timestamp can be filtered in or out 
# returns TRUE is ok to proceed, FALSE to skip...

function dateFilter {

  param (
   [string] $timestamp,
   [int] $year,
   [int] $month,
   [int] $day 
  )  


  # first check if timestamp is valid

  $regexPattern = "^\d{4}_\d{2}_\d{2}_\d{4}$"
   
  if ($timestamp -match $regexPattern) {
    # OK - Write-Host "The string '$timestamp' matches the date format yyyy_mm_dd_hhhh."
  } else {
    Write-Host "ERROR: The string '$timestamp' does not match the date format yyyy_mm_dd_hhhh. Skipping File."
    return $false
  } 


  if ($year -eq 0) 
  { 
    return $true
  } 
  elseif ($year -ne [int] $timestamp.Substring(0,4)) 
  {
    return $false
  } 
  else 
  {
    if ($month -eq 0)
    {
      return $true
    }
    elseif ($month -ne [int] $timestamp.Substring(5,2)) 
    {
      return $false
    }
    else
    {
      if ($day -eq 0)
      {
        return $true
      }
      elseif ($day -ne [int] $timestamp.Substring(8,2)) 
      {
        return $false
      }
      else
      {
        return $true
      }
    }
  }
} #End Function    


# the main/core logic function 
function coreLogsCsvTranformProcess {
  
   param (
     [bool]   $debug,
     [string] $signalFolderName,
     [string] $outputCsvFolders,
     [int]    $year,
     [int]    $month,
     [int]    $day 
   )  

   

   begin {
    if ($debug)
    {
      debug-log -message "BEGIN Function coreLogsCsvTranformProcess"  
      debug-log -message "Processing directory (Full Name) $signalFolderName"
      debug-log -message "Converting all the files therin into $outputCsvFolders"
      debug-log -message "Just processing for date=year:{$year}-month:{$month}-day:{$day}, if day is zero, whole month, months is zero whole year and so on..."
    }
   } # End of Begin


   # The Main Process
   process {

    $signalName = Split-Path -Path $signalLogsFolder -Leaf
    if ($debug) { debug-log -message "Processing signal: $signalName" }

    # use signal name to get correspondind destination leaf 
    $outputCsvFolder = Join-Path $outputCsvFolders $signalName
    if ($debug) { debug-log -message "Its output folder will be : $outputCsvFolder" }
    if (Test-Path -Path $outputCsvFolder )
    {
       if ($debug) { debug-log -message "$outputCsvFolder Exists...no action, proceed" }
    }
    else
    {
      [System.IO.Directory]::CreateDirectory($outputCsvFolder) | Out-Null
      if ($debug) { debug-log -message "Created $outputCsvFolder (no errors)" }
    }

    # compute New IP address for signal controller based on signal ID used in naming folders
    $signalID = [int] $signalName.Substring(0, 3)
    $controllerIP = "192.168." + $signalID + ".11" 
    if ($debug) { debug-log -message "Controller IP derived from $signalName = $controllerIP, (signalID = $signalID)" }
    
    # iterate through the data directory in signal folder of controller logs
    $dataFolder = [System.IO.Path]::Combine($signalFolderName, "data")
    if ($debug) { debug-log -message "data folder with all SIEM*.dat files : $dataFolder" }

    Get-ChildItem -Path $dataFolder -File | ForEach-Object {

      # give the child a meaningful variable name
      $theLogDatFile = $_.FullName
      if ($debug) { debug-log -message "Full Name of DAT file : $theLogDatFile" }

      # Examine the filename, which is the leaf of the current object 
      $fileName = Split-Path -Path $theLogDatFile -Leaf
      if ($debug) { debug-log -message "FileName of DAT file : $fileName" }

      # Only transform filenames that start with "SIEM", avoid any "config"
      if ($fileName.StartsWith("SIEM")) {

        if ($debug) { debug-log -message "Begin processing The DAT file : $fileName" }

        # timestamp ends at .dat and is 15 characters long
        $datPosition = $fileName.IndexOf(".dat")
        $timestamp = $filename.Substring($datPosition-15,15)
        if ($debug) { debug-log -message "timestamp (which is the start of file write) parsed out as : $timestamp" }

        if (dateFilter -timestamp $timestamp -year $year -month $month -day $day)
        {

          # compute the new filename and add the full path
          $newIPAddressFileName = "SIEM_" + $controllerIP + "_" + $timestamp

          $newDatFileName = $newIPAddressFileName + ".dat"
          $newDatFileWithPath = Join-Path $outputCsvFolder $newDatFileName
          if ($debug) { debug-log -message "New DAT File Name :  $newDatFileWithPath (Note that controller IP was replaced)" }
          
          $csvFileName = $newIPAddressFileName + ".csv"
          $csvFileWithPath = Join-Path $outputCsvFolder $csvFileName
          if ($debug) { debug-log -message "New CSV File Name : $csvFileWithPath" }

          # limit decoding to generate only NEW CSV files
          if (Test-Path -Path $csvFileWithPath )
          {
            # do absolutely nothing 
            if ($debug) { debug-log -message "$csvFileWithPath already exists, skipping" }
          } else {

            ###############################################################################
            #  MAIN/CORE LOGIC OF THE PERF.LOG.TRANSLATE SCRIPT
            #
            #  This is most time intensive and brittle part, without which the script runs 
            #  to quickly mirror the signal folders from controller logs (a side benefit)
            #
            #  3-step process to decode each file  

            if ($debug) { debug-log -message "Decoding $newDatFileName" }

            # Step 1: R E N A M E  (I P)

            if ($debug) { debug-log -message "Copying & Renaming From : $theLogDatFile TO:  $newDatFileWithPath"}
            Copy-Item -Path $theLogDatFile -Destination $newDatFileWithPath

            # Step 2: D E C O D E 
 
            if ($debug) { debug-log -message "Decoding $newDatFileWithPath TO: $csvFileWithPath"}
            Start-Process -FilePath $perfLogTranslateExe -ArgumentList $newDatFileWithPath -NoNewWindow -Wait


            # Step 3: R E P L A C E (I P)
            # Replace Line 1 with new IP

            if ($debug) { debug-log -message "Replacing Line 1 in $csvFileWithPath"}

            $content = Get-Content $csvFileWithPath
            $content[0] = $controllerIP + ",,"
            Set-Content $csvFileWithPath -Value $content

            if ($debug) { debug-log -message "Finished with transformation (copy/rename/decode/replacement of Line 1) of $fileName in folder $signalFolderName into $csvFileWithPath"  }

          } # End-If Test for existance of CSV file csvFileWithPath already exists in the staging area

        } 
        else
        {
          if ($debug) {debug-log -message "Skipped $fileName as it did not match date filter for timestamp date=year:{$year}-month:{$month}-day:{$day}" }
        } # End-If Test for matching timestamp with date filter

      } 
      else
      {
        if ($debug) {debug-log -message "Skipped $fileName (JUNK FILE) because it does not start with SIEM" }
      } # End-If filename starts with "SIEM"

    } # End of Get-ChildItem listing of all data files for a signal

    if ($debug) { debug-log -message "Finished Processing signal: $signalName" }    

   } # End of Process



   end {
    if ($debug)
    {
      debug-log -message "END Function coreLogsCsvTranformProcess"  
    }
   } # End of End

} # End of function coreLogsCsvTranformProcess 


 
#######################################################################################


# Begin PerfLogTranslate.ps1

if ($debugMode) 
{ 
  debug-log -message "Starting up in DEBUG (Verbose) mode"
  debug-log -message "Read parameters from command line as debugMode = $debugMode, signalId = $signalId, date=year:{$year}-month:{$month}-day:{$day}"
}
else
{
  debug-log -message  "D E B U G    M O D E   I S   O F F"
}


###############################################################################
# PerfLogTranslate Executable with complete path
#

$perfLogTranslateExe = "C:\Users\ukari\Downloads\PerfLogTranslate.exe"
if ($debugMode) { debug-log -message  "perfLogTranslateExe = $perfLogTranslateExe" }


###############################################################################
# Remote/Shared Read-Only Directory maintained by Traffic Operations
#

$controllerLogs = "R:\Public Works\Traffic Operations\SIGNALS\Signal Controller Logs"
if ($debugMode) {debug-log -message  "controllerLogs = $controllerLogs" }


################################################################################
# Local Working Directory for Data Processing and Visualization - CSV Files
#
# This is the output folder for this script 
# This folder will be created in the same directory as this script.    

$csvOutputFolder  = "signalControllerLogsCsv"
if ($debugMode) { debug-log -message  "csvOutputFolder = $csvOutputFolder" }

# End of User-Defined Variables  ###############################################


################################################################################
# Proceed only if controller logs folder can be accessed by this script
#

if ($debugMode) { debug-log -message  "Testing whether script can find and access " + $controllerLogs }

if (Test-Path -Path $controllerLogs) {

  if ($debugMode) {debug-log -message  "$controllerLogs has been found to exist and is accessible, begin work... " }

  ############################################################################################
  #   
  #  Create local csvOutputFolder  (creating one if it does not already exist)

  # Combine Present Working Directory (PWD) to create the full subdirectory path to csvFolder
  $csvDirPath = [System.IO.Path]::Combine($PWD.Path, $csvOutputFolder)  
  if (Test-Path -Path $csvDirPath) {debug-log -message  "$csvDirPath exists, no action " }
  else 
  { 
     # .NET method to create directory, checking first, if it does not exist    
     [System.IO.Directory]::CreateDirectory($csvDirPath) | Out-Null 
     if ($debugMode) {debug-log -message  "$csvDirPath created" }
  }


  ############################################################################################
  #    
  #  Iterate through all directories which are named for each signal as 
  #
  #  001_Texas@OldHearne&Sims
  #  002_Texas@Hwy21 
  #  and so on, the three digit with leading zeroes numbers representing unique signal ID
  #
  #  However, if a signalID is provided, use it to narrow down to just one folder   
  #

  if ($signalID -eq 0) 
  {

    Write-Host 'Example Usage .\PerfLogTranslate.ps1 -debugMode -signalID "007" -year "2024" -month "12" -day "02"'
    Write-Host "Note - SignalID command line parameter was NULL (0)." 
    Write-Host "Therefore, this scripts will now process ALL signal folders"
    Write-Host "Recommended to continue only if a few updates, continue?? (y/n)"    

    $whetherContinue = Read-Host
    if ($whetherContinue -eq "y")
    {
      Write-Host "OK.  Processing all folders"
      if ($debugMode) {debug-log -message  "Begin interating through the sub-directories of " + $controllerLogs } 
      
      # pipe the folders list into ForEach-Object
      Get-ChildItem -Path $controllerLogs -Directory | ForEach-Object {

        # give the child a meaningful variable name
        $signalLogsFolder = $_.FullName

        if ($debugMode) {debug-log -message  "Entering coreLogsCsvTranformProcess $signalLogsFolder" } 

        # set the Powershell window title  
        $currSignal = Split-Path -Path $signalLogsFolder -Leaf
        $host.UI.RawUI.WindowTitle = "PerfLogTranslate.Ps1 [ALL]) current folder $currSignal in $controllerLogs"

        coreLogsCsvTranformProcess -debug $debugMode `
                                   -signalFolderName $signalLogsFolder `
                                   -outputCsvFolders $csvDirPath `
                                   -year $year `
                                   -month $month `
                                   -day $day `
    
      } # End of iterating through all signal folders in controller logs directory
    } 
    else
    {
      if ($debugMode) { debug-log -message  "End/Done without iterating through $controllerLogs.   (Graceful Exit)."}
    } # End If whether continue
  } 
  elseif ($signalID -gt 0 -and $signalID -le 114)
  {
    # this will process just a single signal folder
    $formattedNumber = "{0:000}" -f $signalID

    try
    {
      if($debugMode) {debug-log -message  "Formatted Signal ID = $formattedNumber" }
      # pipe the controller logs directory into Where-Object to find folder that starts with signal ID
      $signalLogsFolder = (Get-ChildItem -Path $controllerLogs | Where-Object { $_.Name -match "^$formattedNumber" } ).FullName

      try
      {
        if (Test-Path -Path $signalLogsFolder)
        {
          if ($debugMode) {debug-log -message  "Entering coreLogsCsvTranformProcess $signalLogsFolder" } 
   
          # set the Powershell window title  
          $winTitle = Split-Path -Path $signalLogsFolder -Leaf
          $host.UI.RawUI.WindowTitle = "$winTitle (PerfLogTranslate.Ps1 -$signalID)"

          coreLogsCsvTranformProcess -debug $debugMode `
                                     -signalFolderName $signalLogsFolder `
                                     -outputCsvFolders $csvDirPath `
                                     -year $year `
                                     -month $month `
                                     -day $day `
        }
        else
        {
          # this will most likely fire because error in computation of folder name using leading zeroes
          debug-log -message "ERROR: Could not find signal logs folder using signalID = $signalID in $controllerLogs" 
          debug-log -message "formattedNumber with leading zeros $formattedNumber"
        }
      }
      catch
      {
        # this will fire because there was an error, period.  Unspecified.  Either signalLogsFolder NULL or 
        # coreLogsCsvTranformProcess crashed out for some reason
        debug-log -message "ERROR: Could not find signal logs folder using signalID = $signalID in $controllerLogs" 
        debug-log -message "SYSTEM ERROR: $Error"
      }
    }
    catch 
    {
      debug-log -message "ERROR: Could not find signal logs folder using signalID = $signalID in $controllerLogs" 
    } # End of try catch for name matching 
  }
  else 
  { 
    debug-log -message "Valid Signal IDs are 1 through 114 as of February 13, 2025" 
  } # End-If (signalID -eq 0) 
} 
else 
{ 

  # if got here it means that remote signal controller data logs FOLDER was not found
  debug-log -message "ERROR:  $controllerLogs does not exist (Controller Logs not found)." 

} # End-If Test-Path -Path $controllerLogs 

debug-log -message "PerfLogTranslate.Ps1 Complete" 

# The End 
# Some tests
# Get-ChildItem |  ForEach-Object { if ((Split-Path -Path $_ -Leaf).Length -ne 37) {$_} } # for one digit, 38, 39 for 2,3 digit signal IDS
