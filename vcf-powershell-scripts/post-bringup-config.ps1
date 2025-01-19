# ====================================================================================
#                 VMware Cloud Foundation Post BringUp Configuration                 
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
#                                                                                    
#                   Words and Music By Alasdair Carnie & Ben Sier                      
# ====================================================================================

# Variables for the execution log file and json file directories.
Clear-Host
$scriptDir = Split-Path $MyInvocation.MyCommand.Path # Log file diretories will be created in the folder you exeute the script from
$logPathDir = New-Item -ItemType Directory -Path "$scriptDir\Logs" -Force
$jsonPathDir = New-Item -ItemType Directory -Path "$scriptDir\json" -Force
$logfile = "$logPathDir\VVS-Log-_$(get-date -format `"yyyymmdd_hhmmss`").txt"

# Custom function to create a separate logging window for script execution.
Function logger($strMessage, [switch]$logOnly,[switch]$consoleOnly)
{
	$curDateTime = get-date -format "hh:mm:ss"
	$entry = "$curDateTime :> $strMessage"
    if ($consoleOnly) {
		write-host $entry
    } elseif ($logOnly) {
		$entry | out-file -Filepath $logfile -append
	} else {
        write-host $entry
		$entry | out-file -Filepath $logfile -append
	}
}

logger "
__     ______ _____   _     _            __ _                   
\ \   / / ___|  ___| | |   (_)_   _____ / _(_)_ __ ___          
 \ \ / / |   | |_    | |   | \ \ / / _ \ |_| | '__/ _ \         
  \ V /| |___|  _|   | |___| |\ V /  __/  _| | | |  __/         
 __\_/  \____|_|_    |_____|_| \_/ \___|_| |_|_|  \___|         
|  _ \ ___  ___| |_  | __ ) _ __(_)_ __   __ _ _   _ _ __       
| |_) / _ \/ __| __| |  _ \| '__| | '_ \ / _` | | | | '_ \      
|  __/ (_) \__ \ |_  | |_) | |  | | | | | (_| | |_| | |_) |     
|_|   \___/|___/\__| |____/|_|  |_|_| |_|\__, |\__,_| .__/      
  ____             __ _                  |___/_   _ |_|         
 / ___|___  _ __  / _(_) __ _ _   _ _ __ __ _| |_(_) ___  _ __  
