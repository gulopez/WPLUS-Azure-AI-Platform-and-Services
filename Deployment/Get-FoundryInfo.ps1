<#
.SYNOPSIS
    Retrieve and display information about an existing Azure AI Foundry resource

.DESCRIPTION
    This script retrieves comprehensive information about an existing AI Foundry resource including:
    - Account details (endpoint, keys, location)
    - Project information
    - Deployed models
    - Configuration settings
    - Connection strings and environment variables

.PARAMETER ResourceGroupName
    The name of the resource group containing the AI Foundry account (required)

.PARAMETER FoundryName
    The name of the AI Foundry hub account (required)

.PARAMETER ProjectName
    The name of the project (optional, default: firstProject)

.EXAMPLE
    .\Get-FoundryInfo.ps1 -ResourceGroupName "azureaiworkshoprg" -FoundryName "ai-foundry-12345"

.EXAMPLE
    .\Get-FoundryInfo.ps1 -ResourceGroupName "myResourceGroup" -FoundryName "myFoundry" -ProjectName "myProject"

.NOTES
    Prerequisites: 
    - Azure CLI must be installed
    - User must be logged in to Azure CLI
    - Appropriate permissions to read AI Foundry resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$FoundryName,
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectName = "firstProject"
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

# Get AI Foundry information
function Get-AIFoundryInformation {
    param(
        [string]$FoundryName,
        [string]$ProjectName,
        [string]$ResourceGroupName
    )
    
    Write-Header "Retrieving AI Foundry Information"
    
    Write-Info "Getting AI Foundry account details for: $FoundryName"
    
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
        
        # Get deployed models
        Write-Info "Retrieving deployed models..."
        $deployments = az cognitiveservices account deployment list `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
        
        if ($deployments) {
            Write-Success "Found $($deployments.Count) deployed model(s)"
        }
        else {
            Write-Warning "No models deployed yet"
        }
        
        # Note: AI Foundry projects are accessed through the Cognitive Services endpoint
        # Project-specific operations are done via the REST API using the endpoint
        Write-Info "Project configuration: $ProjectName"
        
        # Clean endpoint (remove trailing slash if present)
        $cleanEndpoint = $foundryAccount.properties.endpoint.TrimEnd('/')
        Write-Success "Project endpoint available at: $cleanEndpoint/api/projects/$ProjectName"
        
        Write-Success "AI Foundry information retrieved successfully"
        
        # Clean endpoint (remove trailing slash if present)
        $cleanEndpoint = $foundryAccount.properties.endpoint.TrimEnd('/')
        
        return @{
            Name = $FoundryName
            Endpoint = $cleanEndpoint
            PrimaryKey = $foundryKeys.key1
            SecondaryKey = $foundryKeys.key2
            ResourceGroup = $ResourceGroupName
            Location = $foundryAccount.location
            Kind = $foundryAccount.kind
            Sku = $foundryAccount.sku.name
            ProjectName = $ProjectName
            ProjectEndpoint = "$cleanEndpoint/api/projects/$ProjectName"
            Deployments = $deployments
        }
    }
    catch {
        Write-Error "Failed to retrieve AI Foundry information: $_"
        return $null
    }
}

# Display AI Foundry information
function Show-FoundryInformation {
    param(
        [hashtable]$FoundryInfo,
        [string]$SubscriptionId,
        [string]$TenantId
    )
    
    Write-Header "AI Foundry Information Summary"
    
    if (-not $FoundryInfo) {
        Write-Error "No information to display"
        return
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Account Details" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Account Name:        " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.Name -ForegroundColor White
    
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.ResourceGroup -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.Location -ForegroundColor White
    
    Write-Host "Kind:                " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.Kind -ForegroundColor White
    
    Write-Host "SKU:                 " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.Sku -ForegroundColor White
    
    Write-Host "Project Name:        " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.ProjectName -ForegroundColor White
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Connection Information" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Endpoint:            " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryInfo.Endpoint -ForegroundColor White
    
    Write-Host "Project Endpoint:    " -NoNewline -ForegroundColor Gray
    Write-Host "$($FoundryInfo.Endpoint)/api/projects/$($FoundryInfo.ProjectName)" -ForegroundColor White
    
    if ($FoundryInfo.PrimaryKey) {
        Write-Host "Primary Key:         " -NoNewline -ForegroundColor Gray
        Write-Host "$($FoundryInfo.PrimaryKey.Substring(0, 20))..." -ForegroundColor White
    }
    
    if ($FoundryInfo.SecondaryKey) {
        Write-Host "Secondary Key:       " -NoNewline -ForegroundColor Gray
        Write-Host "$($FoundryInfo.SecondaryKey.Substring(0, 20))..." -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Deployed Models" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    if ($FoundryInfo.Deployments -and $FoundryInfo.Deployments.Count -gt 0) {
        foreach ($deployment in $FoundryInfo.Deployments) {
            Write-Host "Model: " -NoNewline -ForegroundColor Cyan
            Write-Host $deployment.name -ForegroundColor White
            
            if ($deployment.properties.model) {
                Write-Host "  └─ Model Name: " -NoNewline -ForegroundColor Gray
                Write-Host $deployment.properties.model.name -ForegroundColor White
                
                if ($deployment.properties.model.version) {
                    Write-Host "     Version: " -NoNewline -ForegroundColor Gray
                    Write-Host $deployment.properties.model.version -ForegroundColor White
                }
                
                if ($deployment.sku) {
                    Write-Host "     Capacity: " -NoNewline -ForegroundColor Gray
                    Write-Host "$($deployment.sku.capacity) ($($deployment.sku.name))" -ForegroundColor White
                }
            }
            Write-Host ""
        }
    }
    else {
        Write-Host "No models deployed yet" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To deploy models, visit: https://ai.azure.com" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Environment Variables (.env format)" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "AI_FOUNDRY_PROJECT_ENDPOINT=$($FoundryInfo.Endpoint)/api/projects/$($FoundryInfo.ProjectName)" -ForegroundColor White
    Write-Host "AI_FOUNDRY_NAME=$($FoundryInfo.Name)" -ForegroundColor White
    Write-Host "AZURE_PROJECT_NAME=$($FoundryInfo.ProjectName)" -ForegroundColor White
    Write-Host "AZURE_OPENAI_BASE_URL_ENDPOINT=$($FoundryInfo.Endpoint)" -ForegroundColor White
    Write-Host "AZURE_OPENAI_API_KEY=$($FoundryInfo.PrimaryKey)" -ForegroundColor White
    Write-Host "TENANT_ID=$TenantId" -ForegroundColor White
    Write-Host "AZURE_SUBSCRIPTION_ID=$SubscriptionId" -ForegroundColor White
    Write-Host "AZURE_RESOURCE_GROUP=$($FoundryInfo.ResourceGroup)" -ForegroundColor White
    
    if ($FoundryInfo.Deployments) {
        Write-Host ""
        Write-Host "# Model-specific endpoints (update deployment names as needed):" -ForegroundColor Gray
        
        # Find common deployments
        $gpt4o = $FoundryInfo.Deployments | Where-Object { $_.name -like "*gpt-4o*" -and $_.name -notlike "*mini*" } | Select-Object -First 1
        $gpt4oMini = $FoundryInfo.Deployments | Where-Object { $_.name -like "*gpt-4o-mini*" } | Select-Object -First 1
        $embedding3Large = $FoundryInfo.Deployments | Where-Object { $_.name -like "*embedding-3-large*" } | Select-Object -First 1
        $embeddingAda = $FoundryInfo.Deployments | Where-Object { $_.name -like "*embedding-ada*" } | Select-Object -First 1
        
        if ($gpt4o) {
            Write-Host "MODEL_DEPLOYMENT_NAME=$($gpt4o.name)" -ForegroundColor White
            Write-Host "AZURE_OPENAI_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($gpt4o.name)/chat/completions?api-version=2025-01-01-preview" -ForegroundColor White
        }
        
        if ($embedding3Large) {
            Write-Host "EMBEDDING_MODEL_DEPLOYMENT_NAME=$($embedding3Large.name)" -ForegroundColor White
            Write-Host "AZURE_OPENAI_EMBEDDING_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($embedding3Large.name)/embeddings?api-version=2023-05-15" -ForegroundColor White
        }
        
        if ($embeddingAda) {
            Write-Host "EMBEDDING_ADA_MODEL_DEPLOYMENT_NAME=$($embeddingAda.name)" -ForegroundColor White
            Write-Host "AZURE_OPENAI_EMBEDDING_ADA_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($embeddingAda.name)/embeddings?api-version=2023-05-15" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Success "Information displayed successfully!"
    Write-Host ""
}

# Export information to .env file
function Export-FoundryEnvFile {
    param(
        [hashtable]$FoundryInfo,
        [string]$SubscriptionId,
        [string]$TenantId,
        [string]$OutputPath = ".\.env"
    )
    
    Write-Header "Exporting to .env File"
    
    try {
        # In Azure Cloud Shell, the recommended writable/persistent location is ~/clouddrive
        $cloudShellDrive = Join-Path -Path $HOME -ChildPath "clouddrive"
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or $OutputPath -eq ".\\.env") {
            if (Test-Path -Path $cloudShellDrive -PathType Container) {
                $OutputPath = Join-Path -Path $cloudShellDrive -ChildPath ".env"
            }
        }

        # If user provided a directory, write .env inside it
        if (Test-Path -Path $OutputPath -PathType Container) {
            $OutputPath = Join-Path -Path $OutputPath -ChildPath ".env"
        }

        # If it looks like a directory path (trailing slash), write .env inside it
        if ($OutputPath.EndsWith("/") -or $OutputPath.EndsWith("\\")) {
            $OutputPath = Join-Path -Path $OutputPath -ChildPath ".env"
        }

        # Ensure parent directory exists
        $parentDir = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -Path $parentDir -PathType Container)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        $envContent = @"
# Azure AI Foundry Configuration
# Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

AI_FOUNDRY_PROJECT_ENDPOINT=$($FoundryInfo.Endpoint)/api/projects/$($FoundryInfo.ProjectName)
AI_FOUNDRY_NAME=$($FoundryInfo.Name)
AZURE_PROJECT_NAME=$($FoundryInfo.ProjectName)
AZURE_OPENAI_BASE_URL_ENDPOINT=$($FoundryInfo.Endpoint)
AZURE_OPENAI_API_KEY=$($FoundryInfo.PrimaryKey)
TENANT_ID=$TenantId
AZURE_SUBSCRIPTION_ID=$SubscriptionId
AZURE_RESOURCE_GROUP=$($FoundryInfo.ResourceGroup)
"@
        
        # Add model-specific endpoints if available
        if ($FoundryInfo.Deployments) {
            $gpt4o = $FoundryInfo.Deployments | Where-Object { $_.name -like "*gpt-4o*" -and $_.name -notlike "*mini*" } | Select-Object -First 1
            $embedding3Large = $FoundryInfo.Deployments | Where-Object { $_.name -like "*embedding-3-large*" } | Select-Object -First 1
            $embeddingAda = $FoundryInfo.Deployments | Where-Object { $_.name -like "*embedding-ada*" } | Select-Object -First 1
            
            if ($gpt4o) {
                $envContent += "`nMODEL_DEPLOYMENT_NAME=$($gpt4o.name)"
                $envContent += "`nAZURE_OPENAI_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($gpt4o.name)/chat/completions?api-version=2025-01-01-preview"
                $envContent += "`nMODEL_API_VERSION=2025-01-01-preview"
            }
            
            if ($embedding3Large) {
                $envContent += "`nEMBEDDING_MODEL_DEPLOYMENT_NAME=$($embedding3Large.name)"
                $envContent += "`nAZURE_OPENAI_EMBEDDING_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($embedding3Large.name)/embeddings?api-version=2023-05-15"
                $envContent += "`nEMBEDDING_MODEL_API_VERSION=2023-05-15"
                $envContent += "`nAZURE_OPENAI_EMBEDDING_API_KEY=$($FoundryInfo.PrimaryKey)"
            }
            
            if ($embeddingAda) {
                $envContent += "`nEMBEDDING_ADA_MODEL_DEPLOYMENT_NAME=$($embeddingAda.name)"
                $envContent += "`nAZURE_OPENAI_EMBEDDING_ADA_ENDPOINT=$($FoundryInfo.Endpoint)/openai/deployments/$($embeddingAda.name)/embeddings?api-version=2023-05-15"
                $envContent += "`nEMBEDDING_ADA_MODEL_API_VERSION=2023-05-15"
                $envContent += "`nAZURE_OPENAI_EMBEDDING_ADA_API_KEY=$($FoundryInfo.PrimaryKey)"
            }
        }
        
        $envContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
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
        Write-Host "║          Azure AI Foundry Information Script                   ║" -ForegroundColor Blue
        Write-Host "║          Retrieve and Display Resource Information            ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Get AI Foundry information
        $foundryInfo = Get-AIFoundryInformation `
            -FoundryName $FoundryName `
            -ProjectName $ProjectName `
            -ResourceGroupName $ResourceGroupName
        
        if (-not $foundryInfo) {
            Write-Error "Could not retrieve AI Foundry information"
            exit 1
        }
        
        # Display information
        Show-FoundryInformation `
            -FoundryInfo $foundryInfo `
            -SubscriptionId $accountInfo.id `
            -TenantId $accountInfo.tenantId
        
        # Ask if user wants to export
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Info "Would you like to export this information to a .env file? (Y/N)"
        $response = Read-Host
        
        if ($response -eq 'Y' -or $response -eq 'y') {
            $defaultOutputPath = ".\\.env"
            $cloudShellDrive = Join-Path -Path $HOME -ChildPath "clouddrive"
            if (Test-Path -Path $cloudShellDrive -PathType Container) {
                $defaultOutputPath = Join-Path -Path $cloudShellDrive -ChildPath ".env"
            }

            $outputPath = Read-Host "Enter output path (default: $defaultOutputPath)"
            if ([string]::IsNullOrWhiteSpace($outputPath)) {
                $outputPath = $defaultOutputPath
            }
            Export-FoundryEnvFile `
                -FoundryInfo $foundryInfo `
                -SubscriptionId $accountInfo.id `
                -TenantId $accountInfo.tenantId `
                -OutputPath $outputPath
        }
        
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  Complete!" -ForegroundColor Green
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
