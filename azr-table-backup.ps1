Import-Module Az.Accounts
Import-Module Az.Automation
Import-Module Az.Storage
Import-Module AzTable

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName       
    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$sourceRg = "add source recource group name"
$sourceAccount = "add source storage account name"
$sourceTable = "add source table name"
$targetRg = "add source recource group name"
$targetAccount = "add source storage account name"
$targetContainer = "add target blob container name"
$backupname = "add backup file prefix"

$storagekey = (Get-AzStorageAccountKey -ResourceGroupName $sourceRg -AccountName $sourceAccount) | Where-Object {$_.KeyName -eq "key1"}
$storageaccountkey = $storagekey.Value

$ctx = New-AzStorageContext -StorageAccountName $sourceAccount -StorageAccountKey $storageaccountkey

$cloudTable = (Get-AzStorageTable –Name $sourceTable –Context $ctx).CloudTable

$rows = Get-AzTableRowAll -table $cloudTable

$todayDate = Get-Date -Format "yyyy-MM-dd"

$fileName = $backupname + "." + $todayDate + ".csv"

#Define all table fields you would like to include into backup
#2 mandatory fields (PartitionKey and RowKey) added and one as example
$export = $rows | ForEach-Object {
    [PSCustomObject]@{
        "PartitionKey" = $_.PartitionKey
        "RowKey" = $_.RowKey
        "RequestId" = $_.RequestId
    }
}

$filePath = "C:\Temp\" + $fileName

$export | export-csv $filePath -delimiter ";" -Encoding UTF8 -force -notypeinformation

$targetstoragekey = (Get-AzStorageAccountKey -ResourceGroupName $targetRg -AccountName $targetAccount) | Where-Object {$_.KeyName -eq "key1"}

$targetstorageaccountkey = $targetstoragekey.Value

$targetstoragectx = New-AzStorageContext -StorageAccountName $targetAccount -StorageAccountKey $targetstorageaccountkey

Set-AzStorageBlobContent -File $filePath -Container $targetContainer -Blob $fileName -Context $targetstoragectx
