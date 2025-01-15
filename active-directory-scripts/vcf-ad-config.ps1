###################################################################################################################
###  This script creates the active directory groups and users used by VCF to secure and manage various components.
###  It uses three CSV files, which can be modified for the customers needs and naming conventions.                                  
###################################################################################################################

Import-Module -Name ActiveDirectory

# This function will replicate any AD changes to other DCs in the forest.  This should be done if you are using a parent / child setup for VCF, or if you have multiple DCs in a given domain
function Replicate-AllDomainController {
    (Get-ADDomainController -Filter *).Name | Foreach-Object {repadmin /syncall $_ (Get-ADDomain).DistinguishedName /e /Av| Out-Null}; Start-Sleep 10; Get-ADReplicationPartnerMetadata -Target "$env:userdnsdomain" -Scope Domain | Select-Object Server, LastReplicationSuccess
    }

# Environment Variables
$dc = "vcfad.vcf.holo.lab" # Change this to match the name of the Active Directory domain controller + forest name you created earlier
$domain = "DC=vcf,DC=holo,DC=lab" # Change this to match the active directory domain name you deployed earlier
$dnsName = "@vcf.holo.lab"
$sgOuName = "Security Groups" # This OU name is VMware best practice.  Ut should remain unchanged unless customer insists
$suOuName = "Security Users" # This OU name is VMware best practice.  Ut should remain unchanged unless customer insists
$newGroupPath = "OU=" + $sgOuName + "," + $domain # This variable will create your group path for AD
$newUserPath = "OU=" + $suOuName + "," + $domain # This variable will create your user path for AD
$website = "www.holo.lab" # Specify a website entry for each user you create

$vcfGroups = Get-Content .\vcf-global-groups.csv
$vcfGroups = $vcfGroups -replace "OUPath",$newGroupPath
$vcfGroups = $vcfGroups -replace "dcfqdn",$dc
$vcfGroups | Out-File gg-deploy.csv

$vcfUsers = Get-Content .\vcf-users.csv
$vcfUsers = $vcfUsers -replace "OUPath",$newUserPath
$vcfUsers = $vcfUsers -replace "dcfqdn",$dc
$vcfGroups = $vcfGroups -replace "weburl",$website
$vcfUsers | Out-File users-deploy.csv

Start-Sleep 2

# Create The OUs to hold the Security Groups and Users as per VMware best practice.
New-ADOrganizationalUnit -Name $sgOuName -Path $domain -Server $dc
New-ADOrganizationalUnit -Name $suOuName -Path $domain -Server $dc

# Create Active Directory Global Groups.
Import-Csv "./gg-deploy.csv" | ForEach-Object {
    New-ADGroup `
    -Name $_."name" `
    -DisplayName  $_."displayname" `
    -Path  $_."path" `
    -GroupScope $_."scope" `
    -GroupCategory $_."type"`
    -Server $_."server"
     }

Start-Sleep 2

Replicate-AllDomainController

Start-Sleep 5

# This array provides the list of Group Names that the IF statement can parse in order to add usera to their mtching groups as specified in the users-deploy.csv
$array = "gg-vcf-admins","gg-vcf-operators","gg-vcf-viewers","gg-vc-admins","gg-vc-reaad-only","gg-sso-admins","gg-nsx-enterprise-admins","gg-nsx-network-admins","gg-nsx-auditors","gg-wsa-admins",`
"gg-wsa-directory-ad mins","gg-wsa-read-only","gg-vrslcm-admins","gg-vrslcm-content-admins","gg-vrslcm-content-developers","gg-vrops-admins","gg-vrops-content-admins",`
"gg-vrops-read-only","gg-vrli-admins","gg-vrli-users","gg-vrli-viewers","gg-vra-org-owners","gg-vra-cloud-assembly-admins","gg-vra-cloud-assembly-users","gg-vra-clpoud-assembly-viewers",`
"gg-vra-service-broker-admins","gg-vra-service-broker-users","gg-vra-service-broker-viewers","gg-vra-orchestrator-admins","gg-vra-orchestrator-designers","gg-vra-orchestrator-viewers",`
"gg-vra-project-admins-sample","gg-vra-project-users-sample","gg-kub-admins","gg-kub-readonly","gg-vra-codestream-admins","gg-vra-codestream-developers","gg-vra-codestream-executors",`
"gg-vra-codestream-users","gg-vra-codestream-viewers","gg-vra-saltstack-admins","gg-vra-saltstack-superusers","gg-vra-saltstack-users"

# Create Active Directory users and add them to the appropriate Global Groups.  This includes specifying an email address for each user as required for the default restriction settings in WSA
Import-Csv ".\users-deploy.csv" | ForEach-Object {
    $upn = $_."samAccountName" + $dnsName
    $setpass = ConvertTo-SecureString -AsPlainText $_."password" -force
    New-ADUser `
    -Name $_."user" `
    -Path  $_."path" `
    -SamAccountName  $_."samaccountname" `
    -DisplayName $_."Displayname" `
    -Givenname $_."name" `
    -Surname $_."surname" `
    -UserPrincipalName  $upn `
    -EmailAddress $upn `
    -AccountPassword $setpass `
    -ChangePasswordAtLogon $false  `
    -Enabled $true `
    -HomePage $_."website" `
    -Description $_."description"`
    -Server $_."server"

     IF ($_.group -in $array) {
         Add-ADGroupMember -Identity $_."group" -Server $_."server" -Members $_."samaccountname";
        }
}
