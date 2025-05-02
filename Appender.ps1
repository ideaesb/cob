$sourceDirectory = "C:\Users\ukari\Documents\044_E29thBriarcrest_Staging\Backup\4"
$destinationDirectory = "C:\Users\ukari\Documents\044_E29thBriarcrest_Staging\csv2"

$sourceFileNamePrefix = "SIEM_10.105.1.35_"
$destinationFileNamePrefix = "SIEM_192.168.44.11_"

Get-ChildItem -Path $sourceDirectory -Filter "*.csv" | Sort-Object Name | ForEach-Object { 

 $newFileName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
 # SIEM_10.105.1.35_2021_02_19_1500.20210219213056 - count the last part
 $newFileName = $newFileNAme.Substring(0, $newFileName.Length - 15) + ".csv"
 $newFileName = $newFileNAme -replace $sourceFileNamePrefix, $destinationFileNamePrefix
 $newPath = Join-Path -Path $destinationDirectory -ChildPath $newFileName

 if (Test-Path -Path $newPath) {
    
   Get-Content -Path $_.FullName | Select-Object -Skip 2 | Add-Content -Path $newPath

   Write-Host "File exists: so " $_.Name " will be APPENDED to "  $newPath

  } else {


    # Replace Line 1 with new IP
    $content = Get-Content -Path $_.FullName
    $content[0] = "192.168.44.11" + ",,"
    Set-Content -Path $newPath -Value $content

    # Copy-Item -Path $_.FullName -Destination $newPath
    Write-Host "File does not exist: so new file" $newPath "CREATED" 


  }

}
