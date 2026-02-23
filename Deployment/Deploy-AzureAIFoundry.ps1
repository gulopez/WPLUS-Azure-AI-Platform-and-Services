<#
.SYNOPSIS
    Deploy Azure AI Foundry with all required resources and configurations

.DESCRIPTION
    This script automates the deployment of:
    - Azure AI Foundry resource and project
    - AI models (gpt-4o, gpt-4o-mini, text-embedding-3-large, text-embedding-ada-002)
    - Bing Grounding resource
    - Azure AI Search resource
    - Cosmos DB with NoSQL Vector Search capability
    - SQL Server and Database with vector capabilities
    - PostgreSQL Flexible Server with vector extensions
    - Connections between resources
    - Updates .env file with all endpoints and keys

.PARAMETER ResourceGroupName
    The name of the resource group to use (default: azureaiworkshoprg)

.PARAMETER Location
    The Azure region for deployment (default: eastus2)

.PARAMETER LabInstanceId
    The lab instance ID (will be prompted if not provided)

.EXAMPLE
    .\Deploy-AzureAIFoundry.ps1 -LabInstanceId "53439517"

.NOTES
    Prerequisites: 
    - Azure CLI must be installed
    - User must be logged in to Azure CLI
    - Appropriate permissions in the subscription
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "azureaiworkshoprg",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$LabInstanceId
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

# Get or prompt for Lab Instance ID
function Get-LabInstanceId {
    if ([string]::IsNullOrWhiteSpace($script:LabInstanceId)) {
        Write-Info "Lab Instance ID is required for resource naming"
        $script:LabInstanceId = Read-Host "Enter your Lab Instance ID"
    }
    
    if ([string]::IsNullOrWhiteSpace($script:LabInstanceId)) {
        Write-Error "Lab Instance ID is required"
        exit 1
    }
    
    Write-Success "Using Lab Instance ID: $script:LabInstanceId"
}

# Create or verify Resource Group
function Initialize-ResourceGroup {
    Write-Header "Setting Up Resource Group"
    
    Write-Info "Checking if resource group '$ResourceGroupName' exists..."
    $rgExists = az group exists --name $ResourceGroupName
    
    if ($rgExists -eq "true") {
        Write-Success "Resource group '$ResourceGroupName' already exists"
    }
    else {
        Write-Info "Creating resource group '$ResourceGroupName' in location '$Location'..."
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Success "Resource group created successfully"
    }
}

# Create Azure AI Foundry resource
function New-AIFoundryResource {
    param(
        [string]$FoundryName,
        [string]$ProjectName = "firstProject"
    )
    
    Write-Header "Creating Azure AI Foundry Resource"
    
    Write-Info "Creating AI Foundry: $FoundryName"
    Write-Info "Project Name: $ProjectName"
    
    # Check if the resource already exists
    $existingFoundry = az cognitiveservices account show `
        --name $FoundryName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingFoundry) {
        Write-Warning "AI Foundry '$FoundryName' already exists"
        return $existingFoundry
    }
    
    # Create the AI Foundry resource (Hub)
    Write-Info "Creating AI Foundry hub..."
    $foundry = az ml workspace create `
        --kind hub `
        --resource-group $ResourceGroupName `
        --name $FoundryName `
        --location $Location `
        --output json | ConvertFrom-Json
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "AI Foundry hub created successfully"
    }
    else {
        Write-Warning "Using alternative method to create AI Foundry..."
        # Alternative: Create using cognitive services
        az cognitiveservices account create `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --kind AIServices `
            --sku S0 `
            --location $Location `
            --yes `
            --output none
    }
    
    # Create project under the hub
    Write-Info "Creating AI Foundry project: $ProjectName..."
    $project = az ml workspace create `
        --kind project `
        --resource-group $ResourceGroupName `
        --name $ProjectName `
        --hub-id "/subscriptions/$($script:AccountInfo.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/$FoundryName" `
        --location $Location `
        --output json 2>$null | ConvertFrom-Json
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "AI Foundry project created successfully"
    }
    else {
        Write-Warning "Project creation may need to be completed in portal"
    }
    
    Start-Sleep -Seconds 10
    
    return $foundry
}

# Deploy AI models
function Deploy-AIModels {
    param(
        [string]$FoundryName,
        [array]$Models
    )
    
    Write-Header "Deploying AI Models"
    
    $deployedModels = @()
    
    foreach ($model in $Models) {
        Write-Info "Deploying model: $($model.Name)"
        
        # Check if model already deployed
        $existing = az cognitiveservices account deployment show `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --deployment-name $model.DeploymentName `
            2>$null | ConvertFrom-Json
        
        if ($existing) {
            Write-Warning "Model '$($model.DeploymentName)' already deployed"
            $deployedModels += $existing
            continue
        }
        
        # Deploy the model
        try {
            $deployment = az cognitiveservices account deployment create `
                --name $FoundryName `
                --resource-group $ResourceGroupName `
                --deployment-name $model.DeploymentName `
                --model-name $model.ModelName `
                --model-version $model.Version `
                --model-format OpenAI `
                --sku-capacity $model.Capacity `
                --sku-name "Standard" `
                --output json | ConvertFrom-Json
            
            Write-Success "Model '$($model.DeploymentName)' deployed successfully"
            $deployedModels += $deployment
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Warning "Could not deploy model '$($model.DeploymentName)': $_"
            Write-Info "You may need to deploy this model manually in the portal"
        }
    }
    
    return $deployedModels
}

