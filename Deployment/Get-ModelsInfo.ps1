<#
.SYNOPSIS
    Retrieve deployed model information from Azure AI Foundry/Cognitive Services account

.DESCRIPTION
    This script retrieves and displays information about all models deployed to an 
    Azure AI Foundry or Cognitive Services account, including:
    - Deployment names
    - Model names and versions
    - Capacity (TPM - Tokens Per Minute)
    - SKU information
    - Model format
    - Provisioning state
    
    Note: Models are deployed at the hub (Cognitive Services account) level and are
    accessible by all projects under that hub.

.PARAMETER ResourceGroupName
    The name of the resource group containing the AI Foundry account (Required)

.PARAMETER FoundryName
    The name of the AI Foundry/Cognitive Services account (Required)

.PARAMETER ExportToFile
    Optional path to export model information to a JSON file

.PARAMETER ShowJson
    Display raw JSON output instead of formatted display

.EXAMPLE
    .\Get-ModelsInfo.ps1 -ResourceGroupName "WPLUS-Foundry" -FoundryName "myopenAI-wplus"
    
    Displays all deployed models with formatted output

.EXAMPLE
    .\Get-ModelsInfo.ps1 -ResourceGroupName "WPLUS-Foundry" -FoundryName "myopenAI-wplus" -ExportToFile "models.json"
    
    Displays model information and exports to JSON file

.EXAMPLE
    .\Get-ModelsInfo.ps1 -ResourceGroupName "WPLUS-Foundry" -FoundryName "myopenAI-wplus" -ShowJson
    
    Displays raw JSON output of all models

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - AI Foundry/Cognitive Services account must exist
    - Appropriate permissions to read account information
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true, HelpMessage="AI Foundry/Cognitive Services account name")]
    [string]$FoundryName,
    
    [Parameter(Mandatory=$false, HelpMessage="Export model information to JSON file")]
    [string]$ExportToFile,
    
    [Parameter(Mandatory=$false, HelpMessage="Display raw JSON output")]
    [switch]$ShowJson
)

# Import common functions
$commonFunctionsPath = Join-Path $PSScriptRoot "Common-Functions.ps1"
if (Test-Path $commonFunctionsPath) {
    . $commonFunctionsPath
}
else {
    Write-Host "Error: Common-Functions.ps1 not found at: $commonFunctionsPath" -ForegroundColor Red
    Write-Host "Please ensure Common-Functions.ps1 is in the same directory as this script." -ForegroundColor Yellow
    exit 1
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
        Write-Info "Please verify the account name and resource group"
        exit 1
    }
}

