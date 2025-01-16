# This PowerShell script breaks down the component parts of an edge cluster and creates a series of system objects for each section.  It then combines them, and outputs a JSON file for use in automated deployments.

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

Logger "Deploying MGMT WLD Edge Cluster and AVN Configuration"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables
$sddcManagerfqdn = "sddc-manager.vcf.sddc.lab"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!VMware123!"
$sddcMgrVMName = "sddc-manager"
$sddcUser = "root"
$sddcPassword = "VMware123!VMware123!"

# Common Edge Cluster or Node Variables
$asn = "65003"
$asnPeer = "65001"
$bgpPeerPassword = "VMware123!VMware123!"
$masterPassword = "VMware123!VMware123!"
$uplink1Peer = "10.0.15.1/24"
$uplink2Peer = "10.0.16.1/24"

$tier0Name = "VLC-Tier-0"
$tier1Name = "VLC-Tier-1"
$routingType = "EBGP"
$tier0ServiceHA = "ACTIVE_ACTIVE"
$ecName = "EC-01"
$edgeClusterProfileType = "DEFAULT"
$edgeClusterType = "NSX-T"
$formFactor = "LARGE"

$edge1Uplink1InterfaceIP = "10.0.15.2/24"
$edge1Uplink2InterfaceIP = "10.0.16.2/24"
$edge2Uplink1InterfaceIP = "10.0.15.3/24"
$edge2Uplink2InterfaceIP = "10.0.16.3/24"

$uplink1Vlan = "15"
$uplink2Vlan = "16"

$clusterId = ""
$managementGateway = "10.0.11.253"
$edgeTepVlan = "17"
$edgeTepGateway = "10.0.17.253"

# Unique Edge Node 1
$edge1NodeName = "edge1-mgmt.vcf.sddc.lab"
$edge1Tep1IP = "10.0.17.2/24"
$edge1Tep2IP = "10.0.17.3/24"
$edgeNode1managementIP = "10.0.11.23/24"

# Unique Edge Node 2
$edge2NodeName = "edge2-mgmt.vcf.sddc.lab"
$edge2Tep1IP = "10.0.17.4/24"
$edge2Tep2IP = "10.0.17.5/24"
$edgeNode2managementIP = "10.0.11.24/24"

# Here is where we will start the creation of the system objects

# Authenticate to SDDC Manager using global variables defined at the top of the script
logger "Requesting SDDC Manager Authentication Token"
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass
Start-Sleep 5

# Get the management cluster ID from SDDC Manager and store it in a variable
logger "Getting the Management Cluster ID"
$sddcClusterid = $(get-vcfworkloaddomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty clusters).id

# Creating uplink networks for edgeNode1
logger "Creating the uplink configuration for Edge Node 1"

$uplinkNetworkEdge1_1 = @{
    asnPeer            = $asnPeer
    bgpPeerPassword    = $bgpPeerPassword
    peerIP             = $uplink1Peer
    uplinkInterfaceIP  = $edge1Uplink1InterfaceIP
    uplinkVlan         = $uplink1vLan
}

$uplinkNetworkEdge1_2 = @{
    asnPeer            = $asnPeer
    bgpPeerPassword    = $bgpPeerPassword
    peerIP             = $uplink2Peer
    uplinkInterfaceIP  = $edge1Uplink2InterfaceIP
    uplinkVlan         = $uplink2vLan
}

# Creating uplink networks for edgeNode2
logger "Creating the uplink configuration for Edge Node 2"

$uplinkNetworkEdge2_1 = @{
    asnPeer            = $asnPeer
    bgpPeerPassword    = $bgpPeerPassword
    peerIP             = $uplink1Peer
    uplinkInterfaceIP  = $edge2Uplink1InterfaceIP
    uplinkVlan         = $uplink1Vlan
}

$uplinkNetworkEdge2_2 = @{
    asnPeer            = $asnPeer
    bgpPeerPassword    = $bgpPeerPassword
    peerIP             = $uplink2Peer
    uplinkInterfaceIP  = $edge2Uplink2InterfaceIP
    uplinkVlan         = $uplink2Vlan
}

# Creating edge node specs
logger "Creating Edge Node 1 & 2 Configuration"

$edgeNode1 = @{
    clusterId           = $sddcClusterid
    edgeNodeName        = $edge1NodeName
    edgeTep1IP          = $edge1Tep1IP
    edgeTep2IP          = $edge1Tep2IP
    edgeTepGateway      = $edgeTepGateway
    edgeTepVlan         = $edgeTepVlan
    interRackCluster     = $false
    managementGateway    = $managementGateway
    managementIP        = $edgeNode1managementIP
    uplinkNetwork       = @($uplinkNetworkEdge1_1, $uplinkNetworkEdge1_2)
}

$edgeNode2 = @{
    clusterId           = $sddcClusterid
    edgeNodeName        = $edge2NodeName
    edgeTep1IP          = $edge2Tep1IP
    edgeTep2IP          = $edge2Tep2IP
    edgeTepGateway      = $edgeTepGateway
    edgeTepVlan         = $edgeTepVlan
    interRackCluster     = $false
    managementGateway    = $managementGateway
    managementIP        = $edgeNode2managementIP
    uplinkNetwork       = @($uplinkNetworkEdge2_1, $uplinkNetworkEdge2_2)
}

# Building the final ordered JSON structure
logger "Creating Edge Cluster Configuration"

$edgeClusterObject = [ordered]@{
    asn                           = $asn
    edgeAdminPassword            = $masterPassword
    edgeAuditPassword            = $masterPassword
    edgeRootPassword             = $masterPassword
    mtu                           = 8000
    tier0Name                    = $tier0Name
    tier0RoutingType             = $routingType
    tier0ServicesHighAvailability= $tier0ServiceHA
    tier1Name                    = $tier1Name
    edgeClusterName              = $ecName
    edgeClusterProfileType       = $edgeClusterProfileType
    edgeClusterType              = $edgeClusterType
    edgeFormFactor               = $formFactor
    edgeNodeSpecs                = @($edgeNode1, $edgeNode2)
}

# Convert the final ordered hashtable to JSON
logger "Converting system objects to JSON"

$($edgeClusterObject | ConvertTo-JSON -Depth 10) | Out-File "$($jsonPathDir.FullName)\MGMT_Edge_Cluster.json"

# Validate the Edge Cluster Configuration, and Deploy the Edge Cluster
logger "Validating Edge Cluster Configuration"
New-VCFEdgeCluster -json "$($jsonPathDir.FullName)\MGMT_Edge_Cluster.json" -validate -ErrorVariable validation_err -ErrorAction SilentlyContinue | Out-Null
if($validation_err)
{
	logger "Validation failed with below error /n $($validation_err.Exception.Message)"
}
else 
{
	logger "Validation successful, deploying Edge Cluster"
	$edgeDeploy = New-VCFEdgeCluster -json "$($jsonPathDir.FullName)\MGMT_Edge_Cluster.json"
	do { $taskStatus = Get-VCFTask -id $($edgeDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
}
