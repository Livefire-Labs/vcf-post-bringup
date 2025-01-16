# Variables for the execution log file and json file directories.
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

Logger "Deploying AVN Configuration"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables
logger "Creating SDDC Manager variables"
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = "sddc-manager"

# Authenticate to SDDC Manager using global variables defined at the top of the script
logger "Authenticating with SDDC Manager"
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass

Start-Sleep 5

# Get the Edge Cluster ID
logger "Getting Edge Cluster ID"
$edgeClusterId = Get-VCFEdgeCluster | Select-Object -ExpandProperty id

# Variables to check for the existance of AVNs, and to create them if required.
logger "Injesting AVN Variables"
$avnsLocalGw = "10.50.0.1"
$avnsLocalMtu = "8000"
$avnsLocalName = "region-seg-1"
$avnsLocalRegionType = "REGION_A"
$avnsLocalRouterName = "VLC-Tier-1"
$avnsLocalSubnet = "10.50.0.0"
$avnsLocalSubnetMask = "255.255.255.0"

$avnsXRegGw = "10.60.0.1"
$avnsXRegMtu = "8000"
$avnsXRegName = "xregion-seg01"
$avnsXRegRegionType = "X_REGION"
$avnsXRegRouterName = "VLC-Tier-1"
$avnsXRegSubnet = "10.60.0.0"
$avnsXRegSubnetMask = "255.255.255.0"

#Create AVN Configration JSON file
logger "Creating AVN Configuration JSON file"

$avnLocal = @{
    gateway      = $avnsLocalGw
    mtu          = $avnsLocalMtu
    name         = $avnsLocalName
    regionType   = $avnsLocalRegionType
    routerName   = $avnsLocalRouterName
    subnet       = $avnsLocalSubnet
    subnetMask   = $avnsLocalSubnetMask
}

$avnXRegion = @{
    gateway      = $avnsXRegGw
    mtu          = $avnsXRegMtu
    name         = $avnsXRegName
    regionType   = $avnsXRegRegionType
    routerName   = $avnsXRegRouterName
    subnet       = $avnsXRegSubnet
    subnetMask   = $avnsXRegSubnetMask
}

# Build the complete object with avns array and edgeClusterId
$avnOutput = [ordered] @{
    avns          = @($avnLocal, $avnXRegion)
    edgeClusterId = $edgeClusterId
}

# Convert the hashtable to JSON
logger "Saving configurartion to JSON file"
$($avnOutput | ConvertTo-Json -Depth 10) | Out-File "$($jsonPathDir.FullName)\avns.json"

	logger "Validating AVN configuration"
	Add-VCFApplicationVirtualNetwork  -json "$scriptDir\json\avns.json" -validate -ErrorVariable validation_err -ErrorAction SilentlyContinue | Out-Null
	if($validation_err)
	{
		logger "Validation failed with below error /n $($validation_err.Exception.Message)"
	}
	else 
	{
		#Deploy the AVN Configuration
		logger "Configuring the Edge Cluster with AVN Segments"
		$avnDeploy = Add-VCFApplicationVirtualNetwork  -json "$scriptDir\json\avns.json"
		do { $taskStatus = Get-VCFTask -id $($avnDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
		logger "AVN Configuration deployed successfully"
	}