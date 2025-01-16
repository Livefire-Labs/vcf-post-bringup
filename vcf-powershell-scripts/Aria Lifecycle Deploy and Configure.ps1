# ====================================================================================
#                    vRealize Suite Lifecycle Manager Deployment                     
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
#                                                                                    
#                       Words & Music By Alasdair Carnie                     
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

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# Variables Details could be pulled from the PnP Workbook
logger "Setting Variables for SDDC Manager"
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = $sddcManagerfqdn.Split('.')[0] # If maintaining static values would suggest this method, this way single input
# $sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!VMware123!"

# Aria Lifecycle Variables
$ariaLCMFqdn = "aria-lcm.vcf.sddc.lab"
$standAloneLB = "10.60.0.250"
$ariaLCMPassword = "VMware123!"

Request-VCFToken -username $ssoUser -password $ssoPass -fqdn $sddcManagerfqdn

# Get the Aria Lifecycle Bundle from the depot.  Give that it can take a cfew cycles for SDDC Manager to pull the full list of available bundles
# and that it does not pull the bundle list in any logical order, I created a loop to keep checking until the bundle is available, before continuing
$maxWaitTimeMinutes = 10
$retryIntervalSeconds = 60
$ariaLCMBundle = $null
$startTime = Get-Date

# Loop to keep checking for matched bundles
while ($ariaLCMBundle -eq $null) {
    # Get the bundles that match the requirements
    $ariaLCMBundle = Get-VCFBundle | Where-Object {
        $bundle = $_
        $bundle.components | Where-Object { 
            ($_.toVersion -match "8.18") -and ($_.description -match "vRSLCM Bundle")
        } | ForEach-Object {
            $bundle
        }
    }

    # Check if any matched bundles were found
    if ($ariaLCMBundle -eq $null) {
        Write-Host "No matched Aria bundle found. Retrying in $retryIntervalSeconds seconds..."
        Start-Sleep -Seconds $retryIntervalSeconds
        
        # Check if we've exceeded the maximum wait time
        $currentTime = Get-Date
        if (($currentTime - $startTime).TotalMinutes -ge $maxWaitTimeMinutes) {
            Write-Host "Exceeded maximum wait time of $maxWaitTimeMinutes minutes. Check SDDC Mananger Depot connection."
            exit 1  # Exit the script with a status code of 1
        }
    } else {
        Write-Host "Matched Aria bundle found."
    }
}

# Proceed with the rest of the script using $ariaLCMBundle
$ariaLCMBundle

Sleep 10

if ($ariaLCMBundle | Where-Object {$_.downloadstatus -eq "successful"}) {
    Write-Host "Aria Lifecycle Bundle has already been downloaded. Skipping download..."
    # Continue with the rest of the script
    # Download the Aria Lifecycle Bundle, and monitor the task until completed
    logger "Bundle already downloaded, skipping download..."
    # Continue with the rest of the script
} else {
    Write-Host "Aria Lifecycle Bundle has not been downloaded yet. Downloading..."
    # Download the Aria Lifecycle Bundle, and monitor the task until completed
    logger "Requesting Aria Lifecycle Bundle"
    $requestBundle = Request-VCFBundle -id $ariaLCMBundle.id
    Sleep 5
    do {$taskStatus = Get-VCFTask -id $($requestBundle.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
    sleep 30
    Write-Host "Aria Suite Lifecycle Download Complete"
    logger "Bundle Download Complete"
}

# Create the JSON Specification for Aria Deployment
Logger "Creating JSON Specification"
Write-Host "Creating JSON Specification File"
$ariaLCMDepSpec = [PSCustomObject]@{apiPassword= @ariaLCMPassword;fqdn= $ariaLCMFqdn;nsxtStandaloneTier1Ip= $standAloneLB;sshPassword= $ariaLCMPassword}
$ariaLCMDepSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\ariaLCMDepSpec.json
logger "JSOn Creation Complete"

# Validating the settings
logger "Validating JSON Settings"
Write-Host "Validating JSON Settings"
$ariaLCMValidate = New-VCFvRSLCM -json $jsonPathDir\ariaLCMDepSpec.json -validate

Sleep 5

do {$taskStatus = Get-VCFTask -id $($ariaLCMValidate.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
Write-Host "Validation Complete"
logger "Validation Complete"

# Deploy Aria Lifecycle
logger "Deploying Aria Lifecycle"
$ariaLCMDeploy = New-VCFvRSLCM -json $jsonPathDir\ariaLCMDepSpec.json
Write-Host "Deploying Aria Lifecycle"
sleep 5
do {$taskStatus = Get-VCFTask -id $($ariaLCMDeploy.id)| Select status;sleep 5} until ($taskStatus -match "Successful")
Write-Host "Deployment Completed Successfully"
logger "Aria Lifecycle deployment complete"

# ==================== Create and deploy Certificate for Aria Lifecycle ====================
logger "Creating certificate request for Aria Lifecycle"
$domainName = Get-VCFWorkloadDomain | Where-Object {$_.type -match "MANAGEMENT"} |Select -ExpandProperty name
$vrslcm = Get-VCFvRSLCM
$vrslcm | Add-Member -Type NoteProperty -Name Type -Value "VRSLCM"

# Create JSON Specification for Aria Lifecycle Certificate Signing Request
Write-Host "Creating JSON Specification for Aria Lifecycle Certificate Signing Request"
$csrVrslcm = [PSCustomObject]@{
    csrGenerationSpec = @{country= 'us';email= 'admin@vcf.holo.org';keyAlgorithm= 'RSA';keySize= '2048';locality= 'Champaign';organization= 'Holo';organizationUnit='IT';state= 'Illinois'}
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.Type})
}
logger "Requesting Aria Lifecycle Certificate"
# Create the JSON file for Aria Lifecycle CSR Generation
$csrVrslcm | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrvrslcmSpec.json

# Generate CSR for Aria Lifecycle Certificate
Write-Host "Requesting vRSLCM CSR for $domainName"
$csrVrslcmReq = Request-VCFCertificateCSR -domainName $domainName -json $jsonPathDir\csrsvrslcmSpec.json
do {$taskStatus = Get-VCFTask -id $($csrVrslcmReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")

# Create JSON Specification for Aria Lifecycle Certificate Generation
Write-Host "Creating JSON specification for vRSLCM Certificate Request"
$certVrslcmSpec = [PSCustomObject]@{
    caType = "Microsoft"
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.type})
}

# Request the creation of certificate for Aria Lifecycle
logger "Creating Certificate"
$certvrslcmSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmSpec.json

Write-Host "Generating Aria Lifecycle Certificate on CA for $domainName"
$certVrslcmCreateReq = Request-VCFCertificate -domainName $domainName -json .\certVrslcmSpec.json
do {$taskStatus = Get-VCFTask -id $($certVrslcmCreateReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")

# Install certificate on Aria Lifecycle
logger "Installing Aria Lifecycle Certificate"
$certVrslcmInstallSpec = [PSCustomObject]@{
    operationType = "INSTALL"
    resources = @(@{fqdn=$vrslcm.fqdn;name=$vrslcm.fqdn;sans=@($vrslcm.fqdn);resourceID=$vrslcm.id;type=$vrslcm.type})
}

$certVrslcmInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmInstallSpec.json
Write-Host "Installing Certificates for $domainName"
$certVrslcmInstallReq = Set-VCFCertificate -domainName $domainName -json $jsonPathDir\certVrslcmInstallSpec.json
do {$taskStatus = Get-VCFTask -id $($certVrslcmInstallReq.id) | Select status;sleep 5} until ($taskStatus -match "Successful")
