<#
.SYNOPSIS
    Connect an existing Azure AI Search service to an Azure AI Foundry project

.DESCRIPTION
    This script:
    - Finds the existing Azure AI Search (Microsoft.Search/searchServices) resource in the specified resource group
    - Retrieves its admin API key
    - Adds it as a connected resource (Cognitive Search) to the specified AI Foundry account
    - Uses the ARM REST API via 'az rest', so no extra CLI extensions are required

.PARAMETER ResourceGroupName
    The name of the resource group containing both the Search service and the Foundry project (required)

.PARAMETER FoundryName
    The name of the AI Foundry account (required)

.PARAMETER ProjectName
    The name of the AI Foundry project under the account (required)

.PARAMETER ConnectionName
    The display name for the connection (optional, defaults to the Search service name)

.EXAMPLE
    .\Connect-AISearch.ps1 -ResourceGroupName "azureaiworkshoprg" -FoundryName "ai-foundry-12345" -ProjectName "firstProject"

.EXAMPLE
    .\Connect-AISearch.ps1 -ResourceGroupName "myRG" -FoundryName "myFoundry" -ProjectName "myProject" -ConnectionName "my-search-conn"

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to read Search services and manage AI Foundry connections
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true, HelpMessage="AI Foundry account name")]
    [string]$FoundryName,

    [Parameter(Mandatory=$true, HelpMessage="AI Foundry project name")]
    [string]$ProjectName,

    [Parameter(Mandatory=$false, HelpMessage="Connection name (defaults to Search service name)")]
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
# Find Azure AI Search service in the resource group
# ───────────────────────────────────────────────────────────────
function Find-AISearchResource {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )

    Write-Header "Searching for Azure AI Search Service"
    Write-Info "Resource group: $ResourceGroupName"

    Write-Info "Looking for Microsoft.Search/searchServices resources..."
    $searchServices = az resource list `
        --resource-group $ResourceGroupName `
        --resource-type "Microsoft.Search/searchServices" `
        --output json 2>$null | ConvertFrom-Json

    if (-not $searchServices -or $searchServices.Count -eq 0) {
        Write-ErrorMsg "No Azure AI Search service found in resource group '$ResourceGroupName'"
        Write-Info "Create one first with: .\Deploy-AISearch.ps1 -ResourceGroupName '$ResourceGroupName' -SearchName '<name>'"
        return $null
    }

    if ($searchServices.Count -gt 1) {
        Write-Warning "Multiple Search services found – using the first one: $($searchServices[0].name)"
    }

    $search = $searchServices[0]
    Write-Success "Found Search service: $($search.name)"
    return $search
}

# ───────────────────────────────────────────────────────────────
# Get Search service admin keys
# ───────────────────────────────────────────────────────────────
function Get-SearchKeys {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SearchName,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )

    Write-Info "Retrieving admin API keys for Search service: $SearchName"

    try {
        $keys = az search admin-key show `
            --service-name $SearchName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json

        if ($keys -and $keys.primaryKey) {
            Write-Success "Admin API keys retrieved"
            return $keys
        }
    }
    catch { <# fall through to REST fallback #> }

    # Fallback: use REST API
    Write-Info "Trying REST API to list admin keys..."
    try {
        $subscriptionId = (az account show --output json 2>$null | ConvertFrom-Json).id
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/$SearchName/listAdminKeys?api-version=2025-05-01"
        $keys = az rest --method post --uri $uri --output json 2>$null | ConvertFrom-Json

        if ($keys -and $keys.primaryKey) {
            Write-Success "Admin API keys retrieved via REST"
            return $keys
        }
    }
    catch { <# fall through #> }

    Write-ErrorMsg "Could not retrieve admin keys for Search service '$SearchName'"
    return $null
}

# ───────────────────────────────────────────────────────────────
# Create (or update) the AI Search connection on the Foundry account
# ───────────────────────────────────────────────────────────────
function Add-AISearchConnectionToFoundry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$FoundryName,

        [Parameter(Mandatory=$true)]
        [string]$ConnectionName,

        [Parameter(Mandatory=$true)]
        [string]$SearchResourceId,

        [Parameter(Mandatory=$true)]
        [string]$SearchEndpoint,

        [Parameter(Mandatory=$true)]
        [string]$SearchApiKey,

        [Parameter(Mandatory=$true)]
        [string]$SearchLocation
    )

    Write-Header "Creating AI Search Connection"
    Write-Info "Foundry:    $FoundryName"
    Write-Info "Connection: $ConnectionName"
    Write-Info "Endpoint:   $SearchEndpoint"

    $apiVersion = "2025-06-01"
    # Connections live at the Cognitive Services ACCOUNT level
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

    # Build the PUT body – category is CognitiveSearch for CognitiveServices RP
    $body = @{
        properties = @{
            category      = "CognitiveSearch"
            target        = $SearchEndpoint
            authType      = "ApiKey"
            isSharedToAll = $true
            credentials   = @{
                key = $SearchApiKey
            }
            metadata      = @{
                ResourceId = $SearchResourceId
                Location   = $SearchLocation
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
        Write-Info "  3. Go to Connected Resources → New connection → Azure AI Search"
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
        [string]$SearchName,
        [string]$SearchEndpoint,
        [string]$ProjectName,
        [string]$ConnectionName,
        [string]$FoundryName,
        $Connection
    )

    Write-Header "Connection Summary"

    Write-Host "Search Service:      " -NoNewline -ForegroundColor Gray
    Write-Host $SearchName -ForegroundColor White

    Write-Host "Search Endpoint:     " -NoNewline -ForegroundColor Gray
    Write-Host $SearchEndpoint -ForegroundColor White

    Write-Host "Foundry Account:     " -NoNewline -ForegroundColor Gray
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
    Write-Host "  .env variables you may want to add:" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "AZURE_SEARCH_CONNECTION_NAME=$ConnectionName" -ForegroundColor White
    Write-Host "AZURE_SEARCH_ENDPOINT=$SearchEndpoint" -ForegroundColor White
    Write-Host ""
}

# ───────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────
function Main {
    try {
        $ErrorActionPreference = "Stop"

        Show-ScriptBanner -Title "Connect AI Search to AI Foundry Project"

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

        # 3. Find the Search service
        $searchResource = Find-AISearchResource -ResourceGroupName $ResourceGroupName
        if (-not $searchResource) {
            exit 1
        }

        $searchName = $searchResource.name

        # Resolve the full ARM resource ID
        $searchResourceId = $searchResource.id
        if (-not $searchResourceId) {
            $searchResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/$searchName"
        }

        # Build endpoint
        $searchEndpoint = "https://$searchName.search.windows.net"

        # Resolve location
        $searchLocation = $searchResource.location
        if (-not $searchLocation) {
            $searchLocation = (az group show --name $ResourceGroupName --output json 2>$null | ConvertFrom-Json).location
        }
        Write-Info "Search service location: $searchLocation"

        # 4. Get Search admin key
        $searchKeys = Get-SearchKeys -SearchName $searchName -ResourceGroupName $ResourceGroupName
        if (-not $searchKeys) {
            exit 1
        }

        # 5. Determine connection name (must match ^[a-zA-Z0-9][a-zA-Z0-9_-]{2,32}$)
        if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
            $ConnectionName = $searchName
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

        # 7. Create the connection
        $connection = Add-AISearchConnectionToFoundry `
            -SubscriptionId $subscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -FoundryName $FoundryName `
            -ConnectionName $ConnectionName `
            -SearchResourceId $searchResourceId `
            -SearchEndpoint $searchEndpoint `
            -SearchApiKey $searchKeys.primaryKey `
            -SearchLocation $searchLocation

        # 8. Summary
        Show-ConnectionSummary `
            -SearchName $searchName `
            -SearchEndpoint $searchEndpoint `
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
