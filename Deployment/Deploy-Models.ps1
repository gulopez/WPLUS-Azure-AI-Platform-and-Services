<#
.SYNOPSIS
    Deploy AI models to Azure AI Foundry/Cognitive Services account

.DESCRIPTION
    This script deploys multiple AI models to an existing Azure AI Foundry or Cognitive Services account.
    It supports deploying:
    - GPT-4o model
    - GPT-4o-mini model
    - Text Embedding 3 Large model
    - Text Embedding Ada 002 model
    
    You can also provide custom models via the -Models parameter.

.PARAMETER ResourceGroupName
    The name of the resource group containing the AI Foundry account (Required)

.PARAMETER FoundryName
    The name of the AI Foundry/Cognitive Services account (Required)

.PARAMETER Models
    Array of model definitions to deploy. Each model should have:
    - Name: Display name
    - DeploymentName: Deployment identifier
    - ModelName: Azure model name
    - Version: Model version
    - Capacity: TPM capacity (tokens per minute)
    
    If not provided, default models will be deployed.

.PARAMETER Location
    The Azure region (default: eastus2). Used for display purposes only.

.EXAMPLE
    .\Deploy-Models.ps1 -ResourceGroupName "WPLUS-Foundry" -FoundryName "myopenAI-wplus"
    
    Deploys default models (gpt-4o, gpt-4o-mini, text-embedding-3-large, text-embedding-ada-002)

.EXAMPLE
    $customModels = @(
        @{ Name = "GPT-4o"; DeploymentName = "gpt-4o"; ModelName = "gpt-4o"; Version = "2024-11-20"; Capacity = 100 }
    )
    .\Deploy-Models.ps1 -ResourceGroupName "WPLUS-Foundry" -FoundryName "myopenAI-wplus" -Models $customModels

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - AI Foundry/Cognitive Services account must already exist
    - Appropriate permissions to deploy models
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true, HelpMessage="AI Foundry/Cognitive Services account name")]
    [string]$FoundryName,
    
    [Parameter(Mandatory=$false, HelpMessage="Array of model definitions to deploy")]
    [array]$Models,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2"
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

function Write-ErrorMsg { 
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
        if (!$azVersion) {
            throw "Azure CLI not found"
        }
        Write-Success "Azure CLI is installed (version: $($azVersion.'azure-cli'))"
    }
    catch {
        Write-ErrorMsg "Azure CLI is not installed. Please install from: https://aka.ms/installazurecliwindows"
        exit 1
    }
    
    # Check if logged in to Azure
    Write-Info "Checking Azure login status..."
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if (!$account) {
            throw "Not logged in"
        }
        Write-Success "Logged in to Azure (Subscription: $($account.name))"
        return $account
    }
    catch {
        Write-ErrorMsg "Not logged in to Azure. Please run: az login"
        exit 1
    }
}

# Verify AI Foundry account exists
function Test-FoundryAccount {
    Write-Header "Verifying AI Foundry Account"
    
    Write-Info "Checking if AI Foundry account '$FoundryName' exists..."
    try {
        $foundry = az cognitiveservices account show `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        if (!$foundry) {
            throw "Account not found"
        }
        
        Write-Success "AI Foundry account found"
        Write-Info "Account: $($foundry.name)"
        Write-Info "Location: $($foundry.location)"
        Write-Info "Kind: $($foundry.kind)"
        Write-Info "SKU: $($foundry.sku.name)"
        return $foundry
    }
    catch {
        Write-ErrorMsg "AI Foundry account '$FoundryName' not found in resource group '$ResourceGroupName'"
        Write-Info "Please ensure the account exists before deploying models"
        exit 1
    }
}

# Deploy AI models
function Deploy-AIModels {
    param(
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

# Show deployment summary
function Show-DeploymentSummary {
    param(
        [hashtable]$Result
    )
    
    Write-Header "Deployment Summary"
    
    Write-Host ""
    Write-Host "AI Foundry Account:  " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryName -ForegroundColor White
    
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $ResourceGroupName -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $Location -ForegroundColor White
    
    Write-Host ""
    
    # Deployed models
    if ($Result.Deployed.Count -gt 0) {
        Write-Host "✓ Successfully Deployed Models: " -ForegroundColor Green -NoNewline
        Write-Host "$($Result.Deployed.Count)" -ForegroundColor White
        foreach ($model in $Result.Deployed) {
            Write-Host "  → $($model.name)" -ForegroundColor Cyan
        }
        Write-Host ""
    }
    
    # Skipped models
    if ($Result.Skipped.Count -gt 0) {
        Write-Host "⚠ Skipped Models (already exist): " -ForegroundColor Yellow -NoNewline
        Write-Host "$($Result.Skipped.Count)" -ForegroundColor White
        foreach ($model in $Result.Skipped) {
            Write-Host "  → $($model.DeploymentName)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Failed models
    if ($Result.Failed.Count -gt 0) {
        Write-Host "✗ Failed Models: " -ForegroundColor Red -NoNewline
        Write-Host "$($Result.Failed.Count)" -ForegroundColor White
        foreach ($model in $Result.Failed) {
            Write-Host "  → $($model.DeploymentName)" -ForegroundColor Red
        }
        Write-Host ""
        Write-Info "Failed models may need to be deployed manually in the Azure Portal"
        Write-Host ""
    }
    
    if ($Result.Deployed.Count -gt 0 -or $Result.Skipped.Count -gt 0) {
        Write-Success "Model deployment process completed!"
        Write-Host ""
        Write-Info "Next steps:"
        Write-Host "  1. Verify deployments in Azure Portal: https://portal.azure.com" -ForegroundColor Cyan
        Write-Host "  2. Test models in AI Foundry Portal: https://ai.azure.com" -ForegroundColor Cyan
        Write-Host "  3. Use Get-FoundryInfo.ps1 to retrieve endpoint and keys" -ForegroundColor Cyan
    }
    else {
        Write-Warning "No models were deployed successfully"
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
        Write-Host "║            AI Models Deployment Script                        ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Verify AI Foundry account exists
        $foundryAccount = Test-FoundryAccount
        
        # Define default models if not provided
        if (-not $Models -or $Models.Count -eq 0) {
            Write-Info "No models specified, using default model set..."
            $Models = @(
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
            Write-Success "Using 4 default models"
            Write-Host ""
        }
        else {
            Write-Success "Using $($Models.Count) custom model(s)"
            Write-Host ""
        }
        
        # Deploy models
        $result = Deploy-AIModels -ModelsToDeploy $Models
        
        # Show summary
        Show-DeploymentSummary -Result $result
        
        # Exit with appropriate code
        if ($result.Failed.Count -gt 0 -and $result.Deployed.Count -eq 0) {
            exit 1
        }
        
    }
    catch {
        Write-ErrorMsg "An error occurred: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        exit 1
    }
}

# Run the script
Main
