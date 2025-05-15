$path = "R:\Public Works\Traffic Operations\SIGNALS\Signal Controller Logs\025_Villamaria@Cavitt\data"  # Replace with your directory
$oldIP = "10.105.1.177"
$newIP = "10.105.2.99"

# Get files containing the old IP
$files = Get-ChildItem -Path $path -Filter "SIEM_10.105.1.177*"

# Rename files
foreach ($file in $files) {
    $newFileName = $file.Name -replace $oldIP, $newIP
    $newFilePath = Join-Path -Path $path -ChildPath $newFileName
    Rename-Item -Path $file.FullName -NewName $newFilePath
}