# Create Bing Grounding resource
function New-BingResource {
    param(
        [string]$BingName
    )
    
    Write-Header "Creating Bing Grounding Resource"
    
    Write-Info "Creating Bing resource: $BingName"
    
    # Check if exists
    $existing = az cognitiveservices account show `
        --name $BingName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existing) {
        Write-Warning "Bing resource '$BingName' already exists"
        return $existing
    }
    
    # Create Bing Search resource
    try {
        $bing = az cognitiveservices account create `
            --name $BingName `
            --resource-group $ResourceGroupName `
            --kind Bing.Search.v7 `
            --sku S1 `
            --location global `
            --yes `
            --output json | ConvertFrom-Json
        
        Write-Success "Bing resource created successfully"
        return $bing
    }
    catch {
        Write-Error "Failed to create Bing resource: $_"
        Write-Info "You may need to create this resource manually in the portal"
        return $null
    }
}

# Create Azure AI Search resource
function New-AISearchResource {
    param(
        [string]$SearchServiceName
    )
    
    Write-Header "Creating Azure AI Search Resource"
    
    Write-Info "Creating AI Search service: $SearchServiceName"
    Write-Info "Configuration: Basic SKU, 1 replica, 1 partition, Free semantic search"
    
    # Check if exists
    $existing = az search service show `
        --name $SearchServiceName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existing) {
        Write-Warning "AI Search service '$SearchServiceName' already exists"
        return $existing
    }
    
    # Create AI Search service with specifications matching AISearch.json
    try {
        $search = az search service create `
            --name $SearchServiceName `
            --resource-group $ResourceGroupName `
            --sku basic `
            --location $Location `
            --replica-count 1 `
            --partition-count 1 `
            --public-network-access Enabled `
            --disable-local-auth false `
            --semantic-search free `
            --output json | ConvertFrom-Json
        
        Write-Success "AI Search service created successfully"
        Write-Info "SKU: Basic | Replicas: 1 | Partitions: 1 | Semantic Search: Free"
        Start-Sleep -Seconds 10
        return $search
    }
    catch {
        Write-Error "Failed to create AI Search service: $_"
        Write-Info "You may need to create this resource manually in the portal"
        return $null
    }
}

# Create Cosmos DB resource
function New-CosmosDBResource {
    param(
        [string]$CosmosAccountName,
        [string]$DatabaseName = "RetailDB",
        [string]$ContainerName = "Products"
    )
    
    Write-Header "Creating Cosmos DB Resource"
    
    Write-Info "Creating Cosmos DB account: $CosmosAccountName"
    Write-Info "Configuration: NoSQL API with Vector Search capability"
    
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
                --location $Location `
                --kind GlobalDocumentDB `
                --default-consistency-level Session `
                --enable-automatic-failover true `
                --enable-multiple-write-locations false `
                --capabilities EnableNoSQLVectorSearch `
                --backup-policy-type Periodic `
                --backup-interval 240 `
                --backup-retention 8 `
                --output json | ConvertFrom-Json
            
            Write-Success "Cosmos DB account created successfully"
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Failed to create Cosmos DB account: $_"
            Write-Info "You may need to create this resource manually in the portal"
            return $null
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
                --partition-key-path "/id" `
                --throughput 400 `
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
    Write-Info "Database: $DatabaseName | Container: $ContainerName | Partition Key: /id"
    
    return @{
        AccountName = $CosmosAccountName
        DatabaseName = $DatabaseName
        ContainerName = $ContainerName
    }
}

