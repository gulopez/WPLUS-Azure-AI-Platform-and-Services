<#
.SYNOPSIS
    Connect an existing Bing resource to an Azure AI Foundry project

.DESCRIPTION
    This script:
    - Finds the existing Bing Search (Bing.Search.v7) resource in the specified resource group
    - Retrieves its API key
    - Adds it as a connected resource (Bing Grounding) to the specified AI Foundry project
    - Uses the ARM REST API via 'az rest', so no extra CLI extensions are required

.PARAMETER ResourceGroupName
    The name of the resource group containing both the Bing resource and the Foundry project (required)

.PARAMETER FoundryName
    The name of the AI Foundry hub (required)

.PARAMETER ProjectName
    The name of the AI Foundry project under the hub (required)

.PARAMETER ConnectionName
    The display name for the connection inside the project (optional, defaults to the Bing resource name)

.EXAMPLE
    .\Connect-BingToFoundry.ps1 -ResourceGroupName "azureaiworkshoprg" -FoundryName "ai-foundry-12345" -ProjectName "firstProject"

.EXAMPLE
    .\Connect-BingToFoundry.ps1 -ResourceGroupName "myRG" -FoundryName "myFoundry" -ProjectName "myProject" -ConnectionName "my-bing-connection"

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to read Cognitive Services resources and manage AI Foundry connections
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true, HelpMessage="AI Foundry hub name")]
    [string]$FoundryName,

    [Parameter(Mandatory=$true, HelpMessage="AI Foundry project name")]
    [string]$ProjectName,

    [Parameter(Mandatory=$false, HelpMessage="Connection name (defaults to Bing resource name)")]
    [string]$ConnectionName
)

# ───────────────────────────────────────────────────────────────
# Import common functions
# ───────────────────────────────────────────────────────────────
$commonFunctionsPath = Join-Path $PSScriptRoot "Common-Functions.ps1"
if (Test-Path $commonFunctionsPath) {
    . $commonFunctionsPath
}
else {
    # Inline fallback so the script is self-contained
    function Write-Success  { Write-Host "✓ $args" -ForegroundColor Green }
    function Write-Info     { Write-Host "→ $args" -ForegroundColor Cyan }
    function Write-Warning  { Write-Host "⚠ $args" -ForegroundColor Yellow }
    function Write-ErrorMsg { Write-Host "✗ $args" -ForegroundColor Red }
    function Write-Header {
        param([string]$Message)
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Host "  $Message" -ForegroundColor Magenta
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Host ""
    }
    function Show-ScriptBanner {
        param([Parameter(Mandatory=$true)][string]$Title)
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║  $($Title.PadRight(60))║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
    }
    function Test-Prerequisites {
        Write-Header "Checking Prerequisites"
        try {
            $azVersion = az version --output json 2>$null | ConvertFrom-Json
            if (!$azVersion) { throw "Azure CLI not found" }
            Write-Success "Azure CLI is installed (version: $($azVersion.'azure-cli'))"
        }
        catch {
            Write-ErrorMsg "Azure CLI is not installed. Please install from: https://aka.ms/installazurecliwindows"
            throw "Azure CLI is required but not installed"
        }
        try {
            $account = az account show 2>$null | ConvertFrom-Json
            if (!$account) { throw "Not logged in" }
            Write-Success "Logged in to Azure (Subscription: $($account.name))"
            return $account
        }
        catch {
            Write-ErrorMsg "Not logged in to Azure. Please run: az login"
            throw "Azure login is required"
        }
    }
}

