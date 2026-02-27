<#
.SYNOPSIS
    Consolidated lab-restore script: deploys AI Foundry, connects Bing Grounding
    and Azure AI Search, and prints all .env variables at the end.

.DESCRIPTION
    This script combines the functionality of:
      - Deploy-Foundry.ps1   (Foundry account + project + model deployments)
      - Connect-BingToFoundry.ps1  (Bing Grounding connection)
      - Connect-AISearch.ps1       (Azure AI Search connection)

    At the end it prints a single consolidated block of .env variables.

.PARAMETER ResourceGroupName
    Resource group that contains (or will contain) all resources (required)

.PARAMETER FoundryName
    Name of the AI Foundry (Cognitive Services) account (required)

.PARAMETER ProjectName
    Name of the project under the Foundry account (default: firstProject)

.PARAMETER Location
    Azure region (default: eastus2)

.PARAMETER DeployModels
    Whether to deploy the default model set (default: true)

.PARAMETER Models
    Custom array of model definitions. When omitted the script uses a built-in
    default set (gpt-4o, gpt-4o-mini, text-embedding-3-large, text-embedding-ada-002).

.PARAMETER SkipBing
    Skip the Bing Grounding connection step

.PARAMETER SkipAISearch
    Skip the Azure AI Search connection step

.EXAMPLE
    .\RestoreLab.ps1 -ResourceGroupName "azureaiworkshoprg" -FoundryName "ai-foundry-59483770"

