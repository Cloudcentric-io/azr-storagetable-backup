$targetrg = Read-Host -Prompt 'Please provide target resource group name'
$targetsa = Read-Host -Prompt 'Please provide target storage account name'
$targetlocation = Read-Host -Prompt 'Please provide target resource group location'
$backupaccount = Read-Host -Prompt 'Please provide automation account name'
$tablebackupblob = Read-Host -Prompt 'Please provide target storage account container name'
$subs_id  = Read-Host -Prompt 'Please provide target subscriptiond id'
$Password = Read-Host -Prompt 'Please provide self signed certificate password'

Write-Host "Connecting to Azure ..."

Connect-AzAccount 

Write-Host "Setting subscription context ..."

Set-AzContext -SubscriptionId $subs_id

# Create public and private keys 
Write-Host "Generating self signed certificate ..."
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -passout pass:$Password -nodes
#key.pem, cert.pem
Start-Sleep -s 5
openssl pkcs12 -inkey key.pem -in cert.pem -export -out cert.pfx -passin pass:$Password -passout pass:$Password
#pfx

# Creating service principall

$pfx_cert_raw = Get-Content "./cert.pem" -AsByteStream
$base64 = [System.Convert]::ToBase64String($pfx_cert_raw)
New-AzADServicePrincipal -DisplayName $backupaccount -CertValue $base64 -EndDate "2021-01-01"

$CertPassword = ConvertTo-SecureString $Password -AsPlainText -Force
$CertThumb = Get-PfxCertificate -FilePath "./cert.pfx" -Password $CertPassword | Select-Object Thumbprint

Write-Host "Starting deployment of resources ..."

# Azure Resource Manager templates deployment

New-AzSubscriptionDeployment `
-name Deployment `
-location $targetlocation `
-templatefile azuredeploy.json `
-targetrg $targetrg -targetsa $targetsa -targetlocation $targetlocation -backupaccount $backupaccount -tablebackupblob $tablebackupblob

Write-Host "Configuring automation account"

Import-Module Az.Automation
Enable-AzureRmAlias


# Create a Run As account by using a service principal
$CertifcateAssetName = "AzureRunAsCertificate"
$ConnectionAssetName = "AzureRunAsConnection"
$ConnectionTypeName = "AzureServicePrincipal"

# Create the Automation certificate asset

New-AzAutomationCertificate -AutomationAccountName $backupaccount -Name $CertifcateAssetName -Path "./cert.pfx" -Password $CertPassword -ResourceGroupName $targetrg
    
# Populate the ConnectionFieldValues
$SubscriptionInfo = Get-AzSubscription -SubscriptionId $subs_id
$TenantID = $SubscriptionInfo | Select-Object TenantId -First 1
$ApplicationId = Get-AzADServicePrincipal -DisplayName $backupaccount | Select-Object ApplicationId -First 1

$ConnectionFieldValues = @{"ApplicationId" = $ApplicationId; "TenantId" = $TenantID; "CertificateThumbprint" = $CertThumb; "SubscriptionId" = $subs_id}

# Create an Automation connection asset named AzureRunAsConnection in the Automation account. This connection uses the service principal.
New-AzAutomationConnection -ResourceGroupName $targetrg -AutomationAccountName $backupaccount -Name $ConnectionAssetName -ConnectionTypeName $ConnectionTypeName -ConnectionFieldValues $ConnectionFieldValues

Write-Host "Deployment complete"
Write-Host "Do not forget to save generated certificates key.pem and cert.pem"