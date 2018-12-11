# Author: scott sutherland
# This script uses tshark to parse the src.ip, dst.ip, and dst.port from a provided .cap file. It then looks up owner information.
# Todo: add src filters, add threading (its super slow), add udp parsing
# Note: currently udp ports are not imported and show up as 0
# information on ips are grabbed from arin.net and ip-api.com

# Example commands
# Get-IpInfoFromCap -capPath "c:\temp\packetcapture.cap" -Verbose -DstIp 1.1.1.1
# Get-IpInfoFromCap -capPath "c:\temp\packetcapture.cap" -Verbose -DstIp 1.1.1.1 -UDP
# Get-IpInfoFromCap -capPath "c:\temp\packetcapture.cap" -Verbose -DstIp 1.1.1.1 | Out-GridView
# Get-IpInfoFromCap -capPath "c:\temp\packetcapture.cap" -Verbose -DstIp 1.1.1.1 | Export-Csv c:\temp\output.csv
# Get-IpInfoFromCap -capPath "c:\temp\packetcapture.cap" -Verbose -DstIp 1.1.1.1 -IpAPI

Function Get-IpInfoFromCap{

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$True, ValueFromPipeline = $true, HelpMessage="Cap file path.")]
        [string]$capPath,
        [string]$SrcIp,
        [string]$DstIp,
        [int]$Port,
        [string]$TsharkPath,
        [switch]$IpAPI,
        [switch]$UDP
    )
       
    Begin
    {
        # Set TCP/UDP variable for filtering
        if ($UDP){$protocol = "udp"}else{$protocol= "tcp"}
        # Set tshark path
        if( -not $TsharkPath){           
            $TsharkPath = 'C:\Program Files\Wireshark\tshark.exe'
        }

        # Verify tshark path
        If ((Test-Path $TsharkPath) -eq $True) {
            Write-Verbose "The tshark path is valid: $TsharkPath"
        }else{
            Write-Host "The tshark path is invalid: $TsharkPath"
            return
        }        

        # Port table
        $TblPortInfo = New-Object System.Data.DataTable
        $TblPortInfo.Columns.Add("SrcIp") | Out-Null
        $TblPortInfo.Columns.Add("DstIp") | Out-Null
        $TblPortInfo.Columns.Add("Ports") | Out-Null
     
        # IP info table
        $TblIPInfo = new-object System.Data.DataTable
        $TblIPInfo.Columns.Add("IpDest") | Out-Null
        $TblIPInfo.Columns.Add("IpSrc") | Out-Null
        $TblIPInfo.Columns.Add("Owner") | Out-Null
        $TblIPInfo.Columns.Add("StartRange") | Out-Null
        $TblIPInfo.Columns.Add("EndRange") | Out-Null
        $TblIPInfo.Columns.Add("Country") | Out-Null
        $TblIPInfo.Columns.Add("City") | Out-Null
        $TblIPInfo.Columns.Add("Zip") | Out-Null
        $TblIPInfo.Columns.Add("ISP") | Out-Null
        #$TblIPInfo.Columns.Add("Ports") | Out-Null     
        
        # Output table
        $OutputTbl = new-object System.Data.DataTable
        $OutputTbl.Columns.Add("IpSrc") | Out-Null
        $OutputTbl.Columns.Add("IpDest") | Out-Null       
        $OutputTbl.Columns.Add("Owner") | Out-Null
        $OutputTbl.Columns.Add("StartRange") | Out-Null
        $OutputTbl.Columns.Add("EndRange") | Out-Null
        $OutputTbl.Columns.Add("Country") | Out-Null
        $OutputTbl.Columns.Add("City") | Out-Null
        $OutputTbl.Columns.Add("Zip") | Out-Null
        $OutputTbl.Columns.Add("ISP") | Out-Null
        $OutputTbl.Columns.Add("Ports") | Out-Null                            
    }

    Process
    {
        # Set cap file path
        if( -not $capPath){           
            Write-Host "No cap file provided."
            return
        }

        # Verify cap path
        If ((Test-Path $capPath) -eq $True) {
            Write-Verbose "The cap path is valid: $capPath"
        }else{
            Write-Host "The cap path is invalid: $capPath"
            return
        }                                  
            
        # Set DstIp filter
        if(-not $DstIp){           
            $DstIpFilter = ""
        }else{
            $DstIpFilter = "-Yip.dst==$DstIp"
        }

        # Execute tshark command (parse cap)
        Write-Verbose "Parsing cap file to variable"
        try{

            #$TsharkCmdOutput = &$TsharkPath -r $capPath -T fields -e ip.src -e ip.dst -e tcp.dstport $DstIpFilter -E header=y -E separator=`, -E occurrence=f
            $a1 = "-r$capPath"
            $a2 = "-Tfields"
            $a3 = "-eip.src"
            $a4 = "-eip.dst"
            $a5 = "-e$protocol.dstport"
            $a7 = "-Eheader=y"
            $a8 = "-Eseparator=`,"
            $a9 = "-Eoccurrence=f"

            $TsharkCmdOutput = &$TsharkPath $a1 $a2 $a3 $a4 $a5 $DstIpFilter $a7 $a8 $a9

        }catch{
            Write-Warning "Bummer. Something went wrong..."
            return
        }
        
        # Import data tshark parsed
        $CapData = ConvertFrom-Csv -InputObject $TsharkCmdOutput

        # Import all parsed data (SrcIp, DstIp, Port) into $TblPortInfo
        $capDataIpOnly = $CapData | select ip.src,ip.dst -Unique | Sort-Object ip.src | select -Skip 1

        # Status user
        Write-Host "Getting IP information..."

        # Lookup source IP owner and location
        $capDataIpOnly | ForEach-Object {

            # Get source IP
            $IpAddress = $_.'ip.src'        
            $CurrentDest = $_.'ip.dst' 

            # Send whois request to arin via restful api
            $web = new-object system.net.webclient
            [xml]$results = $web.DownloadString("http://whois.arin.net/rest/ip/$IpAddress")

            # Send location query to http://ip-api.com via xml api
            if ($IpAPI){
                $web2 = new-object system.net.webclient
                [xml]$results2 = $web2.DownloadString("http://ip-api.com/xml/$IpAddress")
            }

            # Parse data from responses    
            $IpOwner = $results.net.name 
            $IpStart = $results.net.startAddress
            $IpEnd = $results.net.endaddress  
            $IpCountry = $results2.query.country.'#cdata-section'
            $IpCity = $results2.query.city.'#cdata-section'
            $IpZip = $results2.query.zip.'#cdata-section'
            $IpISP = $results2.query.isp.'#cdata-section'

            # Put results in the data table   
            $TblIPInfo.Rows.Add("$CurrentDest",
                              "$IpAddress",
                              "$IpOwner",
                              "$IpStart",
                              "$IpEnd",
                              "$IpCountry",
                              "$IpCity",
                              "$IpZip",
                              "$IpISP") | Out-Null

            # status the user
            Write-Verbose "Dest:$CurrentDest Src:$IpAddress Owner: $IpOwner ($IpCountry) ($IpStart -$IpEnd)"
    
        }
        
        # Status user
        Write-Host "Consolidating ports..."

        # Get list of unique src ips
        $CapSrcIps = $CapData | select ip.src,ip.dst -Unique | Sort-Object ip.src 

        # Iterate through each IP
        $CapSrcIps | 
        ForEach-Object{
            
            # Combine ports with list
            $SourceIp =  $_.'ip.src'
            $DestinationIp =  $_.'ip.dst'

            # loop through full list
            $CapData | select ip.src,ip.dst,"$protocol.dstport" -Unique |
            ForEach-Object{

                $Src = $_.'ip.src'
                $Dst = $_.'ip.dst'
                $Port = $_."$protocol.dstport"

                # check if it is current ip
                if(($SourceIp -eq $Src) -and ($DestinationIp -eq $Dst)){                    

                    # build port list
                    $ports = "$ports$port,"
                    $GoodSrc =  $Src
                    $GoodDst = $Dst
                    $GoodPort = $Port
                }
            }

            # remove trailing 
            $ports = $ports.Substring(0,$ports.Length-1)

            # Add ip info to final list
            $TblPortInfo.Rows.Add($GoodSrc,$GoodDst,$ports) | out-null

            # clear port list
            $ports = ""
        }  

        # Status user
        Write-Host "Merging records..."

        # Combine Lists
         $TblPortInfo | 
         ForEach-Object{

            # Get port information
            $PortIpSrc = $_.SrcIp
            $PortIpDst = $_.DstIp
            $PortIpPorts = $_.Ports

            # Get IP information & merge
            $TblIPInfo | 
            ForEach-Object{
                
                # Get ip info
                $IpInfoIpSrc = $_.IpSrc
                $IpInfoIpDst = $_.IpDest                
                $IpInfoOwner = $_.Owner
                $IpInfoStartRange = $_.StartRange
                $IpInfoEndRange = $_.EndRange
                $IpInfoCountry = $_.Country
                $IpInfoCity = $_.City
                $IpInfoZip = $_.Zip
                $IpInfoISP = $_.ISP

                # Check for ip match
                if (($PortIpSrc -eq $IpInfoIpSrc) -and ($PortIpDst -eq $IpInfoIpDst)){

                    # Put results in the data table   
                    $OutputTbl.Rows.Add($IpInfoIpSrc,
                                        $IpInfoIpDst,               
                                        $IpInfoOwner,
                                        $IpInfoStartRange,
                                        $IpInfoEndRange,
                                        $IpInfoCountry,
                                        $IpInfoCity,
                                        $IpInfoZip,
                                        $IpInfoISP,
                                        $PortIpPorts) | Out-Null
                }
            }                   
         }
    }

    End
    {    
        # Status user
        Write-Host "Done."     
        
        # Return the full result set
        $OutputTbl | Sort-Object Owner -Unique                
    }
}
