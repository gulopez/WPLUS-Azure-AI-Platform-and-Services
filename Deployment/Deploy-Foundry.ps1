<#
.SYNOPSIS
    Deploy Azure AI Foundry Hub and Project

.DESCRIPTION
    This script automates the deployment of:
    - Azure AI Foundry hub resource
    - Azure AI Foundry project under the hub
    - Cognitive Services account for AI services

.PARAMETER ResourceGroupName
    The name of the resource group to use (required)

.PARAMETER FoundryName
    The name of the AI Foundry hub to create (required)

.PARAMETER Location
    The Azure region for deployment (default: eastus2)

.PARAMETER ProjectName
    The name of the project to create under the hub (default: firstProject)

.EXAMPLE
    .\Deploy-Foundry.ps1 -ResourceGroupName "azureaiworkshoprg" -FoundryName "ai-foundry-12345"

.EXAMPLE
    .\Deploy-Foundry.ps1 -ResourceGroupName "myResourceGroup" -FoundryName "myFoundry" -ProjectName "myProject" -Location "eastus"

.NOTES
    Prerequisites: 
    - Azure CLI must be installed
    - User must be logged in to Azure CLI
    - Appropriate permissions in the subscription
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "azureaiworkshoprg",
    
    [Parameter(Mandatory=$true)]
    [string]$FoundryName = "ai-foundry-59483770",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectName = "firstProject",

    # Model deployment options (merged from Deploy-Models.ps1)
    [Parameter(Mandatory=$true)]
    [switch]$DeployModels,

    [Parameter(Mandatory=$false, HelpMessage="Array of model definitions to deploy")]
    [array]$Models
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

