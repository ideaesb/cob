$lookup = @{
"001" = [PSCustomObject]@{ Name = "Texas@OldHearne&Sims";  IP = "10.105.0.179"}
"002" = [PSCustomObject]@{ Name = "Texas@Hwy21";  IP = "10.105.0.148"}
"003" = [PSCustomObject]@{ Name = "Texas@MLK";  IP = "10.105.0.195"}
"004" = [PSCustomObject]@{ Name = "Texas@23rd";  IP = "10.105.0.35"}
"005" = [PSCustomObject]@{ Name = "Texas@WJB";  IP = "10.105.2.3"}
"006" = [PSCustomObject]@{ Name = "Texas@27th";  IP = "10.105.0.163"}
"007" = [PSCustomObject]@{ Name = "Texas@29th";  IP = "10.105.0.211"}
"008" = [PSCustomObject]@{ Name = "Texas@Coulter";  IP = "10.105.2.19"}
"009" = [PSCustomObject]@{ Name = "Texas@Carson";  IP = "10.105.0.68"}
"010" = [PSCustomObject]@{ Name = "Texas@Twin&PostOffice";  IP = "10.105.0.83"}
"011" = [PSCustomObject]@{ Name = "Texas@Mitchell";  IP = "10.105.5.115"}
"012" = [PSCustomObject]@{ Name = "Texas@VillaMaria";  IP = "10.105.0.101"}
"013" = [PSCustomObject]@{ Name = "Texas@Elm";  IP = "10.105.0.227"}
"014" = [PSCustomObject]@{ Name = "Texas@SulphurSprings&Eaglepass";  IP = "10.105.0.132"}
"015" = [PSCustomObject]@{ Name = "Texas@North&Broadmoor";  IP = "10.105.0.51"}
"016" = [PSCustomObject]@{ Name = "Texas@Rosemary";  IP = "10.105.0.243"}
"017" = [PSCustomObject]@{ Name = "VillaMaria@WJB";  IP = "10.105.2.131"}
"018" = [PSCustomObject]@{ Name = "VillaMaria@Nash";  IP = "10.105.2.147"}
"019" = [PSCustomObject]@{ Name = "VillaMaria@RustlingOaks&Blinn";  IP = "10.105.2.179"}
"020" = [PSCustomObject]@{ Name = "VillaMaria@Joseph";  IP = "10.105.2.163"}
"021" = [PSCustomObject]@{ Name = "VillaMaria@E29th";  IP = "10.105.1.179"}
"022" = [PSCustomObject]@{ Name = "VillaMaria@Briarcrest";  IP = "10.105.1.147"}
"023" = [PSCustomObject]@{ Name = "VillaMaria@Cartercreek";  IP = "10.105.1.227"}
"024" = [PSCustomObject]@{ Name = "VillaMaria@Wayside";  IP = "10.105.1.163"}
"025" = [PSCustomObject]@{ Name = "VillaMaria@Cavitt";  IP = "10.105.2.99"}
"026" = [PSCustomObject]@{ Name = "VillaMaria&College";  IP = "10.105.2.215"}
"027" = [PSCustomObject]@{ Name = "VillaMaria@MidtownPark";  IP = "10.105.5.19"}
"028" = [PSCustomObject]@{ Name = "VillaMaria@Wellborn&Vanhook";  IP = "10.105.1.83"}
"029" = [PSCustomObject]@{ Name = "VillaMaria@2818";  IP = "10.105.1.67"}
"030" = [PSCustomObject]@{ Name = "VillaMaria@Jaguar";  IP = "10.105.2.243"}
"031" = [PSCustomObject]@{ Name = "Boonville@ElmoWeedon&Harvey";  IP = "10.105.5.3"}
"032" = [PSCustomObject]@{ Name = "Boonville@University";  IP = "10.105.3.211"}
"033" = [PSCustomObject]@{ Name = "Boonville@Copperfield";  IP = "10.105.3.195"}
"034" = [PSCustomObject]@{ Name = "Boonville@Woodcrest&Tesori";  IP = "10.105.3.179"}
"036" = [PSCustomObject]@{ Name = "Boonville@Briarcrest&FM1179";  IP = "10.105.3.163"}
"037" = [PSCustomObject]@{ Name = "Boonville@AustinsColony";  IP = "10.105.3.151"}
"038" = [PSCustomObject]@{ Name = "WJB@Nash";  IP = "10.105.2.115"}
"039" = [PSCustomObject]@{ Name = "WJB@Main&Bryan";  IP = "10.105.0.19"}
"040" = [PSCustomObject]@{ Name = "WJB@Sims";  IP = "10.105.0.3"}
"041" = [PSCustomObject]@{ Name = "E29th@CartercreekPkwy";  IP = "10.105.5.131"}
"042" = [PSCustomObject]@{ Name = "E29th@Stillmeadow&BriarOaks";  IP = "10.105.4.3"}
"043" = [PSCustomObject]@{ Name = "E29th@Barak";  IP = "10.105.1.51"}
"044" = [PSCustomObject]@{ Name = "E29th@Briarcrest";  IP = "10.105.1.35"}
"045" = [PSCustomObject]@{ Name = "E29th@Broadmoor";  IP = "10.105.1.243"}
"046" = [PSCustomObject]@{ Name = "E29th@Memorial";  IP = "10.105.1.19"}
"047" = [PSCustomObject]@{ Name = "E29th@Joseph";  IP = "10.105.1.195"}
"048" = [PSCustomObject]@{ Name = "E29th@Coulter";  IP = "10.105.1.3"}
"050" = [PSCustomObject]@{ Name = "Briarcrest@Wildflower";  IP = "10.105.2.35"}
"051" = [PSCustomObject]@{ Name = "Briarcrest@Freedom";  IP = "10.105.1.211"}
"052" = [PSCustomObject]@{ Name = "Briarcrest@Oakridge";  IP = "10.105.2.52"}
"053" = [PSCustomObject]@{ Name = "Briarcrest@Campus&CountryClub";  IP = "10.105.1.99"}
"054" = [PSCustomObject]@{ Name = "Briarcrest@Kent";  IP = "10.105.1.115"}
"055" = [PSCustomObject]@{ Name = "Briarcrest@Broadmoor";  IP = "10.105.1.131"}
"056" = [PSCustomObject]@{ Name = "College@North";  IP = "10.105.4.83"}
"057" = [PSCustomObject]@{ Name = "College@OldCollege&Pleasant";  IP = "10.105.4.35"}
"058" = [PSCustomObject]@{ Name = "College@SulpherSprings";  IP = "10.105.4.67"}
"060" = [PSCustomObject]@{ Name = "College@Dodge";  IP = "10.105.2.84"}
"061" = [PSCustomObject]@{ Name = "2818@SandyPoint";  IP = "10.105.5.67"}
"062" = [PSCustomObject]@{ Name = "2818@Hwy21";  IP = "10.105.2.67"}
"063" = [PSCustomObject]@{ Name = "2818@Beck&Shiloh";  IP = "10.105.3.51"}
"064" = [PSCustomObject]@{ Name = "2818@Leonard";  IP = "10.105.3.35"}
"065" = [PSCustomObject]@{ Name = "Hwy21@MLK";  IP = "10.105.5.99"}
"066" = [PSCustomObject]@{ Name = "Hwy21@WJB&Sandypoint";  IP = "10.105.3.83"}
"067" = [PSCustomObject]@{ Name = "Hwy21@Marino";  IP = "10.105.4.116"}
"068" = [PSCustomObject]@{ Name = "Hwy21@Sims";  IP = "10.105.4.99"}
"069" = [PSCustomObject]@{ Name = "Coulter@CarterCreek&E32";  IP = "10.105.3.227"}
"070" = [PSCustomObject]@{ Name = "Finfeather@TurkeyCreek&Carson";  IP = "10.105.3.19"}
"071" = [PSCustomObject]@{ Name = "Wellborn@OldCollege&FandB";  IP = "10.105.2.195"}
"072" = [PSCustomObject]@{ Name = "OldReliance@AustinsColony";  IP = "10.105.3.115"}
"073" = [PSCustomObject]@{ Name = "Hwy21@Waco&Tabor";  IP = "10.105.5.35"}
}