| |   / _ \| '_ \| |_| |/ _` | | | | '__/ _` | __| |/ _ \| '_ \ 
| |__| (_) | | | |  _| | (_| | |_| | | | (_| | |_| | (_) | | | |
 \____\___/|_| |_|_| |_|\__, |\__,_|_|  \__,_|\__|_|\___/|_| |_|
                        |___/                                  

 VCF Certificate Configuration.  Brought to you by the letters L and F, and by the number 42"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables [Gary] Details could be pulled from the PnP Workbook
logger "Setting Variables for SDDC Manager"
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = $sddcManagerfqdn.Split('.')[0] # If maintaining static values would suggest this method, this way single input
# $sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!VMware123!"

# Authenticate to SDDC Manager using global variables defined at the top of the script
if (Test-VCFConnection -server $sddcManagerfqdn) {
    if (Test-VCFAuthentication -server $sddcManagerfqdn -user $ssoUser -pass $ssoPass) { 

        # ==================== Configure Microsoft Certificate Authority Integration, and create and deploy certificates for vCenter, NSX-T and SDDC Manager ====================

        # Setting Microsoft CA Variables for adding the CA to SDDC Manager [Gary] Details could be pulled from the PnP Workbook
        logger "Setting Variables for Configuring the Microsoft CA"
        $mscaUrl = "https://vcfad.vcf.holo.lab/certsrv"
        $mscaUser = "svc-vcf-ca@vcf.holo.lab"
        $mscaPassword = "VMware123!"

        # Register Microsoft CA with SDDC Manager
        if (!(Get-VCFCertificateAuthority).username) {
            logger "Registering the Microsoft CA with SDDC Manager"
            Set-VCFMicrosoftCA -serverUrl $mscaUrl -username $mscaUser -password $mscaPassword -templateName VMware
            Start-Sleep 5
        } else {
            logger "Registering Microsoft CA with SDDC Manager Already Configured"
        }

        # Setting Certificate Variables # Details could be pulled from the PnP Workbook
        logger "Setting Variables for Certificate Replacement"
        $domainName = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty name
        $vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
        $vcenter | Add-Member -Type NoteProperty -Name Type -Value "VCENTER"
        $nsxTCluster = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty nsxtCluster
        $nsxTCluster | Add-Member -MemberType NoteProperty -Name Type -Value "NSXT_MANAGER"
        $sddcCertManager = Get-VCFManager | Select-Object id, fqdn
        $sddcCertManager | Add-Member -MemberType NoteProperty -Name Type -Value "SDDC_MANAGER"
        $country = "us"
        $keySize = "2048"
        $keyAlg = "RSA"
        $locality = "Champaign"
        $org = "Holo"
        $orgUnit = "IT"
        $state = "IL"
        $email = "administrator@vcf.holo.lab"

        if (!(Get-VCFCertificate -domainName $domainName -resources | Select-Object IssuedBy | Where-Object {$_ -match 'DC='+($mscaUrl.Split('.'))[1]})) {
            # Create the JSON file for CSR Generation
            logger "Creating JSON file for CSR request in $domainName"
            $csrsGenerationSpec = New-Object -TypeName PSCustomObject 
            $csrsGenerationSpec | Add-Member -NotePropertyName csrGenerationSpec -NotePropertyValue @{country = $country; email = $email; keyAlgorithm = $keyAlg; keySize = $keySize; locality = $locality; organization = $org; organizationUnit = $orgUnit; state = $state }
            $csrsGenerationSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })
            $csrsGenerationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrsGenerationSpec.json

            # Create CSRs for vCenter, NSX-T and SDDC Manager
            logger "Requesting CSR's for $domainName"
            $csrReq = Request-VCFCertificateCSR -domainName $domainName -json $jsonPathDir\csrsGenerationSpec.json
            do { $taskStatus = Get-VCFTask -id $($csrReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

            # Create JSON Spec for requesting certificates
            logger "Creating JSON spec for certificate creation in $domainName"
            $certCreateSpec = New-Object -TypeName PSCustomObject 
            $certCreateSpec | Add-Member -NotePropertyName caType -NotePropertyValue "Microsoft"
            $certCreateSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })
            $certCreateSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certCreateSpec.json

            # Request the creation of certificates for vCenter, NSX-T and SDDC Manager
            logger "Generating Certificates on CA for $domainName"
            $certCreateReq = Request-VCFCertificate -domainName $domainName -json $jsonPathDir\certCreateSpec.json
            do { $taskStatus = Get-VCFTask -id $($certCreateReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

            # Create JSON Spec for installing certificates
            logger "Creating JSON Spec for installing certificates"
            $certInstallSpec = New-Object -TypeName PSCustomObject
            $certInstallSpec | Add-Member -NotePropertyName operationType -NotePropertyValue "INSTALL"
            $certInstallSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })
            $certInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certInstallSpec.json

            # Install certificates on vCenter, NSX-T and SDDC Manager
            logger "Installing Certificates for $domainName"
            $certInstallReq = Set-VCFCertificate -domainName $domainName -json $jsonPathDir\certInstallSpec.json
            do { $taskStatus = Get-VCFTask -id $($certInstallReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
        } else {
            logger "Installation of Microsoft CA Signed Certificates Already Performed"
        }

        # ==================== Configure SDDC Manager Backup ====================
        $vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
        Connect-VIServer -server $vcenter.fqdn -user $ssoUser -password $ssoPass | Out-Null

        # Variables for configuring the SDDC Manager and NSX-T Manager Backups
        logger "Setting Variables for Backup and extracting SSH Key for Backup User"
        $backupServer = "10.0.0.253"
        $backupPort = "22"
        $backupPath = "/home/admin"
        $backupUser = "admin"
        $backupPassword = "VMware123!VMware123!"
        $backupProtocol = "SFTP"
        $backupPassphrase = "VMware123!VMware123!"

        if ((Get-VCFBackupConfiguration | Select-Object server).server -ne $backupServer) { 
            $getKeyCommand = "ssh-keygen -lf <(ssh-keyscan -t rsa $backupServer 2>/dev/null) | cut -d ' ' -f 2"
            $keyCommandResult = Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $getKeyCommand -ErrorVariable ErrMsg
            $backupKey = $keyCommandResult.ScriptOutput.Trim()

            # Creating Backup Config JSON file
            logger "Create Backup Configuration JSON Specification"
            $backUpConfigurationSpec = [PSCustomObject]@{
                backupLocations = @(@{server = $backupServer; username = $backupUser; password = $backupPassword; port = $backupPort; protocol = $backupProtocol; directoryPath = $backupPath; sshFingerprint = $backupKey })
                backupSchedules = @(@{frequency = 'HOURLY'; resourceType = 'SDDC_MANAGER'; minuteOfHour = '0' })
                encryption      = @{passphrase = $backupPassphrase }
            }
            logger "Creating Backup Configuration JSON file"
            $backUpConfigurationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\backUpConfigurationSpec.json

            # Configuring SDDC Manager Backup settings
            logger "Configuring SDDC Manager Backup Settings"
            $confVcfBackup = Set-VCFBackupConfiguration -json $($backUpConfigurationSpec | ConvertTo-Json -Depth 10)
            do { $taskStatus = Get-VCFTask -id $($confVcfBackup.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
        } else {
            logger "Reconfiguration of Backup Already Performed"
        }
        
       Disconnect-VIServer * -Confirm:$false -WarningAction SilentlyContinue | Out-Null
    }
}