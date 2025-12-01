param(
    [Parameter(Position=0)]
    [string]$storageAccount,
    
    [Parameter(Position=1)]
    [string]$fileSystem,
    
    [Parameter(Position=2)]
    [string]$keyvaultName,
    
    [Parameter(Position=3)]
    [string]$cosmosDbAccountName,
    
    [Parameter(Position=4)]
    [string]$resourceGroupName,
    
    [Parameter(Position=5)]
    [string]$aiSearchName,
    
    [Parameter(Position=6)]
    [string]$managedIdentityClientId,
    
    [Parameter(Position=7)]
    [string]$aif_resource_id
)

# Global variables to track original network access states
$global:original_storage_public_access = ""
$global:original_keyvault_public_access = ""
$global:original_foundry_public_access = ""
$global:aif_resource_group = ""
$global:aif_account_resource_id = ""
$global:aif_subscription_id = ""

# Function to enable public network access temporarily
function Enable-PublicAccess {
    Write-Host "=== Temporarily enabling public network access for services ===" -ForegroundColor Yellow
    
    try {
        # Enable public access for Storage Account
        $global:original_storage_public_access = az storage account show --name $storageAccount --resource-group $resourceGroupName --query "publicNetworkAccess" -o tsv
        
        if ($global:original_storage_public_access -ne "Enabled") {
            Write-Host "Enabling public access for Storage Account: $storageAccount" -ForegroundColor Cyan
            az storage account update --name $storageAccount --resource-group $resourceGroupName --public-network-access Enabled --default-action Allow --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Storage Account public access enabled" -ForegroundColor Green
            } else {
                Write-Host "✗ Failed to enable Storage Account public access" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✓ Storage Account public access already enabled" -ForegroundColor Green
        }

        # Enable public access for AI Foundry
        $global:aif_account_resource_id = $aif_resource_id -replace '/projects/.*', ''
        $global:aif_resource_group = if ($global:aif_account_resource_id -match '.*/resourceGroups/([^/]*)/.*') { $matches[1] } else { "" }
        $global:aif_subscription_id = if ($global:aif_account_resource_id -match '.*/subscriptions/([^/]*)/.*') { $matches[1] } else { "" }

        $env:MSYS_NO_PATHCONV = "1"
        $global:original_foundry_public_access = az resource show --ids $global:aif_account_resource_id --subscription $global:aif_subscription_id --api-version 2024-10-01 --query "properties.publicNetworkAccess" --output tsv
        
        if ([string]::IsNullOrEmpty($global:original_foundry_public_access) -or $global:original_foundry_public_access -eq "null") {
            Write-Host "⚠ Info: Could not retrieve AI Foundry network access status." -ForegroundColor Yellow
            Write-Host "  AI Foundry network access might be managed differently." -ForegroundColor Yellow
        } elseif ($global:original_foundry_public_access -ne "Enabled") {
            Write-Host "Enabling public access for AI Foundry: $global:aif_resource_group" -ForegroundColor Cyan
            az resource update --ids $global:aif_account_resource_id --api-version 2024-10-01 --subscription $global:aif_subscription_id --set properties.publicNetworkAccess=Enabled --set properties.apiProperties.qnaAzureSearchEndpointKey="" --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ AI Foundry public access enabled" -ForegroundColor Green
            } else {
                Write-Host "⚠ Warning: Failed to enable AI Foundry public access automatically." -ForegroundColor Yellow
            }
        } else {
            Write-Host "✓ AI Foundry public access already enabled" -ForegroundColor Green
        }
        
        # Enable public access for Key Vault
        $global:original_keyvault_public_access = az keyvault show --name $keyvaultName --resource-group $resourceGroupName --query "properties.publicNetworkAccess" -o tsv
        
        if ($global:original_keyvault_public_access -ne "Enabled") {
            Write-Host "Enabling public access for Key Vault: $keyvaultName" -ForegroundColor Cyan
            az keyvault update --name $keyvaultName --resource-group $resourceGroupName --public-network-access Enabled --default-action Allow --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ Key Vault public access enabled" -ForegroundColor Green
            } else {
                Write-Host "✗ Failed to enable Key Vault public access" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "✓ Key Vault public access already enabled" -ForegroundColor Green
        }
        
        # Additional wait for all changes to propagate fully
        Write-Host "Allowing additional time for all network access changes to propagate..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30
        Write-Host "=== Public network access configuration completed ===" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Host "Error enabling public access: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to restore original network access settings
function Restore-NetworkAccess {
    Write-Host "=== Restoring original network access settings ===" -ForegroundColor Yellow
    
    # Restore Storage Account access
    if (-not [string]::IsNullOrEmpty($global:original_storage_public_access) -and $global:original_storage_public_access -ne "Enabled") {
        Write-Host "Restoring Storage Account public access to: $global:original_storage_public_access" -ForegroundColor Cyan
        $restore_value = switch ($global:original_storage_public_access.ToLower()) {
            "enabled" { "Enabled" }
            "disabled" { "Disabled" }
            default { $global:original_storage_public_access }
        }
        az storage account update --name $storageAccount --resource-group $resourceGroupName --public-network-access $restore_value --default-action Deny --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Storage Account access restored" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to restore Storage Account access" -ForegroundColor Red
        }
    } else {
        Write-Host "Storage Account access unchanged (already at desired state)" -ForegroundColor Gray
    }
    
    # Restore Key Vault access
    if (-not [string]::IsNullOrEmpty($global:original_keyvault_public_access) -and $global:original_keyvault_public_access -ne "Enabled") {
        Write-Host "Restoring Key Vault public access to: $global:original_keyvault_public_access" -ForegroundColor Cyan
        $restore_value = switch ($global:original_keyvault_public_access.ToLower()) {
            "enabled" { "Enabled" }
            "disabled" { "Disabled" }
            default { $global:original_keyvault_public_access }
        }
        az keyvault update --name $keyvaultName --resource-group $resourceGroupName --public-network-access $restore_value --default-action Deny --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Key Vault access restored" -ForegroundColor Green
        } else {
            Write-Host "✗ Failed to restore Key Vault access" -ForegroundColor Red
        }
    } else {
        Write-Host "Key Vault access unchanged (already at desired state)" -ForegroundColor Gray
    }

    # Restore AI Foundry access
    if (-not [string]::IsNullOrEmpty($global:original_foundry_public_access) -and $global:original_foundry_public_access -ne "Enabled") {
        Write-Host "Restoring AI Foundry public access to: $global:original_foundry_public_access" -ForegroundColor Cyan
        $env:MSYS_NO_PATHCONV = "1"
        az resource update --ids $global:aif_account_resource_id --api-version 2024-10-01 --subscription $global:aif_subscription_id --set properties.publicNetworkAccess="$global:original_foundry_public_access" --set properties.apiProperties.qnaAzureSearchEndpointKey="" --set properties.networkAcls.bypass="AzureServices" --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ AI Foundry access restored" -ForegroundColor Green
        } else {
            Write-Host "⚠ Warning: Failed to restore AI Foundry access automatically." -ForegroundColor Yellow
            Write-Host "  Please manually restore network access in the Azure portal if needed." -ForegroundColor Yellow
        }
    } else {
        Write-Host "AI Foundry access unchanged (already at desired state)" -ForegroundColor Gray
    }
    
    Write-Host "=== Network access restoration completed ===" -ForegroundColor Yellow
}