# Set ping options
$pingCount = 4
$timeout = 1000  # milliseconds

# Initialize results array
$results = @()

$lookup.GetEnumerator() | Sort-Object Name | ForEach-Object {

  $key = "$($_.Key)"
  $id  = [int] $($_.Key) 
  $name = "$($_.Value.Name)"
  $ip = "$($_.Value.IP)"

  try {
        $ping = Test-Connection -ComputerName $ip -Count $pingCount -ErrorAction Stop -Quiet
        $status = if ($ping) { "Success" } else { "Failed" }
        Write-Host "ID: $($_.Key), Signal Name: $($_.Value.Name), Controller IP: $($_.Value.IP) $status"  
      
        # Get detailed ping statistics if successful
        if ($ping) {
            $stats = Test-Connection -ComputerName $ip -Count $pingCount | Measure-Object -Property ResponseTime -Average -Minimum -Maximum
            $result = [PSCustomObject]@{
                Signal       = $key + "_" + $name
                IPAddress    = $ip
                Status       = $status
                AvgResponse  = [math]::Round($stats.Average, 2)
                MinResponse  = $stats.Minimum
                MaxResponse  = $stats.Maximum
                SuccessCount = ($stats.Count)
             }
        } else {
            $result = [PSCustomObject]@{
                Signal       = $key + "_" + $name
                IPAddress    = $ip
                Status       = $status
                AvgResponse  = "N/A"
                MinResponse  = "N/A"
                MaxResponse  = "N/A"
                SuccessCount = 0
            }
        }
    }
    catch 
    {
       Write-Host "ID: $($_.Key), Signal Name: $($_.Value.Name), Controller IP: $($_.Value.IP) ERROR:"
        $result = [PSCustomObject]@{
            Signal       = $key + "_" + $name
            IPAddress    = $ip
            Status       = "Error"
            AvgResponse  = "N/A"
            MinResponse  = "N/A"
            MaxResponse  = "N/A"
            SuccessCount = 0
            ErrorMessage = $_.Exception.Message
        }
    }
    
    $results += $result
}

# Display results in a formatted table
Write-Host "`nNetwork Connection Test Results" -ForegroundColor Cyan
Write-Host "------------------------------`n"
$results | Format-Table -AutoSize -Property Signal, IPAddress, Status, AvgResponse, MinResponse, MaxResponse, SuccessCount, ErrorMessage

# Summary
$successful = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($results | Where-Object { $_.Status -eq "Failed" -or $_.Status -eq "Error" }).Count
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "Total IPs tested: $($ipAddresses.Count)"
Write-Host "Successful: $successful"
Write-Host "Failed/Error: $failed`n"
