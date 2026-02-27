<#
.SYNOPSIS
    Retrieve and display information about an existing Azure Cosmos DB resource

.DESCRIPTION
    This script retrieves comprehensive information about an existing Cosmos DB resource including:
    - Account details (endpoint, keys, location)
    - Databases and containers
    - Configuration settings
    - Connection information

.PARAMETER ResourceGroupName
    The name of the resource group containing the Cosmos DB account (required)

.PARAMETER CosmosAccountName
    The name of the Cosmos DB account (required)

.EXAMPLE
    .\Get-CosmosDBInfo.ps1 -ResourceGroupName "azureaiworkshoprg" -CosmosAccountName "cosmosaivector-12345"

.EXAMPLE
    .\Get-CosmosDBInfo.ps1 -ResourceGroupName "myResourceGroup" -CosmosAccountName "myCosmosAccount"

.NOTES
    Prerequisites: 
    - Azure CLI must be installed
    - User must be logged in to Azure CLI
    - Appropriate permissions to read Cosmos DB resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$CosmosAccountName
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

# Get Cosmos DB account information
function Get-CosmosDBInformation {
    param(
        [string]$CosmosAccountName,
        [string]$ResourceGroupName
    )
    
    Write-Header "Retrieving Cosmos DB Account Information"
    
    Write-Info "Getting Cosmos DB account details for: $CosmosAccountName"
    
    try {
        # Get account details
        $cosmosAccount = az cosmosdb show `
            --name $CosmosAccountName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        if (-not $cosmosAccount) {
            Write-Error "Cosmos DB account '$CosmosAccountName' not found in resource group '$ResourceGroupName'"
            return $null
        }
        
        Write-Success "Account details retrieved"
        
        # Get account keys
        Write-Info "Retrieving account keys..."
        $cosmosKeys = az cosmosdb keys list `
            --name $CosmosAccountName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        Write-Success "Account keys retrieved"
        
        # Get list of databases
        Write-Info "Retrieving databases..."
        $databases = az cosmosdb sql database list `
            --account-name $CosmosAccountName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        if ($databases) {
            Write-Success "Found $($databases.Count) database(s)"
        }
        
        # Get containers for each database
        $databaseDetails = @()
        foreach ($db in $databases) {
            Write-Info "Retrieving containers for database: $($db.name)"
            $containers = az cosmosdb sql container list `
                --account-name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --database-name $db.name `
                --output json 2>$null | ConvertFrom-Json
            
            $databaseDetails += @{
                Name = $db.name
                Containers = $containers
            }
        }
        
        Write-Success "Cosmos DB information retrieved successfully"
        
        return @{
            AccountName = $CosmosAccountName
            Endpoint = $cosmosAccount.documentEndpoint
            PrimaryKey = $cosmosKeys.primaryMasterKey
            SecondaryKey = $cosmosKeys.secondaryMasterKey
            ResourceGroup = $ResourceGroupName
            Location = $cosmosAccount.location
            Kind = $cosmosAccount.kind
            ConsistencyLevel = $cosmosAccount.consistencyPolicy.defaultConsistencyLevel
            Capabilities = $cosmosAccount.capabilities
            AutomaticFailover = $cosmosAccount.enableAutomaticFailover
            MultipleWriteLocations = $cosmosAccount.enableMultipleWriteLocations
            Databases = $databaseDetails
        }
    }
    catch {
        Write-Error "Failed to retrieve Cosmos DB information: $_"
        return $null
    }
}

# Display Cosmos DB information
function Show-CosmosDBInformation {
    param(
        [hashtable]$CosmosInfo
    )
    
    Write-Header "Cosmos DB Information Summary"
    
    if (-not $CosmosInfo) {
        Write-Error "No information to display"
        return
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Account Details" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Account Name:        " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.AccountName -ForegroundColor White
    
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.ResourceGroup -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.Location -ForegroundColor White
    
    Write-Host "Kind:                " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.Kind -ForegroundColor White
    
    Write-Host "Consistency Level:   " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.ConsistencyLevel -ForegroundColor White
    
    Write-Host "Automatic Failover:  " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.AutomaticFailover -ForegroundColor White
    
    Write-Host "Multi-Write:         " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.MultipleWriteLocations -ForegroundColor White
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Capabilities" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    if ($CosmosInfo.Capabilities -and $CosmosInfo.Capabilities.Count -gt 0) {
        foreach ($capability in $CosmosInfo.Capabilities) {
            Write-Host "  → $($capability.name)" -ForegroundColor White
        }
    }
    else {
        Write-Host "  No special capabilities enabled" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Connection Information" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Endpoint:            " -NoNewline -ForegroundColor Gray
    Write-Host $CosmosInfo.Endpoint -ForegroundColor White
    
    if ($CosmosInfo.PrimaryKey) {
        Write-Host "Primary Key:         " -NoNewline -ForegroundColor Gray
        Write-Host "$($CosmosInfo.PrimaryKey.Substring(0, 20))..." -ForegroundColor White
    }
    
    if ($CosmosInfo.SecondaryKey) {
        Write-Host "Secondary Key:       " -NoNewline -ForegroundColor Gray
        Write-Host "$($CosmosInfo.SecondaryKey.Substring(0, 20))..." -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Databases and Containers" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    if ($CosmosInfo.Databases -and $CosmosInfo.Databases.Count -gt 0) {
        foreach ($db in $CosmosInfo.Databases) {
            Write-Host "Database: " -NoNewline -ForegroundColor Cyan
            Write-Host $db.Name -ForegroundColor White
            
            if ($db.Containers -and $db.Containers.Count -gt 0) {
                foreach ($container in $db.Containers) {
                    Write-Host "  └─ Container: " -NoNewline -ForegroundColor Gray
                    Write-Host $container.name -ForegroundColor White
                    
                    if ($container.resource.partitionKey) {
                        Write-Host "     Partition Key: " -NoNewline -ForegroundColor Gray
                        Write-Host "$($container.resource.partitionKey.paths -join ', ')" -ForegroundColor White
                    }
                    
                    if ($container.options -and $container.options.throughput) {
                        Write-Host "     Throughput: " -NoNewline -ForegroundColor Gray
                        Write-Host "$($container.options.throughput) RU/s" -ForegroundColor White
                    }
                }
            }
            else {
                Write-Host "  └─ No containers found" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
    else {
        Write-Host "No databases found" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Connection String Examples" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Python:" -ForegroundColor Cyan
    Write-Host "  from azure.cosmos import CosmosClient" -ForegroundColor White
    Write-Host "  client = CosmosClient('$($CosmosInfo.Endpoint)', '$($CosmosInfo.PrimaryKey)')" -ForegroundColor White
    Write-Host ""
    
    Write-Host "C#:" -ForegroundColor Cyan
    Write-Host "  var client = new CosmosClient(" -ForegroundColor White
    Write-Host "      `"$($CosmosInfo.Endpoint)`"," -ForegroundColor White
    Write-Host "      `"$($CosmosInfo.PrimaryKey)`");" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Connection String:" -ForegroundColor Cyan
    Write-Host "  AccountEndpoint=$($CosmosInfo.Endpoint);AccountKey=$($CosmosInfo.PrimaryKey);" -ForegroundColor White
    Write-Host ""
    
    Write-Success "Information displayed successfully!"
    Write-Host ""
}

# Export information to file
function Export-CosmosDBInfo {
    param(
        [hashtable]$CosmosInfo,
        [string]$OutputPath = ".\cosmos-info.json"
    )
    
    Write-Header "Exporting Information"
    
    try {
        $CosmosInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Success "Information exported to: $OutputPath"
    }
    catch {
        Write-Warning "Could not export information: $_"
    }
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║          Azure Cosmos DB Information Script                    ║" -ForegroundColor Blue
        Write-Host "║          Retrieve and Display Resource Information            ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Get Cosmos DB information
        $cosmosInfo = Get-CosmosDBInformation -CosmosAccountName $CosmosAccountName -ResourceGroupName $ResourceGroupName
        
        if (-not $cosmosInfo) {
            Write-Error "Could not retrieve Cosmos DB information"
            exit 1
        }
        
        # Display information
        Show-CosmosDBInformation -CosmosInfo $cosmosInfo
        
        # Ask if user wants to export
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Info "Would you like to export this information to a JSON file? (Y/N)"
        $response = Read-Host
        
        if ($response -eq 'Y' -or $response -eq 'y') {
            $outputPath = Read-Host "Enter output path (default: .\cosmos-info.json)"
            if ([string]::IsNullOrWhiteSpace($outputPath)) {
                $outputPath = ".\cosmos-info.json"
            }
            Export-CosmosDBInfo -CosmosInfo $cosmosInfo -OutputPath $outputPath
        }
        
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  Complete!" -ForegroundColor Green
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
