<#
.SYNOPSIS
    Deploy an Azure AI Search service

.DESCRIPTION
    This script creates an Azure AI Search (Microsoft.Search/searchServices) resource
    matching the configuration in AISearch.json.
    If the resource already exists, it returns the existing resource information.

.PARAMETER ResourceGroupName
    The name of the resource group where the Search service will be created (required)

.PARAMETER SearchName
    The name of the Search service to create (optional, defaults to "aisearch-<random>")

.PARAMETER Location
    The Azure region for the Search service (default: eastus2)

.PARAMETER Sku
    The pricing tier for the Search service (default: basic)

.EXAMPLE
    .\Deploy-AISearch.ps1 -ResourceGroupName "azureaiworkshoprg"

.EXAMPLE
    .\Deploy-AISearch.ps1 -ResourceGroupName "myRG" -SearchName "my-search-svc" -Location "eastus" -Sku "standard"

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to create Microsoft.Search/searchServices resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$false, HelpMessage="Search service name")]
    [string]$SearchName,

    [Parameter(Mandatory=$false, HelpMessage="Azure region")]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false, HelpMessage="Pricing tier (free, basic, standard, standard2, standard3)")]
    [string]$Sku = "basic"
)

# ───────────────────────────────────────────────────────────────
# Import common functions
# ───────────────────────────────────────────────────────────────
$commonFunctionsPath = Join-Path $PSScriptRoot "Common-Functions.ps1"
if (Test-Path $commonFunctionsPath) {
    . $commonFunctionsPath
}
else {
    Write-Host "Error: Common-Functions.ps1 not found at: $commonFunctionsPath" -ForegroundColor Red
    Write-Host "Please ensure Common-Functions.ps1 is in the same directory as this script." -ForegroundColor Yellow
    exit 1
}

# ───────────────────────────────────────────────────────────────
# Create (or reuse) Azure AI Search service
# ───────────────────────────────────────────────────────────────
function New-AISearchResource {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SearchName,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$Location,

        [Parameter(Mandatory=$true)]
        [string]$Sku
    )

    Write-Header "Creating Azure AI Search Service"
    Write-Info "Name:     $SearchName"
    Write-Info "Location: $Location"
    Write-Info "SKU:      $Sku"

    # Check if the resource already exists
    Write-Info "Checking if Search service '$SearchName' already exists..."
    $existing = $null
    try {
        $existing = az search service show `
            --name $SearchName `
            --resource-group $ResourceGroupName `
            --output json 2>$null | ConvertFrom-Json
    }
    catch { <# not found – expected #> }

    if ($existing -and $existing.name) {
        Write-Warning "Search service '$SearchName' already exists"
        Write-Info "Returning existing resource"
        return $existing
    }

    # Build the PUT body matching AISearch.json schema
    $apiVersion = "2025-05-01"
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Search/searchServices/${SearchName}?api-version=$apiVersion"

    $body = @{
        location   = $Location
        sku        = @{
            name = $Sku
        }
        properties = @{
            replicaCount          = 1
            partitionCount        = 1
            hostingMode           = "Default"
            computeType           = "Default"
            publicNetworkAccess   = "Enabled"
            networkRuleSet        = @{
                ipRules = @()
                bypass  = "None"
            }
            encryptionWithCmk     = @{
                enforcement = "Unspecified"
            }
            disableLocalAuth      = $false
            authOptions           = @{
                apiKeyOnly = @{}
            }
            semanticSearch        = "free"
        }
    } | ConvertTo-Json -Depth 6

    # Write to temp file to avoid PowerShell quote-mangling
    $bodyFile = [System.IO.Path]::GetTempFileName()
    $body | Out-File -FilePath $bodyFile -Encoding UTF8 -Force

    Write-Info "Sending PUT request to create Search service..."

    try {
        $result = az rest `
            --method put `
            --uri $uri `
            --body "@$bodyFile" `
            --headers "Content-Type=application/json" `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "REST call failed: $result"
        }

        $search = $result | ConvertFrom-Json
        Write-Success "Search service '$SearchName' created successfully"
        return $search
    }
    catch {
        Write-ErrorMsg "Failed to create Search service: $_"
        Write-Info "You may need to create this resource manually in the Azure Portal"
        return $null
    }
    finally {
        Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
    }
}

# ───────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────
function Main {
    try {
        $ErrorActionPreference = "Stop"

        Show-ScriptBanner -Title "Azure AI Search Deployment Script"

        # 1. Check prerequisites
        $accountInfo = Test-Prerequisites
        $script:subscriptionId = $accountInfo.id

        # 2. Verify resource group exists
        Write-Header "Verifying Resource Group"
        $rgExists = az group exists --name $ResourceGroupName
        if ($rgExists -ne "true") {
            Write-ErrorMsg "Resource group '$ResourceGroupName' does not exist"
            exit 1
        }
        Write-Success "Resource group '$ResourceGroupName' exists"

        # 3. Generate a default name if none was provided
        if ([string]::IsNullOrWhiteSpace($SearchName)) {
            # Derive a numeric suffix from the resource group (same pattern used by other scripts)
            $hash = [System.Math]::Abs($ResourceGroupName.GetHashCode()) % 100000000
            $SearchName = "aisearch-$hash"
            Write-Info "No SearchName provided – using generated name: $SearchName"
        }

        # 4. Create the Search service
        $search = New-AISearchResource `
            -SearchName $SearchName `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location `
            -Sku $Sku

        if (-not $search) {
            Write-ErrorMsg "Search service creation failed"
            exit 1
        }

        # 5. Retrieve the admin key
        $adminKey = $null
        try {
            $keys = az search admin-key show `
                --service-name $SearchName `
                --resource-group $ResourceGroupName `
                --output json 2>$null | ConvertFrom-Json

            if ($keys -and $keys.primaryKey) {
                $adminKey = $keys.primaryKey
            }
        }
        catch { <# could not retrieve keys #> }

        # 6. Summary
        Write-Header "Deployment Summary"

        Write-Host "Name:          " -NoNewline -ForegroundColor Gray
        Write-Host $search.name -ForegroundColor White

        Write-Host "Location:      " -NoNewline -ForegroundColor Gray
        Write-Host $search.location -ForegroundColor White

        Write-Host "SKU:           " -NoNewline -ForegroundColor Gray
        Write-Host $search.sku.name -ForegroundColor White

        $endpoint = "https://$($search.name).search.windows.net"
        Write-Host "Endpoint:      " -NoNewline -ForegroundColor Gray
        Write-Host $endpoint -ForegroundColor White

        Write-Host "Replicas:      " -NoNewline -ForegroundColor Gray
        Write-Host $search.properties.replicaCount -ForegroundColor White

        Write-Host "Partitions:    " -NoNewline -ForegroundColor Gray
        Write-Host $search.properties.partitionCount -ForegroundColor White

        Write-Host "Semantic:      " -NoNewline -ForegroundColor Gray
        Write-Host $search.properties.semanticSearch -ForegroundColor White

        if ($adminKey) {
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
            Write-Host "  .env variables you may want to add:" -ForegroundColor Green
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
            Write-Host ""
            Write-Host "AZURE_SEARCH_ENDPOINT=$endpoint" -ForegroundColor White
            Write-Host "AZURE_SEARCH_KEY=$adminKey" -ForegroundColor White
            Write-Host ""
        }

        Write-Host ""
        Write-Success "Azure AI Search service is ready"
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
