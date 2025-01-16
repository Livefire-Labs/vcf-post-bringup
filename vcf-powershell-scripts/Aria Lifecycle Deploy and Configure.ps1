# ====================================================================================
#                    vRealize Suite Lifecycle Manager Deployment                     
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
#                                                                                    
#                   Words By Ben Sier, Music By Alasdair Carnie                      
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

logger "Downloading and Deploying Aria Lifecycle"

# Variables Details could be pulled from the PnP Workbook
logger "Setting Variables for SDDC Manager"
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = $sddcManagerfqdn.Split('.')[0] # If maintaining static values would suggest this method, this way single input
# $sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!VMware123!"

$ariaLCFqdn = "aria-"

# Get the Aria Lifecycle Bundle from the depot.  Give that it can take a cfew cycles for SDDC Manager to pull the full list of available bundles
# and that it does not pull the bundle list in any logical order, I created a loop to keep checking until the bundle is available, before continuing
$maxWaitTimeMinutes = 10
$retryIntervalSeconds = 60
$matchedBundles = $null
$startTime = Get-Date

# Loop to keep checking for matched bundles
while ($matchedBundles -eq $null) {
    # Get the bundles that match the requirements
    $matchedBundles = Get-VCFBundle | Where-Object {
        $bundle = $_
        $bundle.components | Where-Object { 
            ($_.toVersion -match "8.18") -and ($_.description -match "vRSLCM Bundle")
        } | ForEach-Object {
            $bundle
        }
    }

    # Check if any matched bundles were found
    if ($matchedBundles -eq $null) {
        Write-Host "No matched bundles found. Retrying in $retryIntervalSeconds seconds..."
        Start-Sleep -Seconds $retryIntervalSeconds
        
        # Check if we've exceeded the maximum wait time
        $currentTime = Get-Date
        if (($currentTime - $startTime).TotalMinutes -ge $maxWaitTimeMinutes) {
            Write-Host "Exceeded maximum wait time of $maxWaitTimeMinutes minutes. Check SDDC Mananger Depot connection."
            exit 1  # Exit the script with a status code of 1
        }
    } else {
        Write-Host "Matched bundles found."
    }
}

# Proceed with the rest of the script using $matchedBundles
$matchedBundles

# Download the vRealize Suite Lifecycle Manager Bundle and monitor the task until comleted
$requestBundle = Request-VCFBundle -id $vrslcmBundle.id
Sleep 5
do {$taskStatus = Get-VCFTask -id $($requestBundle.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
Write-Host "vRealize Suite Lifecycle Manager Download Complete"

# Create the JSON Specification for vRealize Suite Lifecyclec Manager Deployment
Write-Host "Creating JSON Specification File"
$vrslcmDepSpec = [PSCustomObject]@{apiPassword= 'VMware123!';fqdn= $ariaLCFqdn;nsxtStandaloneTier1Ip= '10.60.0.250';sshPassword= 'VMware123!'}
$vrslcmDepSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath .\vrslcmDepSpec.json

# Validate the settings
Write-Host "Validating JSON Settings"
$vrslcmValidate = New-VCFvRSLCM -json .\vrslcmDepSpec.json -validate
Sleep 5
do {$taskStatus = Get-VCFTask -id $($vrslcmValidate.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
Write-Host "Validation Complete"

# Deploy vRealize Suite Lifecycle Manager
$vrslcmDeploy = New-VCFvRSLCM -json .\vrslcmDepSpec.json
Write-Host "Deploying vRealize Suite Lifecycle Manager"
sleep 5
do {$taskStatus = Get-VCFTask -id $($vrslcmDeploy.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
Write-Host "Deployment Completed Successfully"

# ==================== Create and deploy Certificate for vRSLCM ====================

$domainName = Get-VCFWorkloadDomain | Where-Object {$_.type -match "MANAGEMENT"} |Select -ExpandProperty name
$vrslcm = Get-VCFvRSLCM
$vrslcm | Add-Member -Type NoteProperty -Name Type -Value "VRSLCM"

# Create JSON Specification for vRSLCM Certificate Signing Request
Write-Host "Creating JSON Specification for vRSLCM Certificate Signing Request"
$csrVrslcm = [PSCustomObject]@{
    csrGenerationSpec = @{country= 'us';email= 'admin@elasticsky.org';keyAlgorithm= 'RSA';keySize= '2048';locality= 'Champaign';organization= 'Elasticsky';organizationUnit='IT';state= 'Illinois'}
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.Type})
}

# Create the JSON file for vRSLCM CSR Generation
$csrVrslcm | ConvertTo-Json -Depth 10 | Out-File -Filepath .\csrcrslcmSpec.json

# Generate CSR for vRSLCM Certificate
Write-Host "Requesting vRSLCM CSR for $domainName"
$csrVrslcmReq = Request-VCFCertificateCSR -domainName $domainName -json .\csrsvrslcmSpec.json
do {$taskStatus = Get-VCFTask -id $($csrVrslcmReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")

# Create JSON Specification for vRSLCM Certificate Generation
Write-Host "Creating JSON specification for vRSLCM Certificate Request"
$certVrslcmSpec = [PSCustomObject]@{
    caType = "Microsoft"
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.type})
}

# Request the creation of certificate for vRSLCM
$certvrslcmSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath .\certVrslcmSpec.json

Write-Host "Generating vRSLCM Certificate on CA for $domainName"
$certVrslcmCreateReq = Request-VCFCertificate -domainName $domainName -json .\certVrslcmSpec.json
do {$taskStatus = Get-VCFTask -id $($certVrslcmCreateReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")

# Install certificate on vRSLCM
$certVrslcmInstallSpec = [PSCustomObject]@{
    operationType = "INSTALL"
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.type})
}

$certVrslcmInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath .\certVrslcmInstallSpec.json
Write-Host "Installing Certificates for $domainName"
$certVrslcmInstallReq = Set-VCFCertificate -domainName $domainName -json .\certVrslcmInstallSpec.json
do {$taskStatus = Get-VCFTask -id $($certVrslcmInstallReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")