# Function to handle script cleanup on exit
function Cleanup-OnExit {
    param([int]$ExitCode = 0)
    
    Write-Host ""
    if ($ExitCode -ne 0) {
        Write-Host "Script failed with exit code: $ExitCode" -ForegroundColor Red
    }
    Write-Host "Performing cleanup..." -ForegroundColor Cyan
    Restore-NetworkAccess
    exit $ExitCode
}

# Set up error handling and cleanup
$ErrorActionPreference = "Stop"
trap {
    Cleanup-OnExit -ExitCode 1
}

try {
    # Get parameters from azd env, if not provided
    if ([string]::IsNullOrEmpty($resourceGroupName)) {
        $resourceGroupName = azd env get-value RESOURCE_GROUP_NAME
    }

    if ([string]::IsNullOrEmpty($cosmosDbAccountName)) {
        $cosmosDbAccountName = azd env get-value COSMOSDB_ACCOUNT_NAME
    }

    if ([string]::IsNullOrEmpty($storageAccount)) {
        $storageAccount = azd env get-value STORAGE_ACCOUNT_NAME
    }

    if ([string]::IsNullOrEmpty($fileSystem)) {
        $fileSystem = azd env get-value STORAGE_CONTAINER_NAME
    }

    if ([string]::IsNullOrEmpty($keyvaultName)) {
        $keyvaultName = azd env get-value KEY_VAULT_NAME
    }

    if ([string]::IsNullOrEmpty($aiSearchName)) {
        $aiSearchName = azd env get-value AI_SEARCH_SERVICE_NAME
    }

    if ([string]::IsNullOrEmpty($aif_resource_id)) {
        $aif_resource_id = azd env get-value AI_FOUNDRY_RESOURCE_ID
    }

    # Get subscription id from azd env or from environment variable
    try {
        $azSubscriptionId = azd env get-value AZURE_SUBSCRIPTION_ID
    } catch {
        $azSubscriptionId = $env:AZURE_SUBSCRIPTION_ID
    }

    # Check if all required arguments are provided
    if ([string]::IsNullOrEmpty($storageAccount) -or [string]::IsNullOrEmpty($fileSystem) -or [string]::IsNullOrEmpty($keyvaultName) -or [string]::IsNullOrEmpty($cosmosDbAccountName) -or [string]::IsNullOrEmpty($resourceGroupName) -or [string]::IsNullOrEmpty($aif_resource_id) -or [string]::IsNullOrEmpty($aiSearchName)) {
        Write-Host "Usage: .\process_sample_data.ps1 <storageAccount> <storageContainerName> <keyvaultName> <cosmosDbAccountName> <resourceGroupName> <aiSearchName> <managedIdentityClientId> <aif_resource_id>" -ForegroundColor Red
        exit 1
    }

    # Authenticate with Azure
    $accountInfo = az account show 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Already authenticated with Azure." -ForegroundColor Green
    } else {
        if (-not [string]::IsNullOrEmpty($managedIdentityClientId)) {
            # Use managed identity if running in Azure
            Write-Host "Authenticating with Managed Identity..." -ForegroundColor Cyan
            az login --identity --client-id $managedIdentityClientId
        } else {
            # Use Azure CLI login if running locally
            Write-Host "Authenticating with Azure CLI..." -ForegroundColor Cyan
            az login --use-device-code
        }
        Write-Host "Authentication completed." -ForegroundColor Green
    }

    # Check if user has selected the correct subscription
    $currentSubscriptionId = az account show --query id -o tsv
    $currentSubscriptionName = az account show --query name -o tsv

    if ($currentSubscriptionId -ne $azSubscriptionId) {
        Write-Host "Current selected subscription is $currentSubscriptionName ( $currentSubscriptionId )." -ForegroundColor Yellow
        $confirmation = Read-Host "Do you want to continue with this subscription?(y/n)"
        if ($confirmation -notmatch '^[yY]$') {
            Write-Host "Fetching available subscriptions..." -ForegroundColor Cyan
            $availableSubscriptions = az account list --query "[?state=='Enabled'].[name,id]" --output tsv
            $subscriptionList = $availableSubscriptions -split "`n" | ForEach-Object { $_ -split "`t" }
            
            do {
                Write-Host ""
                Write-Host "Available Subscriptions:" -ForegroundColor Yellow
                Write-Host "========================" -ForegroundColor Yellow
                for ($i = 0; $i -lt $subscriptionList.Count; $i += 2) {
                    $index = ($i / 2) + 1
                    Write-Host "$index. $($subscriptionList[$i]) ( $($subscriptionList[$i + 1]) )"
                }
                Write-Host "========================" -ForegroundColor Yellow
                Write-Host ""
                
                $subscriptionIndex = Read-Host "Enter the number of the subscription (1-$($subscriptionList.Count / 2)) to use"
                $indexInt = [int]$subscriptionIndex
                
                if ($indexInt -ge 1 -and $indexInt -le ($subscriptionList.Count / 2)) {
                    $selectedIndex = ($indexInt - 1) * 2
                    $selectedSubscriptionName = $subscriptionList[$selectedIndex]
                    $selectedSubscriptionId = $subscriptionList[$selectedIndex + 1]

                    # Set the selected subscription
                    az account set --subscription $selectedSubscriptionId
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Switched to subscription: $selectedSubscriptionName ( $selectedSubscriptionId )" -ForegroundColor Green
                        break
                    } else {
                        Write-Host "Failed to switch to subscription: $selectedSubscriptionName ( $selectedSubscriptionId )." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Invalid selection. Please try again." -ForegroundColor Red
                }
            } while ($true)
        } else {
            Write-Host "Proceeding with the current subscription: $currentSubscriptionName ( $currentSubscriptionId )" -ForegroundColor Green
            az account set --subscription $currentSubscriptionId
        }
    } else {
        Write-Host "Proceeding with the subscription: $currentSubscriptionName ( $currentSubscriptionId )" -ForegroundColor Green
        az account set --subscription $currentSubscriptionId
    }

    # Enable public network access for required services
    if (-not (Enable-PublicAccess)) {
        Write-Host "Error: Failed to enable public network access for services." -ForegroundColor Red
        exit 1
    }

    # Call add_cosmosdb_access.sh (PowerShell equivalent)
    Write-Host "Running add_cosmosdb_access script" -ForegroundColor Cyan
    & ".\infra\scripts\add_cosmosdb_access.ps1" $resourceGroupName $cosmosDbAccountName $managedIdentityClientId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: add_cosmosdb_access script failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "add_cosmosdb_access script completed successfully." -ForegroundColor Green

    # Call copy_kb_files.sh (PowerShell equivalent)
    Write-Host "Running copy_kb_files script" -ForegroundColor Cyan
    & ".\infra\scripts\copy_kb_files.ps1" $storageAccount $fileSystem $managedIdentityClientId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: copy_kb_files script failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "copy_kb_files script completed successfully." -ForegroundColor Green

    # Call run_create_index_scripts.sh (PowerShell equivalent)
    Write-Host "Running run_create_index_scripts script" -ForegroundColor Cyan
    & ".\infra\scripts\run_create_index_scripts.ps1" $keyvaultName $resourceGroupName $aiSearchName $managedIdentityClientId $aif_resource_id
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: run_create_index_scripts script failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "run_create_index_scripts script completed successfully." -ForegroundColor Green

    Write-Host "All scripts executed successfully." -ForegroundColor Green
}
catch {
    Write-Host "An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup-OnExit -ExitCode 1
}
finally {
    # Note: cleanup will be called automatically via the trap or explicit call
    Cleanup-OnExit -ExitCode 0
}