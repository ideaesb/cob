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
#  the dat file into commma separated value (CSV) files in the a local        #
#  directory called highResCsv.                                               #
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
#                                                                             #
#                                                                             #
###############################################################################

$debugMode = $false
$perfLogTranslateExe = "C:\Users\ukari\Downloads\PerfLogTranslate.exe"

###############################################################################
# Remote/Shared Read-Only Directory maintained by Traffic Operations
#
 
$controllerLogs = "R:\Public Works\Traffic Operations\SIGNALS\Signal Controller Logs"

################################################################################
# Local Working Directory for Data Processing and Visualization - CSV Files
#
# This is the output folder for this script 
# This folder will be created in the same directory as this script.    

$csvOutputFolder  = "signalControllerLogsCsv"

# End of User-Defined Variables  

# Proceed if controller logs folder can be accessed by this script
if (Test-Path -Path $controllerLogs) {

  ############################################################################################
  #  Per https://stackoverflow.com/questions/16906170/create-directory-if-it-does-not-exist
  #  
  #  Create local csvOutputFolder  (creating one if it does not already exist)

  # Combine Present Working Directory (PWD) to create the full subdirectory path to csvFolder
  $csvDirPath = [System.IO.Path]::Combine($PWD.Path, $csvOutputFolder)  
  [System.IO.Directory]::CreateDirectory($csvDirPath) | Out-Null

  ############################################################################################
  #  Iterate through each directory which are named for each signal as 
  #
  #  001_Texas@OldHearne&Sims
  #  002_Texas@Hwy21 
  #  and so on, the three digit with leading zeroes numbers representing unique signal ID
  #
  
  Get-ChildItem -Path $controllerLogs -Directory | ForEach-Object {

    # give the child a meaningful variable name
    $signalFolder = $_
    $signalName = Split-Path -Path $signalFolder -Leaf

    if ($debugMode) { Write-Host "Processing directory (Full Name) " $signalFolder }
    if ($debugMode) { Write-Host "Processing directory:" $signalName }
    
    
    # Create the folder if it does not already exist
    # By end of the loop, CSV directory will, as a result, mirror the controller logs directory
    $signalFolder = [System.IO.Path]::Combine($csvDirPath, $signalName)  
    [System.IO.Directory]::CreateDirectory($signalFolder) | Out-Null
    if ($debugMode) { Write-Host "Created Signal Folder :" $signalFolder }
    
    # iterate through the data directory in signal folder of controller logs
    $dataFolder = [System.IO.Path]::Combine($signalFolder, "data")
    Get-ChildItem -Path $dataFolder -File | ForEach-Object {

      # give the child a meaningful variable name
      $theLogDatFile = $_

      # Examine the filename, which is the leaf of the current object 
      $fileName = Split-Path -Path $theLogDatFile -Leaf
      
      # Only look for filenames that start with "SIEM", avoid any "config"
      if ($fileName.StartsWith("SIEM")) {


         # compute New IP address for signal controller based on signal ID using in folder name
         $signalID = [int] $signalName.Substring(0, 3)
         $controllerIP = "192.168." + $signalID + ".11" 

         # timestamp starts at position 18, and if 15 characters long
         $timestamp = $filename.Substring(18,15)

         # compute the new filename and add the full path
   
         $newIPAddressFileName = "SIEM_" + $controllerIP + "_" + $timestamp

         $newDatFileName = $newIPAddressFileName + ".dat"
         $newDatFileWithPath = Join-Path $signalFolder $newDatFileName
         if ($debugMode) { Write-Host "New IP File Name :" $newDatFileWithPath }
          
         $csvFileName = $newIPAddressFileName + ".csv"
         $csvFileWithPath = Join-Path $signalFolder $csvFileName
         if ($debugMode) { Write-Host "New CSV File Name :" $csvFileWithPath }

         # limit decoding to generate only NEW CSV files
         # if ($true) - can be toggle commented with production if - if need reuse 
         if (Test-Path -Path $csvFileWithPath )
         {
           # do absolutely nothing 
           # if ($debugMode) { Write-Host $csvFileName " already exists, skipping" }
         } else {


           ###############################################################################
           #  MAIN/CORE LOGIC OF THE PERF.LOG.TRANSLATE SCRIPT
           #
           #  This is most time intensive and brittle part, without which the script runs 
           #  to quickly mirror the signal folders from controller logs (a side benefit)
           #
           #  3-step process to decode each file  

           if ($debugMode) { Write-Host "Decoding " $newDatFileName }

           # Step 1:  
           # Although there are ways to pipe content, to avoid any polution of the source
           # copy the file to local/staging area, renaming it in the process, 
           # thereby getting rid of IP in the name of the file.  COB IT Requirement. 

           if ($debugMode) { Write-Host "Copying From :" $theLogDatFile " TO: " $newDatFileWithPath}
           Copy-Item -Path $theLogDatFile -Destination $newDatFileWithPath

           # Step 2: 
           # Run the Yunex Decoder

         
           Start-Process -FilePath $perfLogTranslateExe -ArgumentList $newDatFileWithPath -NoNewWindow -Wait


           # Step 3:
           # Replace Line 1 with new IP

           $content = Get-Content $csvFileWithPath
           $content[0] = $controllerIP + ",,"
           Set-Content $csvFileWithPath -Value $content


         } # End-If Test for existance of CSV file already in the staging area

         if ($debugMode) { Write-Host "Finished" $csvFileName }

      } # End-If filename starts with "SIEM"

      if ($debugMode) { Write-Host $fileName }

    } # End of Get-ChildItem listing of all data files for a signal

  } # End of Get-ChildItem listing of all the Signals 

} else { 

  # controller data logs not found
  Write-Host $controllerLogs " does not exist.  Controller Logs not found." 

} # End-If Test-Path -Path $controllerLogs 
  