<#
.SYNOPSIS
    Deploy Azure Cosmos DB with NoSQL Vector Search capability

.DESCRIPTION
    This script automates the deployment of:
    - Azure Cosmos DB account with NoSQL API and Vector Search capability
    - Database creation
    - Container creation with partition key and throughput configuration

.PARAMETER ResourceGroupName
    The name of the resource group to use (required)

.PARAMETER CosmosAccountName
    The name of the Cosmos DB account to create (required)

.PARAMETER Location
    The Azure region for deployment (default: eastus2)

.PARAMETER DatabaseName
    The name of the database to create (default: RetailDB)

.PARAMETER ContainerName
    The name of the container to create (default: Products)

.PARAMETER PartitionKeyPath
    The partition key path for the container (default: /id)

.PARAMETER Throughput
    The throughput (RU/s) for the container (default: 400)

.EXAMPLE
    .\Deploy-CosmosDB.ps1 -ResourceGroupName "azureaiworkshoprg" -CosmosAccountName "cosmosaivector-12345"

.EXAMPLE
    .\Deploy-CosmosDB.ps1 -ResourceGroupName "myResourceGroup" -CosmosAccountName "myCosmosAccount" -DatabaseName "CustomDB" -ContainerName "Items"

.NOTES
    Prerequisites: 
    - Azure CLI must be installed
    - User must be logged in to Azure CLI
    - Appropriate permissions in the subscription
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$CosmosAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = "RetailDB",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerName = "Products",
    
    [Parameter(Mandatory=$false)]
    [string]$PartitionKeyPath = "/id",
    
    [Parameter(Mandatory=$false)]
    [int]$Throughput = 400
)

# Color output functions
function Write-Success { 
    Write-Host "✓ $args" -ForegroundColor Green 
}

function Write-Info { 
    Write-Host "→ $args" -ForegroundColor Cyan 
}

function Write-Warning { 
    Write-Host "⚠ $args" -ForegroundColor Yellow 
}

function Write-Error { 
    Write-Host "✗ $args" -ForegroundColor Red 
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "  $Message" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
}

# Check prerequisites
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    # Check if Azure CLI is installed
    Write-Info "Checking Azure CLI installation..."
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        Write-Success "Azure CLI is installed (version: $($azVersion.'azure-cli'))"
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install from: https://aka.ms/installazurecliwindows"
        exit 1
    }
    
    # Check if logged in to Azure
    Write-Info "Checking Azure login status..."
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        Write-Success "Logged in to Azure (Subscription: $($account.name))"
        return $account
    }
    catch {
        Write-Error "Not logged in to Azure. Running 'az login'..."
        az login
        $account = az account show | ConvertFrom-Json
        Write-Success "Successfully logged in"
        return $account
    }
}

# Verify Resource Group exists
function Test-ResourceGroup {
    Write-Header "Verifying Resource Group"
    
    Write-Info "Checking if resource group '$ResourceGroupName' exists..."
    $rgExists = az group exists --name $ResourceGroupName
    
    if ($rgExists -eq "true") {
        Write-Success "Resource group '$ResourceGroupName' exists"
        return $true
    }
    else {
        Write-Error "Resource group '$ResourceGroupName' does not exist"
        Write-Info "Please create the resource group first or specify an existing one"
        exit 1
    }
}