# Get deployed models
function Get-DeployedModels {
    Write-Header "Retrieving Deployed Models"
    
    Write-Info "Querying model deployments..."
    try {
        $deployments = az cognitiveservices account deployment list `
            --name $FoundryName `
            --resource-group $ResourceGroupName `
            --output json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve deployments: $deployments"
        }
        
        $deploymentsObj = $deployments | ConvertFrom-Json
        
        if (!$deploymentsObj -or $deploymentsObj.Count -eq 0) {
            Write-Warning "No models are currently deployed to this account"
            return @()
        }
        
        Write-Success "Found $($deploymentsObj.Count) deployed model(s)"
        return $deploymentsObj
    }
    catch {
        Write-ErrorMsg "Failed to retrieve deployed models: $_"
        exit 1
    }
}

# Display model information in formatted view
function Show-ModelInformation {
    param(
        [array]$Models,
        [object]$FoundryAccount
    )
    
    Write-Header "Deployed Models Information"
    
    Write-Host ""
    Write-Host "AI Foundry Hub:      " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryAccount.name -ForegroundColor White
    
    Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
    Write-Host $ResourceGroupName -ForegroundColor White
    
    Write-Host "Location:            " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryAccount.location -ForegroundColor White
    
    Write-Host "Endpoint:            " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryAccount.properties.endpoint -ForegroundColor White
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($Models.Count -eq 0) {
        Write-Warning "No models deployed"
        return
    }
    
    $modelNumber = 1
    foreach ($model in $Models) {
        Write-Host "Model #$modelNumber" -ForegroundColor Cyan
        Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        
        Write-Host "  Deployment Name:   " -NoNewline -ForegroundColor Gray
        Write-Host $model.name -ForegroundColor White
        
        Write-Host "  Model:             " -NoNewline -ForegroundColor Gray
        Write-Host "$($model.properties.model.name) (v$($model.properties.model.version))" -ForegroundColor White
        
        Write-Host "  Format:            " -NoNewline -ForegroundColor Gray
        Write-Host $model.properties.model.format -ForegroundColor White
        
        Write-Host "  SKU:               " -NoNewline -ForegroundColor Gray
        Write-Host $model.sku.name -ForegroundColor White
        
        Write-Host "  Capacity (TPM):    " -NoNewline -ForegroundColor Gray
        Write-Host $model.sku.capacity -ForegroundColor White
        
        Write-Host "  State:             " -NoNewline -ForegroundColor Gray
        $state = $model.properties.provisioningState
        if ($state -eq "Succeeded") {
            Write-Host $state -ForegroundColor Green
        }
        elseif ($state -eq "Failed") {
            Write-Host $state -ForegroundColor Red
        }
        else {
            Write-Host $state -ForegroundColor Yellow
        }
        
        # Show call rate limit if available
        if ($model.properties.callRateLimit) {
            Write-Host "  Rate Limit:        " -NoNewline -ForegroundColor Gray
            Write-Host "$($model.properties.callRateLimit.count) per $($model.properties.callRateLimit.renewalPeriod) seconds" -ForegroundColor White
        }
        
        # Show endpoint for this deployment
        $deploymentEndpoint = "$($FoundryAccount.properties.endpoint.TrimEnd('/'))/openai/deployments/$($model.name)"
        Write-Host "  Endpoint:          " -NoNewline -ForegroundColor Gray
        Write-Host $deploymentEndpoint -ForegroundColor DarkCyan
        
        Write-Host ""
        $modelNumber++
    }
}

# Display summary statistics
function Show-ModelSummary {
    param(
        [array]$Models
    )
    
    if ($Models.Count -eq 0) {
        return
    }
    
    Write-Header "Model Summary"
    
    # Group by model type
    $chatModels = $Models | Where-Object { $_.properties.model.name -like "*gpt*" }
    $embeddingModels = $Models | Where-Object { $_.properties.model.name -like "*embedding*" }
    $otherModels = $Models | Where-Object { $_.properties.model.name -notlike "*gpt*" -and $_.properties.model.name -notlike "*embedding*" }
    
    Write-Host ""
    Write-Host "Total Models:        " -NoNewline -ForegroundColor Gray
    Write-Host $Models.Count -ForegroundColor White
    
    if ($chatModels.Count -gt 0) {
        Write-Host "Chat Models:         " -NoNewline -ForegroundColor Gray
        Write-Host $chatModels.Count -ForegroundColor White
        foreach ($m in $chatModels) {
            Write-Host "  → $($m.name) [$($m.properties.model.name) v$($m.properties.model.version)]" -ForegroundColor Cyan
        }
    }
    
    if ($embeddingModels.Count -gt 0) {
        Write-Host "Embedding Models:    " -NoNewline -ForegroundColor Gray
        Write-Host $embeddingModels.Count -ForegroundColor White
        foreach ($m in $embeddingModels) {
            Write-Host "  → $($m.name) [$($m.properties.model.name) v$($m.properties.model.version)]" -ForegroundColor Cyan
        }
    }
    
    if ($otherModels.Count -gt 0) {
        Write-Host "Other Models:        " -NoNewline -ForegroundColor Gray
        Write-Host $otherModels.Count -ForegroundColor White
        foreach ($m in $otherModels) {
            Write-Host "  → $($m.name) [$($m.properties.model.name) v$($m.properties.model.version)]" -ForegroundColor Cyan
        }
    }
    
    # Total capacity
    $totalCapacity = ($Models | Measure-Object -Property { $_.sku.capacity } -Sum).Sum
    Write-Host ""
    Write-Host "Total TPM Capacity:  " -NoNewline -ForegroundColor Gray
    Write-Host $totalCapacity -ForegroundColor White
    
    Write-Host ""
}

# Generate environment variables for models
function Show-EnvironmentVariables {
    param(
        [array]$Models,
        [object]$FoundryAccount
    )
    
    Write-Header "Environment Variables (.env format)"
    
    $endpoint = $FoundryAccount.properties.endpoint.TrimEnd('/')
    
    Write-Host ""
    Write-Host "# Base Configuration" -ForegroundColor DarkGray
    Write-Host "AZURE_OPENAI_ENDPOINT=$endpoint"
    Write-Host ""
    
    foreach ($model in $Models) {
        $deploymentName = $model.name
        $modelName = $model.properties.model.name
        $modelVersion = $model.properties.model.version
        
        # Determine model type and suggest environment variable names
        if ($modelName -like "*gpt-4o*" -and $modelName -notlike "*mini*") {
            Write-Host "# GPT-4o Model" -ForegroundColor DarkGray
            Write-Host "MODEL_DEPLOYMENT_NAME=$deploymentName"
            Write-Host "MODEL_NAME=$modelName"
            Write-Host "MODEL_VERSION=$modelVersion"
            Write-Host "AZURE_OPENAI_CHAT_ENDPOINT=$endpoint/openai/deployments/$deploymentName/chat/completions?api-version=2024-02-15-preview"
        }
        elseif ($modelName -like "*gpt-4o-mini*") {
            Write-Host "# GPT-4o-mini Model" -ForegroundColor DarkGray
            Write-Host "MODEL_MINI_DEPLOYMENT_NAME=$deploymentName"
            Write-Host "MODEL_MINI_NAME=$modelName"
            Write-Host "MODEL_MINI_VERSION=$modelVersion"
            Write-Host "AZURE_OPENAI_CHAT_MINI_ENDPOINT=$endpoint/openai/deployments/$deploymentName/chat/completions?api-version=2024-02-15-preview"
        }
        elseif ($modelName -like "*text-embedding-3-large*") {
            Write-Host "# Text Embedding 3 Large Model" -ForegroundColor DarkGray
            Write-Host "EMBEDDING_DEPLOYMENT_NAME=$deploymentName"
            Write-Host "EMBEDDING_MODEL_NAME=$modelName"
            Write-Host "EMBEDDING_MODEL_VERSION=$modelVersion"
            Write-Host "AZURE_OPENAI_EMBEDDING_ENDPOINT=$endpoint/openai/deployments/$deploymentName/embeddings?api-version=2023-05-15"
        }
        elseif ($modelName -like "*text-embedding-ada-002*") {
            Write-Host "# Text Embedding Ada 002 Model" -ForegroundColor DarkGray
            Write-Host "EMBEDDING_ADA_DEPLOYMENT_NAME=$deploymentName"
            Write-Host "EMBEDDING_ADA_MODEL_NAME=$modelName"
            Write-Host "EMBEDDING_ADA_MODEL_VERSION=$modelVersion"
            Write-Host "AZURE_OPENAI_EMBEDDING_ADA_ENDPOINT=$endpoint/openai/deployments/$deploymentName/embeddings?api-version=2023-05-15"
        }
        else {
            Write-Host "# $modelName Model" -ForegroundColor DarkGray
            $safeName = $deploymentName -replace '[^a-zA-Z0-9]', '_'
            Write-Host "${safeName}_DEPLOYMENT_NAME=$deploymentName"
            Write-Host "${safeName}_MODEL_NAME=$modelName"
            Write-Host "${safeName}_MODEL_VERSION=$modelVersion"
        }
        Write-Host ""
    }
}

# Export to JSON file
function Export-ModelInformation {
    param(
        [array]$Models,
        [object]$FoundryAccount,
        [string]$FilePath
    )
    
    Write-Header "Exporting to File"
    
    $exportData = @{
        FoundryAccount = @{
            Name = $FoundryAccount.name
            ResourceGroup = $ResourceGroupName
            Location = $FoundryAccount.location
            Endpoint = $FoundryAccount.properties.endpoint
            Kind = $FoundryAccount.kind
            SKU = $FoundryAccount.sku.name
        }
        Models = $Models
        ExportedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        TotalModels = $Models.Count
    }
    
    try {
        $exportData | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
        Write-Success "Model information exported to: $FilePath"
        Write-Info "File size: $((Get-Item $FilePath).Length) bytes"
    }
    catch {
        Write-ErrorMsg "Failed to export to file: $_"
    }
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Show-ScriptBanner -Title "AI Models Information Retrieval Script"
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Verify AI Foundry account exists
        $foundryAccount = Test-FoundryAccount
        
        # Get deployed models
        $models = Get-DeployedModels
        
        if ($ShowJson) {
            # Display raw JSON
            Write-Header "Raw JSON Output"
            $models | ConvertTo-Json -Depth 10
        }
        else {
            # Display formatted information
            Show-ModelInformation -Models $models -FoundryAccount $foundryAccount
            Show-ModelSummary -Models $models
            Show-EnvironmentVariables -Models $models -FoundryAccount $foundryAccount
        }
        
        # Export to file if requested
        if ($ExportToFile) {
            Export-ModelInformation -Models $models -FoundryAccount $foundryAccount -FilePath $ExportToFile
        }
        
        Write-Host ""
        Write-Success "Model information retrieval completed!"
        Write-Host ""
        
    }
    catch {
        Write-ErrorMsg "An error occurred: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        exit 1
    }
}

# Run the script
Main
