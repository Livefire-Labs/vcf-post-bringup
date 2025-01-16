#################################################################################################
#                                                                                                 
#                               Configure access to offline depot                               
#
#                         You must have PowerVCF and PowerCLI Installed
#
#                         Words and Music By Alasdair Carnie & Ben Sier                         
#                                                                                               
#################################################################################################

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

Logger "Offline Depot Access Configure"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# Define variables for environment
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = $sddcManagerfqdn.Split('.')[0] # If maintaining static values would suggest this method, this way single input
# $sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!VMware123!"

# Offline Depot Access
$username = "vcflivefire"           # Replace with your actual username
$password = "VMware123!"             # Replace with your actual password
$hostname = "depot.livefire.dev"     # Replace with your actual hostname
$sddcMgrFqdn = "sddc-manager.vcf.sddc.lab"  # Replace with your actual SDDC Manager   

# Adding a function to configure access to the offline depot
logger "Adding offline depot configuration function"
function Configure-OfflineDepot {
    param (

        [string]$Username,
        [string]$Password,
        [string]$Hostname,
        [string]$sddcMgrFQDN,
        [int]$Port = 443  # Default port set to 443
    )

    # Set up headers
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $AccessToken")

    # Prepare the body for the HTTP request
    $body = @"
{
    "offlineAccount": {
        "password": "$Password",
        "username": "$Username"
    },
    "depotConfiguration": {
        "hostname": "$Hostname",
        "isOfflineDepot": "true",
        "port": "$Port"
    }
}

"@

    # Send the PUT request to configure the depot
    $response = Invoke-RestMethod -Uri "https://$sddcMgrFqdn/v1/system/settings/depot" -Method 'PUT' -Headers $headers -Body $body
    
    # Convert the response to JSON for better readability
    return $response | ConvertTo-Json
}

# Logging into SDDC Manager
logger "Requesting SDDC Manager Authentication Token"
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass
Start-Sleep 5

logger "Configuring access to the offline depot"
# Configure Offline Depot Access
$response = Configure-OfflineDepot -sddcMgrFqdn $sddcMgrFQDN -Username $username -Password $password -Hostname $hostname
do { $taskStatus = Get-VCFTask -id $($response.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")