# Create Cosmos DB resource
function New-CosmosDBResource {
    Write-Header "Creating Cosmos DB Resource"
    
    Write-Info "Creating Cosmos DB account: $CosmosAccountName"
    Write-Info "Configuration: NoSQL API with Vector Search capability"
    Write-Info "Location: $Location"
    
    # Check if exists
    $existing = az cosmosdb show `
        --name $CosmosAccountName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existing) {
        Write-Warning "Cosmos DB account '$CosmosAccountName' already exists"
    }
    else {
        # Create Cosmos DB account with specifications matching Cosmos.json
        try {
            Write-Info "Creating Cosmos DB account (this may take 5-10 minutes)..."
            $cosmos = az cosmosdb create `
                --name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --locations regionName=$Location failoverPriority=0 isZoneRedundant=False `
                --kind GlobalDocumentDB `
                --default-consistency-level Session `
                --enable-automatic-failover true `
                --enable-multiple-write-locations false `
                --capabilities EnableNoSQLVectorSearch `
                --backup-policy-type Periodic `
                --backup-interval 240 `
                --backup-retention 8 `
                --output json 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create Cosmos DB account"
                Write-Info "Azure CLI Error: $cosmos"
                Write-Info "You may need to create this resource manually in the portal"
                exit 1
            }
            
            $cosmos = $cosmos | ConvertFrom-Json
            Write-Success "Cosmos DB account created successfully"
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Failed to create Cosmos DB account: $_"
            Write-Info "You may need to create this resource manually in the portal"
            exit 1
        }
    }
    
    # Create database
    Write-Info "Creating database: $DatabaseName"
    $dbExists = az cosmosdb sql database show `
        --account-name $CosmosAccountName `
        --resource-group $ResourceGroupName `
        --name $DatabaseName `
        2>$null
    
    if (-not $dbExists) {
        try {
            az cosmosdb sql database create `
                --account-name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --name $DatabaseName `
                --output none
            Write-Success "Database '$DatabaseName' created"
        }
        catch {
            Write-Warning "Could not create database: $_"
        }
    }
    else {
        Write-Warning "Database '$DatabaseName' already exists"
    }
    
    # Create container
    Write-Info "Creating container: $ContainerName"
    $containerExists = az cosmosdb sql container show `
        --account-name $CosmosAccountName `
        --resource-group $ResourceGroupName `
        --database-name $DatabaseName `
        --name $ContainerName `
        2>$null
    
    if (-not $containerExists) {
        try {
            az cosmosdb sql container create `
                --account-name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --database-name $DatabaseName `
                --name $ContainerName `
                --partition-key-path $PartitionKeyPath `
                --throughput $Throughput `
                --output none
            Write-Success "Container '$ContainerName' created"
        }
        catch {
            Write-Warning "Could not create container: $_"
        }
    }
    else {
        Write-Warning "Container '$ContainerName' already exists"
    }
    
    Write-Success "Cosmos DB setup completed"
    Write-Info "Database: $DatabaseName | Container: $ContainerName | Partition Key: $PartitionKeyPath"
    
    return @{
        AccountName = $CosmosAccountName
        DatabaseName = $DatabaseName
        ContainerName = $ContainerName
        PartitionKeyPath = $PartitionKeyPath
        Throughput = $Throughput
    }
}

# Get Cosmos DB information
function Get-CosmosDBInformation {
    param(
        [string]$CosmosAccountName
    )
    
    Write-Header "Collecting Cosmos DB Information"
    
    Write-Info "Getting Cosmos DB account details..."
    try {
        $cosmosAccount = az cosmosdb show `
            --name $CosmosAccountName `
            --resource-group $ResourceGroupName `
            --output json | ConvertFrom-Json
        
        $cosmosKeys = az cosmosdb keys list `
            --name $CosmosAccountName `
            --resource-group $ResourceGroupName `
            --output json | ConvertFrom-Json
        
        Write-Success "Cosmos DB information retrieved successfully"
        
        return @{
            AccountName = $CosmosAccountName
            Endpoint = $cosmosAccount.documentEndpoint
            PrimaryKey = $cosmosKeys.primaryMasterKey
            SecondaryKey = $cosmosKeys.secondaryMasterKey
            ResourceGroup = $ResourceGroupName
            Location = $cosmosAccount.location
        }
    }
    catch {
        Write-Warning "Could not retrieve Cosmos DB details: $_"
        return $null
    }
}

# Display deployment summary
function Show-DeploymentSummary {
    param(
        [hashtable]$DeploymentInfo,
        [hashtable]$CosmosInfo
    )
    
    Write-Header "Deployment Summary"
    
    Write-Host ""
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $ResourceGroupName -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $Location -ForegroundColor White
    
    Write-Host ""
    Write-Host "Cosmos DB Account:   " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.AccountName -ForegroundColor White
    
    if ($CosmosInfo) {
        Write-Host "Cosmos DB Endpoint:  " -NoNewline -ForegroundColor Gray
        Write-Host $CosmosInfo.Endpoint -ForegroundColor White
    }
    
    Write-Host "Database:            " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.DatabaseName -ForegroundColor White
    
    Write-Host "Container:           " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.ContainerName -ForegroundColor White
    
    Write-Host "Partition Key:       " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.PartitionKeyPath -ForegroundColor White
    
    Write-Host "Throughput:          " -NoNewline -ForegroundColor Gray
    Write-Host "$($DeploymentInfo.Throughput) RU/s" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Features Enabled:" -ForegroundColor Gray
    Write-Host "  → NoSQL API" -ForegroundColor White
    Write-Host "  → Vector Search Capability" -ForegroundColor White
    Write-Host "  → Automatic Failover" -ForegroundColor White
    Write-Host "  → Session Consistency Level" -ForegroundColor White
    Write-Host "  → Periodic Backup (240 min interval, 8 hr retention)" -ForegroundColor White
    
    if ($CosmosInfo -and $CosmosInfo.PrimaryKey) {
        Write-Host ""
        Write-Host "Connection Information:" -ForegroundColor Gray
        Write-Host "  Endpoint:    $($CosmosInfo.Endpoint)" -ForegroundColor White
        Write-Host "  Primary Key: $($CosmosInfo.PrimaryKey.Substring(0, 20))..." -ForegroundColor White
    }
    elseif (-not $CosmosInfo) {
        Write-Host ""
        Write-Warning "Could not retrieve connection information"
    }
    
    Write-Host ""
    Write-Success "Deployment completed successfully!"
    Write-Info "Next steps:"
    Write-Host "  1. Verify resources in Azure Portal: https://portal.azure.com" -ForegroundColor Cyan
    Write-Host "  2. Use the endpoint and key to connect your applications" -ForegroundColor Cyan
    Write-Host "  3. Configure vector search indexes for your containers" -ForegroundColor Cyan
    Write-Host ""
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║          Azure Cosmos DB Deployment Script                     ║" -ForegroundColor Blue
        Write-Host "║          NoSQL API with Vector Search Capability              ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Verify resource group
        Test-ResourceGroup
        
        # Create Cosmos DB resource
        $deploymentInfo = New-CosmosDBResource
        
        # Get Cosmos DB information
        $cosmosInfo = Get-CosmosDBInformation -CosmosAccountName $CosmosAccountName
        
        # Show summary
        Show-DeploymentSummary -DeploymentInfo $deploymentInfo -CosmosInfo $cosmosInfo
        
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  Cosmos DB Resource Created Successfully!" -ForegroundColor Green
        Write-Host "  Portal: https://portal.azure.com/#resource/subscriptions/$($accountInfo.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.DocumentDB/databaseAccounts/$CosmosAccountName" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        
    }
    catch {
        Write-Error "An error occurred: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        exit 1
    }
}

# Run the script
Main