# Generate secure password
function New-SecurePassword {
    param(
        [int]$Length = 16
    )
    
    # Generate a complex password that meets Azure SQL requirements
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghijkmnopqrstuvwxyz"
    $numbers = "23456789"
    $special = "!@#$%^&*()-_=+"
    
    $password = ""
    $password += $upper[(Get-Random -Maximum $upper.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $numbers[(Get-Random -Maximum $numbers.Length)]
    $password += $special[(Get-Random -Maximum $special.Length)]
    
    $allChars = $upper + $lower + $numbers + $special
    for ($i = 4; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle the password
    $passwordArray = $password.ToCharArray()
    $shuffled = $passwordArray | Get-Random -Count $passwordArray.Length
    return -join $shuffled
}

# Create SQL Server and Database
function New-SQLServerAndDatabase {
    param(
        [string]$ServerName,
        [string]$DatabaseName = "vectordb",
        [string]$AdminUser = "sqladmin"
    )
    
    Write-Header "Creating SQL Server and Database"
    
    Write-Info "Creating SQL Server: $ServerName"
    Write-Info "Configuration: GP_Gen5 (2 vCores), 32GB max size"
    
    # Generate secure password
    $adminPassword = New-SecurePassword -Length 16
    
    # Check if SQL Server exists
    $existingServer = az sql server show `
        --name $ServerName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingServer) {
        Write-Warning "SQL Server '$ServerName' already exists"
        Write-Warning "Cannot retrieve existing password. You may need to reset it manually."
        # Try to use existing or prompt
        Write-Info "Please ensure you have the admin password for existing server"
    }
    else {
        # Create SQL Server
        try {
            Write-Info "Creating SQL Server (this may take 3-5 minutes)..."
            $server = az sql server create `
                --name $ServerName `
                --resource-group $ResourceGroupName `
                --location $Location `
                --admin-user $AdminUser `
                --admin-password $adminPassword `
                --enable-public-network true `
                --output json | ConvertFrom-Json
            
            Write-Success "SQL Server created successfully"
            Write-Info "Admin User: $AdminUser"
            Write-Info "Admin Password: [Generated securely - will be saved to .env]"
            
            # Add firewall rule to allow Azure services
            Write-Info "Configuring firewall rules..."
            az sql server firewall-rule create `
                --name "AllowAzureServices" `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --start-ip-address 0.0.0.0 `
                --end-ip-address 0.0.0.0 `
                --output none
            
            # Add firewall rule to allow all IPs (for lab purposes)
            az sql server firewall-rule create `
                --name "AllowAllIPs" `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --start-ip-address 0.0.0.0 `
                --end-ip-address 255.255.255.255 `
                --output none
            
            Write-Success "Firewall rules configured"
        }
        catch {
            Write-Error "Failed to create SQL Server: $_"
            Write-Info "You may need to create this resource manually in the portal"
            return $null
        }
    }
    
    # Create SQL Database
    Write-Info "Creating SQL Database: $DatabaseName"
    $existingDb = az sql db show `
        --name $DatabaseName `
        --server $ServerName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingDb) {
        Write-Warning "Database '$DatabaseName' already exists"
    }
    else {
        try {
            Write-Info "Creating database with GP_Gen5 SKU (this may take 2-3 minutes)..."
            $database = az sql db create `
                --name $DatabaseName `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --edition GeneralPurpose `
                --family Gen5 `
                --capacity 2 `
                --compute-model Provisioned `
                --max-size 32GB `
                --backup-storage-redundancy Geo `
                --zone-redundant false `
                --read-scale Disabled `
                --no-wait `
                --output json 2>$null
            
            Write-Success "Database creation initiated"
            Write-Info "Database: $DatabaseName | Edition: GeneralPurpose (Gen5) | vCores: 2"
        }
        catch {
            Write-Warning "Could not create database: $_"
            Write-Info "You may need to create the database manually in the portal"
        }
    }
    
    Write-Success "SQL Server setup completed"
    
    return @{
        ServerName = $ServerName
        DatabaseName = $DatabaseName
        AdminUser = $AdminUser
        AdminPassword = $adminPassword
        FullyQualifiedName = "$ServerName.database.windows.net"
    }
}

# Create PostgreSQL Flexible Server
function New-PostgreSQLFlexibleServer {
    param(
        [string]$ServerName,
        [string]$DatabaseName = "books",
        [string]$AdminUser = "postgres"
    )
    
    Write-Header "Creating PostgreSQL Flexible Server"
    
    Write-Info "Creating PostgreSQL server: $ServerName"
    Write-Info "Configuration: Standard_D2s_v3 (GeneralPurpose), 128GB storage, PostgreSQL 15"
    
    # Generate secure password
    $adminPassword = New-SecurePassword -Length 16
    
    # Check if PostgreSQL server exists
    $existingServer = az postgres flexible-server show `
        --name $ServerName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingServer) {
        Write-Warning "PostgreSQL server '$ServerName' already exists"
        Write-Warning "Cannot retrieve existing password. You may need to reset it manually."
        Write-Info "Please ensure you have the admin password for existing server"
    }
    else {
        # Create PostgreSQL Flexible Server
        try {
            Write-Info "Creating PostgreSQL Flexible Server (this may take 5-10 minutes)..."
            $server = az postgres flexible-server create `
                --name $ServerName `
                --resource-group $ResourceGroupName `
                --location $Location `
                --admin-user $AdminUser `
                --admin-password $adminPassword `
                --sku-name Standard_D2s_v3 `
                --tier GeneralPurpose `
                --version 15 `
                --storage-size 128 `
                --public-access 0.0.0.0-255.255.255.255 `
                --backup-retention 7 `
                --geo-redundant-backup Disabled `
                --high-availability Disabled `
                --output json | ConvertFrom-Json
            
            Write-Success "PostgreSQL server created successfully"
            Write-Info "Admin User: $AdminUser"
            Write-Info "Admin Password: [Generated securely - will be saved to .env]"
            Write-Info "PostgreSQL Version: 15"
            
            # Enable required extensions
            Write-Info "Enabling vector and Azure AI extensions..."
            try {
                # Update azure.extensions parameter
                az postgres flexible-server parameter set `
                    --name azure.extensions `
                    --value "VECTOR,AZURE_AI" `
                    --server-name $ServerName `
                    --resource-group $ResourceGroupName `
                    --output none
                
                Write-Success "Vector and Azure AI extensions enabled"
            }
            catch {
                Write-Warning "Could not enable extensions automatically: $_"
                Write-Info "You can enable them manually in the Azure Portal:"
                Write-Info "  Server parameters → azure.extensions → Select VECTOR and AZURE_AI"
            }
            
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Failed to create PostgreSQL server: $_"
            Write-Info "You may need to create this resource manually in the portal"
            return $null
        }
    }
    
    # Create database
    Write-Info "Creating database: $DatabaseName"
    $dbExists = az postgres flexible-server db show `
        --server-name $ServerName `
        --resource-group $ResourceGroupName `
        --database-name $DatabaseName `
        2>$null
    
    if ($dbExists) {
        Write-Warning "Database '$DatabaseName' already exists"
    }
    else {
        try {
            az postgres flexible-server db create `
                --server-name $ServerName `
                --resource-group $ResourceGroupName `
                --database-name $DatabaseName `
                --output none
            Write-Success "Database '$DatabaseName' created"
        }
        catch {
            Write-Warning "Could not create database: $_"
            Write-Info "You can create it manually using: CREATE DATABASE $DatabaseName;"
        }
    }
    
    Write-Success "PostgreSQL Flexible Server setup completed"
    Write-Info "Server: $ServerName.postgres.database.azure.com"
    Write-Info "Database: $DatabaseName | Admin: $AdminUser | Version: PostgreSQL 15"
    Write-Info "Extensions: VECTOR, AZURE_AI"
    
    return @{
        ServerName = $ServerName
        DatabaseName = $DatabaseName
        AdminUser = $AdminUser
        AdminPassword = $adminPassword
        FullyQualifiedName = "$ServerName.postgres.database.azure.com"
        Port = 5432
    }
}

# Collect all endpoints and keys
function Get-ResourceInformation {
    param(
        [string]$FoundryName,
        [string]$ProjectName,
        [string]$BingName,
        [string]$SearchServiceName,
        [string]$CosmosAccountName,
        [hashtable]$SqlServerInfo,
        [hashtable]$PostgresServerInfo
    )
    
    Write-Header "Collecting Resource Information"
    
    $info = @{
        Subscription = $script:AccountInfo.id
        TenantId = $script:AccountInfo.tenantId
        ResourceGroup = $ResourceGroupName
        Location = $Location
    }
    
    # Get AI Foundry information
    Write-Info "Getting AI Foundry information..."
    try {
        $foundryAccount = az cognitiveservices account show `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json | ConvertFrom-Json
        
        $foundryKeys = az cognitiveservices account keys list `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json | ConvertFrom-Json
        
        $info.FoundryEndpoint = $foundryAccount.properties.endpoint
        $info.FoundryKey = $foundryKeys.key1
        $info.FoundryName = $FoundryName
        $info.ProjectName = $ProjectName
        
        Write-Success "AI Foundry information collected"
    }
    catch {
        Write-Warning "Could not retrieve AI Foundry details: $_"
    }
    
    # Get Bing information
    if ($BingName) {
        Write-Info "Getting Bing resource information..."
        try {
            $bingAccount = az cognitiveservices account show `
                --name $BingName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $bingKeys = az cognitiveservices account keys list `
                --name $BingName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $info.BingEndpoint = $bingAccount.properties.endpoint
            $info.BingKey = $bingKeys.key1
            $info.BingConnectionName = $BingName
            
            Write-Success "Bing resource information collected"
        }
        catch {
            Write-Warning "Could not retrieve Bing details: $_"
        }
    }
    
    # Get AI Search information
    if ($SearchServiceName) {
        Write-Info "Getting AI Search information..."
        try {
            $searchService = az search service show `
                --name $SearchServiceName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $searchKeys = az search admin-key show `
                --service-name $SearchServiceName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $info.SearchEndpoint = "https://$SearchServiceName.search.windows.net"
            $info.SearchKey = $searchKeys.primaryKey
            
            Write-Success "AI Search information collected"
        }
        catch {
            Write-Warning "Could not retrieve AI Search details: $_"
        }
    }
    
    # Get Cosmos DB information
    if ($CosmosAccountName) {
        Write-Info "Getting Cosmos DB information..."
        try {
            $cosmosAccount = az cosmosdb show `
                --name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $cosmosKeys = az cosmosdb keys list `
                --name $CosmosAccountName `
                --resource-group $ResourceGroupName `
                --output json | ConvertFrom-Json
            
            $info.CosmosEndpoint = $cosmosAccount.documentEndpoint
            $info.CosmosKey = $cosmosKeys.primaryMasterKey
            $info.CosmosAccountName = $CosmosAccountName
            
            Write-Success "Cosmos DB information collected"
        }
        catch {
            Write-Warning "Could not retrieve Cosmos DB details: $_"
        }
    }
    
    # Add SQL Server information
    if ($SqlServerInfo) {
        Write-Info "Adding SQL Server information..."
        $info.SqlServer = $SqlServerInfo.FullyQualifiedName
        $info.SqlAdminUser = $SqlServerInfo.AdminUser
        $info.SqlAdminPassword = $SqlServerInfo.AdminPassword
        $info.SqlDatabase = $SqlServerInfo.DatabaseName
        Write-Success "SQL Server information added"
    }
    
    # Add PostgreSQL Server information
    if ($PostgresServerInfo) {
        Write-Info "Adding PostgreSQL Server information..."
        $info.PostgresHost = $PostgresServerInfo.FullyQualifiedName
        $info.PostgresUser = $PostgresServerInfo.AdminUser
        $info.PostgresPassword = $PostgresServerInfo.AdminPassword
        $info.PostgresDatabase = $PostgresServerInfo.DatabaseName
        $info.PostgresPort = $PostgresServerInfo.Port
        Write-Success "PostgreSQL Server information added"
    }
    
    return $info
}

# Update .env file
function Update-EnvFile {
    param(
        [hashtable]$Info
    )
    
    Write-Header "Updating .env File"
    
    $envPath = Join-Path $PSScriptRoot ".env"
    
    if (-not (Test-Path $envPath)) {
        Write-Warning ".env file not found at: $envPath"
        Write-Info "Creating new .env file..."
        New-Item -Path $envPath -ItemType File -Force | Out-Null
    }
    
    # Read existing content
    $envContent = Get-Content $envPath -Raw -ErrorAction SilentlyContinue
    
    if ([string]::IsNullOrWhiteSpace($envContent)) {
        Write-Warning ".env file is empty, creating from scratch"
        $envContent = @"
# Azure AI Foundry Configuration
# Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

"@
    }
    
    # Update or add values
    $updates = @{
        "AI_FOUNDRY_PROJECT_ENDPOINT" = "$($Info.FoundryEndpoint)/api/projects/$($Info.ProjectName)"
        "AI_FOUNDRY_NAME" = $Info.FoundryName
        "AZURE_PROJECT_NAME" = $Info.ProjectName
        "AZURE_OPENAI_ENDPOINT" = "$($Info.FoundryEndpoint)/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview"
        "AZURE_OPENAI_BASE_URL_ENDPOINT" = $Info.FoundryEndpoint
        "AZURE_OPENAI_API_KEY" = $Info.FoundryKey
        "MODEL_DEPLOYMENT_NAME" = "gpt-4o"
        "MODEL_API_VERSION" = "2025-01-01-preview"
        "AZURE_OPENAI_EMBEDDING_ENDPOINT" = "$($Info.FoundryEndpoint)/openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15"
        "AZURE_OPENAI_EMBEDDING_API_KEY" = $Info.FoundryKey
        "EMBEDDING_MODEL_DEPLOYMENT_NAME" = "text-embedding-3-large"
        "EMBEDDING_MODEL_API_VERSION" = "2023-05-15"
        "AZURE_OPENAI_EMBEDDING_ADA_ENDPOINT" = "$($Info.FoundryEndpoint)/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15"
        "AZURE_OPENAI_EMBEDDING_ADA_API_KEY" = $Info.FoundryKey
        "EMBEDDING_ADA_MODEL_DEPLOYMENT_NAME" = "text-embedding-ada-002"
        "EMBEDDING_ADA_MODEL_API_VERSION" = "2023-05-15"
        "GROUNDING_WITH_BING_CONNECTION_NAME" = $Info.BingConnectionName
        "TENANT_ID" = $Info.TenantId
        "AZURE_SUBSCRIPTION_ID" = $Info.Subscription
        "AZURE_RESOURCE_GROUP" = $Info.ResourceGroup
        "AZURE_AI_SEARCH_ENDPOINT" = $Info.SearchEndpoint
        "AZURE_AI_SEARCH_API_KEY" = $Info.SearchKey
        "COSMOS_ENDPOINT" = $Info.CosmosEndpoint
        "COSMOS_KEY" = $Info.CosmosKey
        "SQL_SERVER" = $Info.SqlServer
        "SQL_PWD" = $Info.SqlAdminPassword
        "POSTGRES_HOST" = $Info.PostgresHost
        "POSTGRES_USER" = $Info.PostgresUser
        "POSTGRES_PASSWORD" = $Info.PostgresPassword
        "POSTGRES_DATABASE" = $Info.PostgresDatabase
        "POSTGRES_PORT" = $Info.PostgresPort
    }
    
    foreach ($key in $updates.Keys) {
        $value = $updates[$key]
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        
        if ($envContent -match "(?m)^$key=.*$") {
            # Update existing
            $envContent = $envContent -replace "(?m)^$key=.*$", "$key=$value"
            Write-Info "Updated: $key"
        }
        else {
            # Add new
            $envContent += "`n$key=$value"
            Write-Info "Added: $key"
        }
    }
    
    # Save updated content
    $envContent | Set-Content $envPath -NoNewline
    Write-Success ".env file updated successfully"
    Write-Info "Location: $envPath"
}

# Generate summary report
function Show-DeploymentSummary {
    param(
        [hashtable]$Info
    )
    
    Write-Header "Deployment Summary"
    
    Write-Host ""
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $Info.ResourceGroup -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $Info.Location -ForegroundColor White
    
    Write-Host "Subscription ID:     " -NoNewline -ForegroundColor Gray
    Write-Host $Info.Subscription -ForegroundColor White
    
    Write-Host "Tenant ID:           " -NoNewline -ForegroundColor Gray
    Write-Host $Info.TenantId -ForegroundColor White
    
    Write-Host ""
    Write-Host "AI Foundry:          " -NoNewline -ForegroundColor Gray
    Write-Host $Info.FoundryName -ForegroundColor White
    
    Write-Host "Project Name:        " -NoNewline -ForegroundColor Gray
    Write-Host $Info.ProjectName -ForegroundColor White
    
    Write-Host "Foundry Endpoint:    " -NoNewline -ForegroundColor Gray
    Write-Host $Info.FoundryEndpoint -ForegroundColor White
    
    if ($Info.BingConnectionName) {
        Write-Host ""
        Write-Host "Bing Connection:     " -NoNewline -ForegroundColor Gray
        Write-Host $Info.BingConnectionName -ForegroundColor White
    }
    
    if ($Info.SearchEndpoint) {
        Write-Host ""
        Write-Host "AI Search Endpoint:  " -NoNewline -ForegroundColor Gray
        Write-Host $Info.SearchEndpoint -ForegroundColor White
    }
    
    if ($Info.CosmosEndpoint) {
        Write-Host ""
        Write-Host "Cosmos DB Endpoint:  " -NoNewline -ForegroundColor Gray
        Write-Host $Info.CosmosEndpoint -ForegroundColor White
        Write-Host "Cosmos DB Account:   " -NoNewline -ForegroundColor Gray
        Write-Host $Info.CosmosAccountName -ForegroundColor White
    }
    
    if ($Info.SqlServer) {
        Write-Host ""
        Write-Host "SQL Server:          " -NoNewline -ForegroundColor Gray
        Write-Host $Info.SqlServer -ForegroundColor White
        Write-Host "SQL Database:        " -NoNewline -ForegroundColor Gray
        Write-Host $Info.SqlDatabase -ForegroundColor White
        Write-Host "SQL Admin User:      " -NoNewline -ForegroundColor Gray
        Write-Host $Info.SqlAdminUser -ForegroundColor White
    }
    
    if ($Info.PostgresHost) {
        Write-Host ""
        Write-Host "PostgreSQL Server:   " -NoNewline -ForegroundColor Gray
        Write-Host $Info.PostgresHost -ForegroundColor White
        Write-Host "PostgreSQL Database: " -NoNewline -ForegroundColor Gray
        Write-Host $Info.PostgresDatabase -ForegroundColor White
        Write-Host "PostgreSQL User:     " -NoNewline -ForegroundColor Gray
        Write-Host $Info.PostgresUser -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Models Deployed:" -ForegroundColor Gray
    Write-Host "  → gpt-4o" -ForegroundColor White
    Write-Host "  → gpt-4o-mini" -ForegroundColor White
    Write-Host "  → text-embedding-3-large" -ForegroundColor White
    Write-Host "  → text-embedding-ada-002" -ForegroundColor White
    
    Write-Host ""
    Write-Success "Deployment completed successfully!"
    Write-Info "Next steps:"
    Write-Host "  1. Verify resources in Azure Portal: https://portal.azure.com" -ForegroundColor Cyan
    Write-Host "  2. Connect resources in AI Foundry Portal: https://ai.azure.com" -ForegroundColor Cyan
    Write-Host "  3. Review the .env file for connection details" -ForegroundColor Cyan
    Write-Host ""
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║        Azure AI Foundry Deployment Automation Script          ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $script:AccountInfo = Test-Prerequisites
        
        # Get Lab Instance ID
        Get-LabInstanceId
        
        # Set resource names
        $foundryName = "ai-foundry-$script:LabInstanceId"
        $projectName = "firstProject"
        $bingName = "gwbing-$script:LabInstanceId"
        $searchName = "aisearch-$script:LabInstanceId"
        $cosmosName = "cosmosaivector-$script:LabInstanceId"
        $sqlServerName = "sqlaivector-$script:LabInstanceId"
        $postgresServerName = "pgaivector-$script:LabInstanceId"
        
        # Initialize resource group
        Initialize-ResourceGroup
        
        # Create AI Foundry
        $foundry = New-AIFoundryResource -FoundryName $foundryName -ProjectName $projectName
        
        # Define models to deploy
        $models = @(
            @{ Name = "GPT-4o"; DeploymentName = "gpt-4o"; ModelName = "gpt-4o"; Version = "2024-05-13"; Capacity = 10 },
            @{ Name = "GPT-4o-mini"; DeploymentName = "gpt-4o-mini"; ModelName = "gpt-4o-mini"; Version = "2024-07-18"; Capacity = 10 },
            @{ Name = "Text Embedding 3 Large"; DeploymentName = "text-embedding-3-large"; ModelName = "text-embedding-3-large"; Version = "1"; Capacity = 10 },
            @{ Name = "Text Embedding Ada 002"; DeploymentName = "text-embedding-ada-002"; ModelName = "text-embedding-ada-002"; Version = "2"; Capacity = 10 }
        )
        
        # Deploy models
        $deployedModels = Deploy-AIModels -FoundryName $foundryName -Models $models
        
        # Create Bing resource
        $bing = New-BingResource -BingName $bingName
        
        # Create AI Search resource
        $search = New-AISearchResource -SearchServiceName $searchName
        
        # Create Cosmos DB resource
        $cosmos = New-CosmosDBResource -CosmosAccountName $cosmosName
        
        # Create SQL Server and Database
        $sqlServer = New-SQLServerAndDatabase -ServerName $sqlServerName
        
        # Create PostgreSQL Flexible Server
        $postgresServer = New-PostgreSQLFlexibleServer -ServerName $postgresServerName
        
        # Collect all information
        $resourceInfo = Get-ResourceInformation `
            -FoundryName $foundryName `
            -ProjectName $projectName `
            -BingName $bingName `
            -SearchServiceName $searchName `
            -CosmosAccountName $cosmosName `
            -SqlServerInfo $sqlServer `
            -PostgresServerInfo $postgresServer
        
        # Update .env file
        Update-EnvFile -Info $resourceInfo
        
        # Show summary
        Show-DeploymentSummary -Info $resourceInfo
        
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  To connect resources in AI Foundry Portal:" -ForegroundColor Green
        Write-Host "  1. Visit: https://ai.azure.com" -ForegroundColor Green
        Write-Host "  2. Navigate to your AI Foundry: $foundryName" -ForegroundColor Green
        Write-Host "  3. Go to Connected Resources and add connections" -ForegroundColor Green
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