# ───────────────────────────────────────────────────────────────
# Find Bing resource in the resource group
# ───────────────────────────────────────────────────────────────
function Find-BingResource {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )

    Write-Header "Searching for Bing Resource"
    Write-Info "Resource group: $ResourceGroupName"

    # Strategy 1 – Cognitive Services accounts of kind Bing.Search.v7
    Write-Info "Looking for Cognitive Services accounts of kind Bing.Search.v7..."
    $cogAccounts = az cognitiveservices account list `
        --resource-group $ResourceGroupName `
        --output json 2>$null | ConvertFrom-Json

    $bingAccounts = @()
    if ($cogAccounts) {
        $bingAccounts = @($cogAccounts | Where-Object { $_.kind -eq "Bing.Search.v7" })
    }

    # Strategy 2 – Microsoft.Bing/accounts resource type
    if ($bingAccounts.Count -eq 0) {
        Write-Info "No Cognitive Services Bing accounts found. Trying Microsoft.Bing/accounts..."
        $bingResources = az resource list `
            --resource-group $ResourceGroupName `
            --resource-type "Microsoft.Bing/accounts" `
            --output json 2>$null | ConvertFrom-Json

        if ($bingResources -and $bingResources.Count -gt 0) {
            # Convert to a similar shape so downstream code works uniformly
            foreach ($br in $bingResources) {
                $bingAccounts += @{
                    name = $br.name
                    id   = $br.id
                    kind = "Bing.Search.v7"
                    properties = @{ endpoint = "https://api.bing.microsoft.com/" }
                }
            }
        }
    }

    if ($bingAccounts.Count -eq 0) {
        Write-ErrorMsg "No Bing resource found in resource group '$ResourceGroupName'"
        Write-Info "Create one first with: .\Deploy-Bing.ps1 -ResourceGroupName '$ResourceGroupName' -BingName '<name>'"
        return $null
    }

    if ($bingAccounts.Count -gt 1) {
        Write-Warning "Multiple Bing resources found – using the first one: $($bingAccounts[0].name)"
    }

    $bing = $bingAccounts[0]
    Write-Success "Found Bing resource: $($bing.name)"
    return $bing
}

# ───────────────────────────────────────────────────────────────
# Get Bing resource keys
# ───────────────────────────────────────────────────────────────
function Get-BingKeys {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BingName,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )

    Write-Info "Retrieving API keys for Bing resource: $BingName"

    try {
        $keys = az cognitiveservices account keys list `
            --name $BingName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json

        if ($keys -and $keys.key1) {
            Write-Success "API keys retrieved"
            return $keys
        }
    }
    catch { <# fall through to REST fallback #> }

    # Fallback for Microsoft.Bing/accounts (different RP, use az rest)
    Write-Info "Trying REST API to list keys..."
    try {
        $subscriptionId = (az account show --output json 2>$null | ConvertFrom-Json).id
        $uri = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Bing/accounts/$BingName/listKeys?api-version=2020-06-10"
        $keys = az rest --method post --uri $uri --output json 2>$null | ConvertFrom-Json

        if ($keys -and $keys.key1) {
            Write-Success "API keys retrieved via REST"
            return $keys
        }
    }
    catch { <# fall through #> }

    Write-ErrorMsg "Could not retrieve API keys for Bing resource '$BingName'"
    return $null
}

# ───────────────────────────────────────────────────────────────
# Create (or update) the connection on the Foundry project
# ───────────────────────────────────────────────────────────────
function Add-BingConnectionToProject {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$FoundryName,

        [Parameter(Mandatory=$true)]
        [string]$ProjectName,

        [Parameter(Mandatory=$true)]
        [string]$ConnectionName,

        [Parameter(Mandatory=$true)]
        [string]$BingResourceId,

        [Parameter(Mandatory=$true)]
        [string]$BingApiKey,

        [Parameter(Mandatory=$true)]
        [string]$BingLocation
    )

    Write-Header "Creating Bing Grounding Connection"
    Write-Info "Foundry:    $FoundryName"
    Write-Info "Connection: $ConnectionName"

    $apiVersion = "2025-06-01"
    # Connections live at the Cognitive Services ACCOUNT level (not project level)
    $connUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/connections/${ConnectionName}?api-version=$apiVersion"

    $existing = $null
    try {
        $existing = az rest --method get --uri $connUri --output json 2>$null | ConvertFrom-Json
    }
    catch { <# connection does not exist – expected #> }

    if ($existing -and $existing.name) {
        Write-Warning "Connection '$ConnectionName' already exists on account '$FoundryName'"
        Write-Info "Updating the existing connection..."
    }

    # Build the PUT body – category is BingLLMSearch for CognitiveServices RP
    $body = @{
        properties = @{
            category      = "BingLLMSearch"
            target        = "https://api.bing.microsoft.com/"
            authType      = "ApiKey"
            isSharedToAll = $true
            credentials   = @{
                key = $BingApiKey
            }
            metadata      = @{
                ResourceId = $BingResourceId
                Location   = $BingLocation
            }
        }
    } | ConvertTo-Json -Depth 5

    # Write to temp file to avoid PowerShell quote-mangling with az rest --body
    $bodyFile = [System.IO.Path]::GetTempFileName()
    $body | Out-File -FilePath $bodyFile -Encoding UTF8 -Force

    Write-Info "Sending PUT request to create/update connection..."

    try {
        $result = az rest `
            --method put `
            --uri $connUri `
            --body "@$bodyFile" `
            --headers "Content-Type=application/json" `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "REST call failed: $result"
        }

        $connection = $result | ConvertFrom-Json
        Write-Success "Connection '$ConnectionName' created/updated successfully"
        return $connection
    }
    catch {
        Write-ErrorMsg "Failed to create connection: $_"
        Write-Info "You can create the connection manually in the AI Foundry Portal:"
        Write-Info "  1. Go to https://ai.azure.com"
        Write-Info "  2. Open project '$ProjectName'"
        Write-Info "  3. Go to Connected Resources → New connection → Bing Search"
        return $null
    }
    finally {
        Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
    }
}

# ───────────────────────────────────────────────────────────────
# Display summary
# ───────────────────────────────────────────────────────────────
function Show-ConnectionSummary {
    param(
        [string]$BingName,
        [string]$ProjectName,
        [string]$ConnectionName,
        [string]$FoundryName,
        $Connection
    )

    Write-Header "Connection Summary"

    Write-Host "Bing Resource:       " -NoNewline -ForegroundColor Gray
    Write-Host $BingName -ForegroundColor White

    Write-Host "Foundry Hub:         " -NoNewline -ForegroundColor Gray
    Write-Host $FoundryName -ForegroundColor White

    Write-Host "Project:             " -NoNewline -ForegroundColor Gray
    Write-Host $ProjectName -ForegroundColor White

    Write-Host "Connection Name:     " -NoNewline -ForegroundColor Gray
    Write-Host $ConnectionName -ForegroundColor White

    if ($Connection -and $Connection.properties) {
        Write-Host "Category:            " -NoNewline -ForegroundColor Gray
        Write-Host $Connection.properties.category -ForegroundColor White

        Write-Host "Auth Type:           " -NoNewline -ForegroundColor Gray
        Write-Host $Connection.properties.authType -ForegroundColor White
    }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  .env variable you may want to add:" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "GROUNDING_WITH_BING_CONNECTION_NAME=$ConnectionName" -ForegroundColor White
    Write-Host ""
}

# ───────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────
function Main {
    try {
        $ErrorActionPreference = "Stop"

        Show-ScriptBanner -Title "Connect Bing Resource to AI Foundry Project"

        # 1. Prerequisites
        $accountInfo = Test-Prerequisites
        $subscriptionId = $accountInfo.id

        # 2. Verify the resource group exists
        Write-Header "Verifying Resource Group"
        $rgExists = az group exists --name $ResourceGroupName
        if ($rgExists -ne "true") {
            Write-ErrorMsg "Resource group '$ResourceGroupName' does not exist"
            exit 1
        }
        Write-Success "Resource group '$ResourceGroupName' exists"

        # 3. Find the Bing resource
        $bingResource = Find-BingResource -ResourceGroupName $ResourceGroupName
        if (-not $bingResource) {
            exit 1
        }

        $bingName = $bingResource.name

        # Resolve the full ARM resource ID
        $bingResourceId = $bingResource.id
        if (-not $bingResourceId) {
            $bingResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$bingName"
        }

        # 4. Get Bing API key
        $bingKeys = Get-BingKeys -BingName $bingName -ResourceGroupName $ResourceGroupName
        if (-not $bingKeys) {
            exit 1
        }

        # 5. Determine connection name (must match ^[a-zA-Z0-9][a-zA-Z0-9_-]{2,32}$)
        if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
            $ConnectionName = $bingName
        }
        # Sanitise: replace disallowed characters with hyphens, trim to 33 chars
        $ConnectionName = ($ConnectionName -replace '[^a-zA-Z0-9_-]', '-').TrimStart('-')
        if ($ConnectionName.Length -gt 33) { $ConnectionName = $ConnectionName.Substring(0, 33) }
        if ($ConnectionName.Length -lt 3)  { $ConnectionName = $ConnectionName.PadRight(3, '0') }

        # 6. Verify the Foundry project exists (Cognitive Services sub-resource)
        Write-Header "Verifying AI Foundry Project"
        Write-Info "Checking project '$ProjectName' under account '$FoundryName'..."

        $apiVersion = "2025-06-01"
        $projectExists = $null
        try {
            $projectCheckUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects/${ProjectName}?api-version=$apiVersion"
            $projectExists = az rest --method get --uri $projectCheckUri --output json 2>$null | ConvertFrom-Json
        }
        catch { <# project not found #> }

        if (-not $projectExists -or -not $projectExists.name) {
            Write-ErrorMsg "AI Foundry project '$ProjectName' not found under account '$FoundryName'"
            Write-Info "Listing projects under account '$FoundryName':"
            az rest --method get `
                --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects?api-version=$apiVersion" `
                --query "value[].{Name:name, DisplayName:properties.displayName}" `
                --output table 2>$null
            exit 1
        }
        Write-Success "Project '$ProjectName' found"

        # Resolve Bing resource location
        $bingLocation = $bingResource.location
        if (-not $bingLocation) {
            # Fallback: use the resource group location
            $bingLocation = (az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json).location
        }
        Write-Info "Bing resource location: $bingLocation"

        # 7. Create the connection
        $connection = Add-BingConnectionToProject `
            -SubscriptionId $subscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -FoundryName $FoundryName `
            -ProjectName $ProjectName `
            -ConnectionName $ConnectionName `
            -BingResourceId $bingResourceId `
            -BingApiKey $bingKeys.key1 `
            -BingLocation $bingLocation

        # 8. Summary
        Show-ConnectionSummary `
            -BingName $bingName `
            -ProjectName $ProjectName `
            -ConnectionName $ConnectionName `
            -FoundryName $FoundryName `
            -Connection $connection

        Write-Host ""
        Write-Success "Done!"
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