# Create Azure AI Foundry resource using Cognitive Services native project management
# This creates:
#   - Microsoft.CognitiveServices/accounts  (kind=AIServices, allowProjectManagement=true)
#   - Microsoft.CognitiveServices/accounts/projects  (sub-resource of the account)
# Matches the shape defined in foundry.json / foundry-Project.
function New-AIFoundryResource {
    param(
        [string]$FoundryName,
        [string]$ProjectName,
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$SubscriptionId
    )
    
    Write-Header "Creating Azure AI Foundry Resource"
    
    Write-Info "Creating AI Foundry Account: $FoundryName"
    Write-Info "Project Name: $ProjectName"
    Write-Info "Location: $Location"
    
    $apiVersion = "2025-06-01"
    $accountUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/${FoundryName}?api-version=$apiVersion"
    
    # ── Step 1: Check if the Cognitive Services account already exists ──
    $existingFoundry = $null
    try {
        $existingFoundry = az rest --method get --uri $accountUri --output json 2>$null | ConvertFrom-Json
    }
    catch { <# does not exist yet #> }
    
    if ($existingFoundry -and $existingFoundry.name) {
        Write-Warning "AI Foundry account '$FoundryName' already exists"
        
        # Verify allowProjectManagement is enabled
        if ($existingFoundry.properties.allowProjectManagement -ne $true) {
            Write-Info "Enabling native project management on existing account..."
            $patchBody = @{
                properties = @{
                    allowProjectManagement = $true
                    defaultProject         = $ProjectName
                    associatedProjects     = @( $ProjectName )
                }
            } | ConvertTo-Json -Depth 5
            
            $patchBodyFile = [System.IO.Path]::GetTempFileName()
            $patchBody | Out-File -FilePath $patchBodyFile -Encoding UTF8 -Force
            
            try {
                az rest --method patch --uri $accountUri `
                    --body "@$patchBodyFile" `
                    --headers "Content-Type=application/json" `
                    --output none 2>&1 | Out-Null
                Write-Success "Project management enabled on account"
            }
            catch {
                Write-Warning "Could not patch account: $_"
            }
            finally {
                Remove-Item -Path $patchBodyFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        # ── Step 2: Create the Cognitive Services account ──
        Write-Info "Creating Cognitive Services account with native project management..."
        
        $accountBody = @{
            location   = $Location
            sku        = @{ name = "S0" }
            kind       = "AIServices"
            identity   = @{ type = "SystemAssigned" }
            properties = @{
                apiProperties          = @{}
                customSubDomainName    = $FoundryName
                networkAcls            = @{
                    defaultAction       = "Allow"
                    virtualNetworkRules = @()
                    ipRules             = @()
                }
                allowProjectManagement = $true
                defaultProject         = $ProjectName
                associatedProjects     = @( $ProjectName )
                publicNetworkAccess    = "Enabled"
            }
        } | ConvertTo-Json -Depth 5
        
        # Write to temp file to avoid PowerShell quote-mangling with az rest --body
        $accountBodyFile = [System.IO.Path]::GetTempFileName()
        $accountBody | Out-File -FilePath $accountBodyFile -Encoding UTF8 -Force
        
        try {
            $result = az rest --method put --uri $accountUri `
                --body "@$accountBodyFile" `
                --headers "Content-Type=application/json" `
                --output json 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Account creation failed: $result"
            }
            
            $existingFoundry = $result | ConvertFrom-Json
            Write-Success "AI Foundry account created successfully"
        }
        catch {
            Write-Error "Failed to create AI Foundry account: $_"
            exit 1
        }
        finally {
            Remove-Item -Path $accountBodyFile -Force -ErrorAction SilentlyContinue
        }
        
        # Wait for provisioning
        Write-Info "Waiting for account provisioning..."
        Start-Sleep -Seconds 15
    }
    
    # ── Step 3: Create the project as a Cognitive Services sub-resource ──
    $projectUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects/${ProjectName}?api-version=$apiVersion"
    
    $existingProject = $null
    try {
        $existingProject = az rest --method get --uri $projectUri --output json 2>$null | ConvertFrom-Json
    }
    catch { <# does not exist yet #> }
    
    if ($existingProject -and $existingProject.name) {
        Write-Warning "Project '$ProjectName' already exists"
    }
    else {
        Write-Info "Creating project '$ProjectName' as Cognitive Services sub-resource..."
        
        $projectBody = @{
            location   = $Location
            kind       = "AIServices"
            identity   = @{ type = "SystemAssigned" }
            properties = @{
                description = "Default project created with the resource"
                displayName = $ProjectName
            }
        } | ConvertTo-Json -Depth 5
        
        # Write to temp file to avoid PowerShell quote-mangling with az rest --body
        $projectBodyFile = [System.IO.Path]::GetTempFileName()
        $projectBody | Out-File -FilePath $projectBodyFile -Encoding UTF8 -Force
        
        try {
            $result = az rest --method put --uri $projectUri `
                --body "@$projectBodyFile" `
                --headers "Content-Type=application/json" `
                --output json 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Project creation failed: $result"
            }
            
            Write-Success "AI Foundry project '$ProjectName' created successfully"
        }
        catch {
            Write-Warning "Could not create project automatically: $_"
            Write-Info "You can create it manually in AI Foundry Portal: https://ai.azure.com"
        }
        finally {
            Remove-Item -Path $projectBodyFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Success "AI Foundry setup completed"
    Write-Info "Account: $FoundryName | Project: $ProjectName | Location: $Location"
    
    return @{
        FoundryName = $FoundryName
        ProjectName = $ProjectName
        Location = $Location
    }
}

# Get AI Foundry information
function Get-AIFoundryInformation {
    param(
        [string]$FoundryName,
        [string]$ResourceGroupName
    )
    
    Write-Header "Retrieving AI Foundry Information"
    
    Write-Info "Getting AI Foundry account details..."
    
    try {
        # Get account details
        $foundryAccount = az cognitiveservices account show `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        if (-not $foundryAccount) {
            Write-Error "AI Foundry account '$FoundryName' not found in resource group '$ResourceGroupName'"
            return $null
        }
        
        Write-Success "Account details retrieved"
        
        # Get account keys
        Write-Info "Retrieving account keys..."
        $foundryKeys = az cognitiveservices account keys list `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        Write-Success "Account keys retrieved"
        
        Write-Success "AI Foundry information retrieved successfully"
        
        return @{
            Name = $FoundryName
            Endpoint = $foundryAccount.properties.endpoint
            PrimaryKey = $foundryKeys.key1
            SecondaryKey = $foundryKeys.key2
            ResourceGroup = $ResourceGroupName
            Location = $foundryAccount.location
            Kind = $foundryAccount.kind
            Sku = $foundryAccount.sku.name
        }
    }
    catch {
        Write-Error "Failed to retrieve AI Foundry information: $_"
        return $null
    }
}

# Default model set (same defaults as Deploy-Models.ps1)
function Get-DefaultModels {
    return @(
        @{
            Name = "GPT-4o"
            DeploymentName = "gpt-4o"
            ModelName = "gpt-4o"
            Version = "2024-11-20"
            Capacity = 100
        },
        @{
            Name = "GPT-4o-mini"
            DeploymentName = "gpt-4o-mini"
            ModelName = "gpt-4o-mini"
            Version = "2024-07-18"
            Capacity = 250
        },
        @{
            Name = "Text Embedding 3 Large"
            DeploymentName = "text-embedding-3-large"
            ModelName = "text-embedding-3-large"
            Version = "1"
            Capacity = 150
        },
        @{
            Name = "Text Embedding Ada 002"
            DeploymentName = "text-embedding-ada-002"
            ModelName = "text-embedding-ada-002"
            Version = "2"
            Capacity = 150
        }
    )
}

# Deploy AI models (merged from Deploy-Models.ps1)
function Deploy-AIModels {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FoundryName,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [array]$ModelsToDeploy
    )

    Write-Header "Deploying AI Models"

    $deployedModels = @()
    $skippedModels = @()
    $failedModels = @()

    foreach ($model in $ModelsToDeploy) {
        Write-Info "Deploying model: $($model.Name)"
        Write-Info "  Deployment Name: $($model.DeploymentName)"
        Write-Info "  Model: $($model.ModelName) v$($model.Version)"
        Write-Info "  Capacity: $($model.Capacity) TPM"

        # Check if model already deployed
        $existing = az cognitiveservices account deployment show `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --deployment-name $model.DeploymentName `
            2>$null | ConvertFrom-Json

        if ($existing) {
            Write-Warning "Model '$($model.DeploymentName)' already deployed"
            $skippedModels += $model
            $deployedModels += $existing
            Write-Host ""
            continue
        }

        # Deploy the model
        try {
            Write-Info "Creating deployment..."
            $deployment = az cognitiveservices account deployment create `
                --name $FoundryName `
                --resource-group $ResourceGroupName `
                --deployment-name $model.DeploymentName `
                --model-name $model.ModelName `
                --model-version $model.Version `
                --model-format OpenAI `
                --sku-capacity $model.Capacity `
                --sku-name "Standard" `
                --output json 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "Deployment failed: $deployment"
            }

            $deploymentObj = $deployment | ConvertFrom-Json
            Write-Success "Model '$($model.DeploymentName)' deployed successfully"
            $deployedModels += $deploymentObj
            Write-Host ""
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Warning "Could not deploy model '$($model.DeploymentName)': $_"
            Write-Info "You may need to deploy this model manually in the portal"
            $failedModels += $model
            Write-Host ""
        }
    }

    return @{
        Deployed = $deployedModels
        Skipped = $skippedModels
        Failed = $failedModels
    }
}

# Display deployment summary
function Show-DeploymentSummary {
    param(
        [hashtable]$DeploymentInfo,
        [hashtable]$FoundryInfo,
        [hashtable]$ModelsResult
    )
    
    Write-Header "Deployment Summary"
    
    Write-Host ""
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $ResourceGroupName -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $Location -ForegroundColor White
    
    Write-Host ""
    Write-Host "AI Foundry Hub:      " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.FoundryName -ForegroundColor White
    
    Write-Host "Project Name:        " -NoNewline -ForegroundColor Gray
    Write-Host $DeploymentInfo.ProjectName -ForegroundColor White
    
    if ($FoundryInfo) {
        Write-Host "Foundry Endpoint:    " -NoNewline -ForegroundColor Gray
        Write-Host $FoundryInfo.Endpoint -ForegroundColor White
        
        Write-Host "Kind:                " -NoNewline -ForegroundColor Gray
        Write-Host $FoundryInfo.Kind -ForegroundColor White
        
        Write-Host "SKU:                 " -NoNewline -ForegroundColor Gray
        Write-Host $FoundryInfo.Sku -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Gray
    Write-Host "  → AI Foundry Hub" -ForegroundColor White
    Write-Host "  → Project: $($DeploymentInfo.ProjectName)" -ForegroundColor White
    if ($ModelsResult) {
        Write-Host "  → Models deployed (see section below)" -ForegroundColor White
    }
    else {
        Write-Host "  → Ready for model deployments" -ForegroundColor White
    }
    
    if ($FoundryInfo -and $FoundryInfo.PrimaryKey) {
        Write-Host ""
        Write-Host "Connection Information:" -ForegroundColor Gray
        Write-Host "  Endpoint:    $($FoundryInfo.Endpoint)" -ForegroundColor White
        Write-Host "  Primary Key: $($FoundryInfo.PrimaryKey.Substring(0, 20))..." -ForegroundColor White
    }

    if ($ModelsResult) {
        Write-Host ""
        Write-Host "Models:" -ForegroundColor Gray

        if ($ModelsResult.Deployed.Count -gt 0) {
            Write-Host "✓ Successfully Deployed Models: " -ForegroundColor Green -NoNewline
            Write-Host "$($ModelsResult.Deployed.Count)" -ForegroundColor White
            foreach ($model in $ModelsResult.Deployed) {
                if ($null -ne $model.name) {
                    Write-Host "  → $($model.name)" -ForegroundColor Cyan
                }
            }
            Write-Host ""
        }

        if ($ModelsResult.Skipped.Count -gt 0) {
            Write-Host "⚠ Skipped Models (already exist): " -ForegroundColor Yellow -NoNewline
            Write-Host "$($ModelsResult.Skipped.Count)" -ForegroundColor White
            foreach ($model in $ModelsResult.Skipped) {
                Write-Host "  → $($model.DeploymentName)" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        if ($ModelsResult.Failed.Count -gt 0) {
            Write-Host "✗ Failed Models: " -ForegroundColor Red -NoNewline
            Write-Host "$($ModelsResult.Failed.Count)" -ForegroundColor White
            foreach ($model in $ModelsResult.Failed) {
                Write-Host "  → $($model.DeploymentName)" -ForegroundColor Red
            }
            Write-Host ""
            Write-Info "Failed models may need to be deployed manually in the Azure Portal"
            Write-Host ""
        }
    }
    
    Write-Host ""
    Write-Success "Deployment completed successfully!"
    Write-Info "Next steps:"
    Write-Host "  1. Verify resources in Azure Portal: https://portal.azure.com" -ForegroundColor Cyan
    Write-Host "  2. Open AI Foundry Portal: https://ai.azure.com" -ForegroundColor Cyan
    if ($ModelsResult) {
        Write-Host "  3. Verify model deployments in AI Foundry Portal" -ForegroundColor Cyan
        Write-Host "  4. Connect additional resources (Bing, AI Search, etc.)" -ForegroundColor Cyan
    }
    else {
        Write-Host "  3. Deploy AI models (gpt-4o, embeddings, etc.)" -ForegroundColor Cyan
        Write-Host "  4. Connect additional resources (Bing, AI Search, etc.)" -ForegroundColor Cyan
    }
    Write-Host ""
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║          Azure AI Foundry Deployment Script                    ║" -ForegroundColor Blue
        Write-Host "║          Hub and Project Creation                              ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Verify resource group
        Test-ResourceGroup
        
        # Create AI Foundry resource
        $deploymentInfo = New-AIFoundryResource `
            -FoundryName $FoundryName `
            -ProjectName $ProjectName `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location `
            -SubscriptionId $accountInfo.id
        
        # Get AI Foundry information
        $foundryInfo = Get-AIFoundryInformation -FoundryName $FoundryName -ResourceGroupName $ResourceGroupName

        # Optionally deploy models (defaults included)
        $modelsResult = $null
        if ($DeployModels) {
            $modelsToDeploy = $Models
            if (-not $modelsToDeploy -or $modelsToDeploy.Count -eq 0) {
                Write-Info "No models specified, using default model set..."
                $modelsToDeploy = Get-DefaultModels
                Write-Success "Using $($modelsToDeploy.Count) default models"
                Write-Host ""
            }
            else {
                Write-Success "Using $($modelsToDeploy.Count) custom model(s)"
                Write-Host ""
            }

            $modelsResult = Deploy-AIModels -FoundryName $FoundryName -ResourceGroupName $ResourceGroupName -ModelsToDeploy $modelsToDeploy
        }
        
        # Show summary
        Show-DeploymentSummary -DeploymentInfo $deploymentInfo -FoundryInfo $foundryInfo -ModelsResult $modelsResult
        
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  AI Foundry Resource Created Successfully!" -ForegroundColor Green
        Write-Host "  Portal: https://portal.azure.com/#resource/subscriptions/$($accountInfo.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName" -ForegroundColor Green
        Write-Host "  AI Foundry: https://ai.azure.com" -ForegroundColor Green
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