.EXAMPLE
    .\RestoreLab.ps1 -ResourceGroupName "myRG" -FoundryName "myFoundry" -ProjectName "demo" -SkipBing

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to manage Cognitive Services, Search and Bing resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName ="azureaiworkshoprg",

    [Parameter(Mandatory=$true)]
    [string]$FoundryName = "ai-foundry-59483770",

    [Parameter(Mandatory=$false)]
    [string]$ProjectName = "firstProject",

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [bool]$DeployModels = $true,

    [Parameter(Mandatory=$false)]
    [array]$Models,

    [Parameter(Mandatory=$false)]
    [switch]$SkipBing,

    [Parameter(Mandatory=$false)]
    [switch]$SkipAISearch
)

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Helper functions                                                         ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Write-Success  { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Info     { Write-Host "→ $args" -ForegroundColor Cyan }
function Write-Warn     { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-ErrorMsg { Write-Host "✗ $args" -ForegroundColor Red }

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "  $Message" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Phase {
    param([string]$Phase, [string]$Title)
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Blue
    Write-Host "│  $Phase – $($Title.PadRight(50 - $Phase.Length))│" -ForegroundColor Blue
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Blue
    Write-Host ""
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Phase 0 – Prerequisites                                                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Test-LabPrerequisites {
    Write-Header "Checking Prerequisites"

    Write-Info "Checking Azure CLI installation..."
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        Write-Success "Azure CLI installed (version: $($azVersion.'azure-cli'))"
    }
    catch {
        Write-ErrorMsg "Azure CLI is not installed. Install from: https://aka.ms/installazurecliwindows"
        throw "Azure CLI required"
    }

    Write-Info "Checking Azure login..."
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if (-not $account) { throw "not logged in" }
        Write-Success "Logged in (Subscription: $($account.name))"
        return $account
    }
    catch {
        Write-ErrorMsg "Not logged in. Run: az login"
        throw "Azure login required"
    }
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Phase 1 – Deploy AI Foundry (account + project + models)                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function New-AIFoundryResource {
    param(
        [string]$FoundryName,
        [string]$ProjectName,
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$SubscriptionId
    )

    Write-Header "Creating Azure AI Foundry Account"
    Write-Info "Account:  $FoundryName"
    Write-Info "Project:  $ProjectName"
    Write-Info "Location: $Location"

    $apiVersion = "2025-06-01"
    $accountUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/${FoundryName}?api-version=$apiVersion"

    # Check existence
    $existingFoundry = $null
    try { $existingFoundry = az rest --method get --uri $accountUri --output json 2>$null | ConvertFrom-Json } catch {}

    if ($existingFoundry -and $existingFoundry.name) {
        Write-Warn "Account '$FoundryName' already exists"

        if ($existingFoundry.properties.allowProjectManagement -ne $true) {
            Write-Info "Enabling native project management..."
            $patchBody = @{
                properties = @{
                    allowProjectManagement = $true
                    defaultProject         = $ProjectName
                    associatedProjects     = @( $ProjectName )
                }
            } | ConvertTo-Json -Depth 5

            $patchFile = [System.IO.Path]::GetTempFileName()
            $patchBody | Out-File -FilePath $patchFile -Encoding UTF8 -Force
            try {
                az rest --method patch --uri $accountUri --body "@$patchFile" --headers "Content-Type=application/json" --output none 2>&1 | Out-Null
                Write-Success "Project management enabled"
            }
            catch { Write-Warn "Could not patch account: $_" }
            finally { Remove-Item -Path $patchFile -Force -ErrorAction SilentlyContinue }
        }
    }
    else {
        Write-Info "Creating Cognitive Services account with native project management..."

        $accountBody = @{
            location   = $Location
            sku        = @{ name = "S0" }
            kind       = "AIServices"
            identity   = @{ type = "SystemAssigned" }
            properties = @{
                apiProperties          = @{}
                customSubDomainName    = $FoundryName
                networkAcls            = @{ defaultAction = "Allow"; virtualNetworkRules = @(); ipRules = @() }
                allowProjectManagement = $true
                defaultProject         = $ProjectName
                associatedProjects     = @( $ProjectName )
                publicNetworkAccess    = "Enabled"
            }
        } | ConvertTo-Json -Depth 5

        $accountFile = [System.IO.Path]::GetTempFileName()
        $accountBody | Out-File -FilePath $accountFile -Encoding UTF8 -Force

        try {
            $result = az rest --method put --uri $accountUri --body "@$accountFile" --headers "Content-Type=application/json" --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Account creation failed: $result" }
            $existingFoundry = $result | ConvertFrom-Json
            Write-Success "AI Foundry account created"
        }
        catch { Write-ErrorMsg "Failed to create account: $_"; throw }
        finally { Remove-Item -Path $accountFile -Force -ErrorAction SilentlyContinue }

        Write-Info "Waiting for provisioning..."
        Start-Sleep -Seconds 15
    }

    # ── Project ──
    $projectUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects/${ProjectName}?api-version=$apiVersion"
    $existingProject = $null
    try { $existingProject = az rest --method get --uri $projectUri --output json 2>$null | ConvertFrom-Json } catch {}

    if ($existingProject -and $existingProject.name) {
        Write-Warn "Project '$ProjectName' already exists"
    }
    else {
        Write-Info "Creating project '$ProjectName'..."
        $projectBody = @{
            location   = $Location
            kind       = "AIServices"
            identity   = @{ type = "SystemAssigned" }
            properties = @{ description = "Default project"; displayName = $ProjectName }
        } | ConvertTo-Json -Depth 5

        $projectFile = [System.IO.Path]::GetTempFileName()
        $projectBody | Out-File -FilePath $projectFile -Encoding UTF8 -Force

        try {
            $result = az rest --method put --uri $projectUri --body "@$projectFile" --headers "Content-Type=application/json" --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Project creation failed: $result" }
            Write-Success "Project '$ProjectName' created"
        }
        catch { Write-Warn "Could not create project: $_" }
        finally { Remove-Item -Path $projectFile -Force -ErrorAction SilentlyContinue }
    }

    return @{ FoundryName = $FoundryName; ProjectName = $ProjectName; Location = $Location }
}

function Get-DefaultModels {
    return @(
        @{ Name = "GPT-4o";                  DeploymentName = "gpt-4o";                  ModelName = "gpt-4o";                  Version = "2024-11-20"; Capacity = 100 },
        @{ Name = "GPT-4o-mini";             DeploymentName = "gpt-4o-mini";             ModelName = "gpt-4o-mini";             Version = "2024-07-18"; Capacity = 250 },
        @{ Name = "Text Embedding 3 Large";  DeploymentName = "text-embedding-3-large";  ModelName = "text-embedding-3-large";  Version = "1";          Capacity = 150 },
        @{ Name = "Text Embedding Ada 002";  DeploymentName = "text-embedding-ada-002";  ModelName = "text-embedding-ada-002";  Version = "2";          Capacity = 150 }
    )
}

function Deploy-AIModels {
    param(
        [string]$FoundryName,
        [string]$ResourceGroupName,
        [array]$ModelsToDeploy
    )

    Write-Header "Deploying AI Models"

    $deployed = @(); $skipped = @(); $failed = @()

    foreach ($model in $ModelsToDeploy) {
        Write-Info "Deploying: $($model.Name)  ($($model.DeploymentName), v$($model.Version), $($model.Capacity) TPM)"

        $existing = az cognitiveservices account deployment show `
            --name $FoundryName --resource-group $ResourceGroupName `
            --deployment-name $model.DeploymentName 2>$null | ConvertFrom-Json

        if ($existing) {
            Write-Warn "Already deployed – skipping"
            $skipped += $model; $deployed += $existing; continue
        }

        try {
            $dep = az cognitiveservices account deployment create `
                --name $FoundryName --resource-group $ResourceGroupName `
                --deployment-name $model.DeploymentName `
                --model-name $model.ModelName --model-version $model.Version `
                --model-format OpenAI --sku-capacity $model.Capacity --sku-name "Standard" `
                --output json 2>&1

            if ($LASTEXITCODE -ne 0) { throw $dep }
            $deployed += ($dep | ConvertFrom-Json)
            Write-Success "$($model.DeploymentName) deployed"
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Warn "Could not deploy $($model.DeploymentName): $_"
            $failed += $model
        }
    }

    return @{ Deployed = $deployed; Skipped = $skipped; Failed = $failed }
}

function Get-AIFoundryInfo {
    param([string]$FoundryName, [string]$ResourceGroupName)

    try {
        $acct = az cognitiveservices account show --name $FoundryName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        $keys = az cognitiveservices account keys list --name $FoundryName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        return @{
            Endpoint     = $acct.properties.endpoint
            PrimaryKey   = $keys.key1
            Location     = $acct.location
            Kind         = $acct.kind
            Sku          = $acct.sku.name
        }
    }
    catch { return $null }
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Phase 2 – Connect Bing Grounding                                         ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Find-BingResource {
    param([string]$ResourceGroupName)

    Write-Info "Looking for Bing resources..."
    $cogAccounts = az cognitiveservices account list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    $bingAccounts = @()
    if ($cogAccounts) {
        $bingAccounts = @($cogAccounts | Where-Object { $_.kind -like "Bing.Search*" })
    }

    if ($bingAccounts.Count -eq 0) {
        $bingResources = az resource list --resource-group $ResourceGroupName --resource-type "Microsoft.Bing/accounts" --output json 2>$null | ConvertFrom-Json
        if ($bingResources -and $bingResources.Count -gt 0) {
            foreach ($br in $bingResources) {
                $bingAccounts += @{ name = $br.name; id = $br.id; kind = "Bing.Search"; location = $br.location; properties = @{ endpoint = "https://api.bing.microsoft.com/" } }
            }
        }
    }

    if ($bingAccounts.Count -eq 0) { return $null }
    if ($bingAccounts.Count -gt 1) { Write-Warn "Multiple Bing resources found – using the first one" }
    return $bingAccounts[0]
}

function Get-BingKeys {
    param([string]$BingName, [string]$ResourceGroupName)

    try {
        $keys = az cognitiveservices account keys list --name $BingName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        if ($keys -and $keys.key1) { return $keys }
    } catch {}

    try {
        $sub = (az account show --output json 2>$null | ConvertFrom-Json).id
        $uri = "/subscriptions/$sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Bing/accounts/$BingName/listKeys?api-version=2020-06-10"
        $keys = az rest --method post --uri $uri --output json 2>$null | ConvertFrom-Json
        if ($keys -and $keys.key1) { return $keys }
    } catch {}

    return $null
}

function Add-BingConnection {
    param(
        [string]$SubscriptionId, [string]$ResourceGroupName, [string]$FoundryName,
        [string]$ConnectionName, [string]$BingResourceId, [string]$BingApiKey, [string]$BingLocation
    )

    $apiVersion = "2025-06-01"
    $connUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/connections/${ConnectionName}?api-version=$apiVersion"

    $body = @{
        properties = @{
            category      = "BingLLMSearch"
            target        = "https://api.bing.microsoft.com/"
            authType      = "ApiKey"
            isSharedToAll = $true
            credentials   = @{ key = $BingApiKey }
            metadata      = @{ ResourceId = $BingResourceId; Location = $BingLocation }
        }
    } | ConvertTo-Json -Depth 5

    $bodyFile = [System.IO.Path]::GetTempFileName()
    $body | Out-File -FilePath $bodyFile -Encoding UTF8 -Force

    try {
        $result = az rest --method put --uri $connUri --body "@$bodyFile" --headers "Content-Type=application/json" --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "REST call failed: $result" }
        $conn = $result | ConvertFrom-Json
        Write-Success "Bing connection '$ConnectionName' created"
        return $conn
    }
    catch { Write-ErrorMsg "Failed to create Bing connection: $_"; return $null }
    finally { Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue }
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Phase 3 – Connect AI Search                                              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Find-AISearchResource {
    param([string]$ResourceGroupName)

    Write-Info "Looking for Azure AI Search services..."
    $searchServices = az resource list --resource-group $ResourceGroupName --resource-type "Microsoft.Search/searchServices" --output json 2>$null | ConvertFrom-Json
    if (-not $searchServices -or $searchServices.Count -eq 0) { return $null }
    if ($searchServices.Count -gt 1) { Write-Warn "Multiple Search services found – using the first one" }
    return $searchServices[0]
}

function Get-SearchKeys {
    param([string]$SearchName, [string]$ResourceGroupName)

    try {
        $keys = az search admin-key show --service-name $SearchName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        if ($keys -and $keys.primaryKey) { return $keys }
    } catch {}

    try {
        $sub = (az account show --output json 2>$null | ConvertFrom-Json).id
        $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/$SearchName/listAdminKeys?api-version=2025-05-01"
        $keys = az rest --method post --uri $uri --output json 2>$null | ConvertFrom-Json
        if ($keys -and $keys.primaryKey) { return $keys }
    } catch {}

    return $null
}

function Add-AISearchConnection {
    param(
        [string]$SubscriptionId, [string]$ResourceGroupName, [string]$FoundryName,
        [string]$ConnectionName, [string]$SearchResourceId, [string]$SearchEndpoint,
        [string]$SearchApiKey, [string]$SearchLocation
    )

    $apiVersion = "2025-06-01"
    $connUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/connections/${ConnectionName}?api-version=$apiVersion"

    $body = @{
        properties = @{
            category      = "CognitiveSearch"
            target        = $SearchEndpoint
            authType      = "ApiKey"
            isSharedToAll = $true
            credentials   = @{ key = $SearchApiKey }
            metadata      = @{ ResourceId = $SearchResourceId; Location = $SearchLocation }
        }
    } | ConvertTo-Json -Depth 5

    $bodyFile = [System.IO.Path]::GetTempFileName()
    $body | Out-File -FilePath $bodyFile -Encoding UTF8 -Force

    try {
        $result = az rest --method put --uri $connUri --body "@$bodyFile" --headers "Content-Type=application/json" --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "REST call failed: $result" }
        $conn = $result | ConvertFrom-Json
        Write-Success "AI Search connection '$ConnectionName' created"
        return $conn
    }
    catch { Write-ErrorMsg "Failed to create AI Search connection: $_"; return $null }
    finally { Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue }
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Sanitise a connection name                                                ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Format-ConnectionName {
    param([string]$Name)
    $Name = ($Name -replace '[^a-zA-Z0-9_-]', '-').TrimStart('-')
    if ($Name.Length -gt 33) { $Name = $Name.Substring(0, 33) }
    if ($Name.Length -lt 3)  { $Name = $Name.PadRight(3, '0') }
    return $Name
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Main                                                                      ║
# ╚════════════════════════════════════════════════════════════════════════════╝

function Main {
    try {
        $ErrorActionPreference = "Stop"

        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║          RestoreLab – Full Lab Environment Setup               ║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""

        # ── 0  Prerequisites ────────────────────────────────────────────────
        $accountInfo = Test-LabPrerequisites
        $subscriptionId = $accountInfo.id

        Write-Header "Verifying Resource Group"
        $rgExists = az group exists --name $ResourceGroupName
        if ($rgExists -ne "true") { Write-ErrorMsg "Resource group '$ResourceGroupName' does not exist"; exit 1 }
        Write-Success "Resource group '$ResourceGroupName' exists"

        # Collect .env values as we go
        $envVars = [ordered]@{}

        # ── 1  Deploy Foundry ───────────────────────────────────────────────
        Write-Phase "Phase 1" "Deploy AI Foundry (Account + Project + Models)"

        $null = New-AIFoundryResource `
            -FoundryName $FoundryName -ProjectName $ProjectName `
            -ResourceGroupName $ResourceGroupName -Location $Location `
            -SubscriptionId $subscriptionId

        $foundryInfo = Get-AIFoundryInfo -FoundryName $FoundryName -ResourceGroupName $ResourceGroupName

        if ($foundryInfo) {
            $envVars["AZURE_OPENAI_ENDPOINT"]        = $foundryInfo.Endpoint
            $envVars["AZURE_OPENAI_API_KEY"]         = $foundryInfo.PrimaryKey
            $envVars["TENANT_ID"]                    = $accountInfo.tenantId
            $envVars["AI_FOUNDRY_PROJECT_ENDPOINT"]  = "$($foundryInfo.Endpoint)/api/projects/$ProjectName"
        }

        # Model deployments
        $modelsResult = $null
        if ($DeployModels) {
            $modelsToDeploy = $Models
            if (-not $modelsToDeploy -or $modelsToDeploy.Count -eq 0) {
                Write-Info "Using default model set..."
                $modelsToDeploy = Get-DefaultModels
            }
            $modelsResult = Deploy-AIModels -FoundryName $FoundryName -ResourceGroupName $ResourceGroupName -ModelsToDeploy $modelsToDeploy
        }

        # Populate model-specific .env vars from deployed models (mirrors Get-ModelsInfo.ps1)
        if ($foundryInfo) {
            $endpoint = $foundryInfo.Endpoint.TrimEnd('/')

            $deployedModels = az cognitiveservices account deployment list `
                --name $FoundryName --resource-group $ResourceGroupName `
                --output json 2>$null | ConvertFrom-Json

            if ($deployedModels) {
                foreach ($model in $deployedModels) {
                    $deploymentName = $model.name
                    $modelName      = $model.properties.model.name
                    $modelVersion   = $model.properties.model.version

                    if ($modelName -like "*gpt-4o*" -and $modelName -notlike "*mini*") {
                        $envVars["MODEL_DEPLOYMENT_NAME"]         = $deploymentName
                        $envVars["MODEL_NAME"]                    = $modelName
                        $envVars["MODEL_VERSION"]                 = $modelVersion
                        $envVars["AZURE_OPENAI_CHAT_ENDPOINT"]    = "$endpoint/openai/deployments/$deploymentName/chat/completions?api-version=2024-02-15-preview"
                    }
                    elseif ($modelName -like "*gpt-4o-mini*") {
                        $envVars["MODEL_MINI_DEPLOYMENT_NAME"]         = $deploymentName
                        $envVars["MODEL_MINI_NAME"]                    = $modelName
                        $envVars["MODEL_MINI_VERSION"]                 = $modelVersion
                        $envVars["AZURE_OPENAI_CHAT_MINI_ENDPOINT"]    = "$endpoint/openai/deployments/$deploymentName/chat/completions?api-version=2024-02-15-preview"
                    }
                    elseif ($modelName -like "*text-embedding-3-large*") {
                        $envVars["EMBEDDING_DEPLOYMENT_NAME"]          = $deploymentName
                        $envVars["EMBEDDING_MODEL_NAME"]               = $modelName
                        $envVars["EMBEDDING_MODEL_VERSION"]            = $modelVersion
                        $envVars["AZURE_OPENAI_EMBEDDING_ENDPOINT"]    = "$endpoint/openai/deployments/$deploymentName/embeddings?api-version=2023-05-15"
                    }
                    elseif ($modelName -like "*text-embedding-ada-002*") {
                        $envVars["EMBEDDING_ADA_DEPLOYMENT_NAME"]          = $deploymentName
                        $envVars["EMBEDDING_ADA_MODEL_NAME"]               = $modelName
                        $envVars["EMBEDDING_ADA_MODEL_VERSION"]            = $modelVersion
                        $envVars["AZURE_OPENAI_EMBEDDING_ADA_ENDPOINT"]    = "$endpoint/openai/deployments/$deploymentName/embeddings?api-version=2023-05-15"
                    }
                    else {
                        $safeName = $deploymentName -replace '[^a-zA-Z0-9]', '_'
                        $envVars["${safeName}_DEPLOYMENT_NAME"] = $deploymentName
                        $envVars["${safeName}_MODEL_NAME"]      = $modelName
                        $envVars["${safeName}_MODEL_VERSION"]   = $modelVersion
                    }
                }
            }
        }

        # ── 2  Connect Bing ────────────────────────────────────────────────
        $bingConnectionName = $null
        if (-not $SkipBing) {
            Write-Phase "Phase 2" "Connect Bing Grounding"

            $bingResource = Find-BingResource -ResourceGroupName $ResourceGroupName
            if ($bingResource) {
                $bingName = $bingResource.name
                Write-Success "Found Bing resource: $bingName"

                $bingResourceId = $bingResource.id
                if (-not $bingResourceId) {
                    $bingResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$bingName"
                }

                $bingKeys = Get-BingKeys -BingName $bingName -ResourceGroupName $ResourceGroupName
                if ($bingKeys) {
                    $bingConnectionName = Format-ConnectionName -Name $bingName

                    $bingLocation = $bingResource.location
                    if (-not $bingLocation) {
                        $bingLocation = (az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json).location
                    }

                    Add-BingConnection `
                        -SubscriptionId $subscriptionId -ResourceGroupName $ResourceGroupName `
                        -FoundryName $FoundryName -ConnectionName $bingConnectionName `
                        -BingResourceId $bingResourceId -BingApiKey $bingKeys.key1 `
                        -BingLocation $bingLocation | Out-Null

                    $envVars["GROUNDING_WITH_BING_CONNECTION_NAME"] = $bingConnectionName
                }
                else {
                    Write-Warn "Could not retrieve Bing API keys – skipping connection"
                }
            }
            else {
                Write-Warn "No Bing resource found in '$ResourceGroupName' – skipping"
            }
        }
        else {
            Write-Info "Bing connection skipped (--SkipBing)"
        }

        # ── 3  Connect AI Search ───────────────────────────────────────────
        $searchConnectionName = $null
        $searchEndpoint       = $null
        if (-not $SkipAISearch) {
            Write-Phase "Phase 3" "Connect Azure AI Search"

            $searchResource = Find-AISearchResource -ResourceGroupName $ResourceGroupName
            if ($searchResource) {
                $searchName = $searchResource.name
                Write-Success "Found Search service: $searchName"

                $searchResourceId = $searchResource.id
                if (-not $searchResourceId) {
                    $searchResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/$searchName"
                }

                $searchEndpoint = "https://$searchName.search.windows.net"

                $searchLocation = $searchResource.location
                if (-not $searchLocation) {
                    $searchLocation = (az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json).location
                }

                $searchKeys = Get-SearchKeys -SearchName $searchName -ResourceGroupName $ResourceGroupName
                if ($searchKeys) {
                    $searchConnectionName = Format-ConnectionName -Name $searchName

                    Add-AISearchConnection `
                        -SubscriptionId $subscriptionId -ResourceGroupName $ResourceGroupName `
                        -FoundryName $FoundryName -ConnectionName $searchConnectionName `
                        -SearchResourceId $searchResourceId -SearchEndpoint $searchEndpoint `
                        -SearchApiKey $searchKeys.primaryKey -SearchLocation $searchLocation | Out-Null

                    $envVars["AZURE_SEARCH_CONNECTION_NAME"] = $searchConnectionName
                    $envVars["AZURE_SEARCH_ENDPOINT"]        = $searchEndpoint
                    $envVars["AZURE_SEARCH_KEY"]             = $searchKeys.primaryKey
                }
                else {
                    Write-Warn "Could not retrieve Search admin keys – skipping connection"
                }
            }
            else {
                Write-Warn "No AI Search service found in '$ResourceGroupName' – skipping"
            }
        }
        else {
            Write-Info "AI Search connection skipped (--SkipAISearch)"
        }

        # ── 4  Summary ─────────────────────────────────────────────────────
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                                                                ║" -ForegroundColor Green
        Write-Host "║          RestoreLab – Complete!                                ║" -ForegroundColor Green
        Write-Host "║                                                                ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""

        Write-Header "Resource Summary"

        Write-Host "Resource Group:      " -NoNewline -ForegroundColor Gray
        Write-Host $ResourceGroupName -ForegroundColor White

        Write-Host "Location:            " -NoNewline -ForegroundColor Gray
        Write-Host $Location -ForegroundColor White

        Write-Host "Foundry Account:     " -NoNewline -ForegroundColor Gray
        Write-Host $FoundryName -ForegroundColor White

        Write-Host "Project:             " -NoNewline -ForegroundColor Gray
        Write-Host $ProjectName -ForegroundColor White

        if ($foundryInfo) {
            Write-Host "Foundry Endpoint:    " -NoNewline -ForegroundColor Gray
            Write-Host $foundryInfo.Endpoint -ForegroundColor White
        }

        if ($bingConnectionName) {
            Write-Host "Bing Connection:     " -NoNewline -ForegroundColor Gray
            Write-Host $bingConnectionName -ForegroundColor White
        }

        if ($searchConnectionName) {
            Write-Host "Search Connection:   " -NoNewline -ForegroundColor Gray
            Write-Host $searchConnectionName -ForegroundColor White
            Write-Host "Search Endpoint:     " -NoNewline -ForegroundColor Gray
            Write-Host $searchEndpoint -ForegroundColor White
        }

        # Models summary
        if ($modelsResult) {
            Write-Host ""
            if ($modelsResult.Deployed.Count -gt 0) {
                Write-Host "Models deployed:     " -NoNewline -ForegroundColor Gray
                Write-Host "$($modelsResult.Deployed.Count)" -ForegroundColor White
            }
            if ($modelsResult.Skipped.Count -gt 0) {
                Write-Host "Models skipped:      " -NoNewline -ForegroundColor Gray
                Write-Host "$($modelsResult.Skipped.Count)" -ForegroundColor Yellow
            }
            if ($modelsResult.Failed.Count -gt 0) {
                Write-Host "Models failed:       " -NoNewline -ForegroundColor Gray
                Write-Host "$($modelsResult.Failed.Count)" -ForegroundColor Red
            }
        }

        # ── .env block ─────────────────────────────────────────────────────
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  .env variables you may want to add:" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""

        foreach ($key in $envVars.Keys) {
            Write-Host "$key=$($envVars[$key])" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""

        Write-Success "Done!  Open AI Foundry Portal: https://ai.azure.com"
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
