<#
.SYNOPSIS
    Display Bing Grounding resource name(s) in a resource group

.DESCRIPTION
    Finds Azure Cognitive Services accounts of kind 'Bing.Search.v8' within the given resource group
    and prints the resource name(s).

.PARAMETER ResourceGroupName
    The name of the resource group to search (required)

.EXAMPLE
    .\Get-BingResourceName.ps1 -ResourceGroupName "myRG"

.NOTES
    Prerequisites:
    - Azure CLI (az) must be installed
    - Logged in to Azure CLI (az login)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Resource group name")]
    [string]$ResourceGroupName
)

# Import common functions (if available)
$commonFunctionsPath = Join-Path $PSScriptRoot "Common-Functions.ps1"
if (Test-Path $commonFunctionsPath) {
    . $commonFunctionsPath
}
else {
    function Write-Info { Write-Host "→ $args" -ForegroundColor Cyan }
    function Write-Success { Write-Host "✓ $args" -ForegroundColor Green }
    function Write-Warning { Write-Host "⚠ $args" -ForegroundColor Yellow }
    function Write-ErrorMsg { Write-Host "✗ $args" -ForegroundColor Red }
    function Write-Header {
        param([string]$Message)
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Host "  $Message" -ForegroundColor Magenta
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Host ""
    }
    function Test-Prerequisites {
        Write-Header "Checking Prerequisites"
        try { az version --output json 2>$null | Out-Null } catch { throw "Azure CLI not found" }
        try { az account show 2>$null | Out-Null } catch { throw "Not logged in. Run: az login" }
    }
    function Show-ScriptBanner {
        param([Parameter(Mandatory = $true)][string]$Title)
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "║  $($Title.PadRight(60))║" -ForegroundColor Blue
        Write-Host "║                                                                ║" -ForegroundColor Blue
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
        Write-Host ""
    }
}

function Get-BingResourcesInResourceGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    Write-Header "Searching for Bing Resources"
    Write-Info "Resource group: $ResourceGroupName"

    # Strategy 1: Cognitive Services accounts of kind Bing.Search.v8
    Write-Info "Looking for Cognitive Services Bing accounts..."
    $cogAccounts = az cognitiveservices account list `
        --resource-group $ResourceGroupName `
        --output json 2>$null | ConvertFrom-Json

    $bingResources = @()
    if ($cogAccounts) {
        $bingResources = @($cogAccounts | Where-Object { $_.kind -eq "Bing.Search.v8" })
    }

    # Strategy 2: Microsoft.Bing/accounts resource type
    if ($bingResources.Count -eq 0) {
        Write-Info "Trying Microsoft.Bing/accounts resource type..."
        $bingAccounts = az resource list `
            --resource-group $ResourceGroupName `
            --resource-type "Microsoft.Bing/accounts" `
            --output json 2>$null | ConvertFrom-Json

        if ($bingAccounts) {
            $bingResources = @($bingAccounts)
        }
    }

    return @($bingResources)
}

function Test-AzPrerequisites {
    Write-Header "Checking Prerequisites"

    # Ensure Azure CLI is installed
    Write-Info "Checking Azure CLI installation..."
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        if (-not $azVersion) { throw "Azure CLI not found" }
        Write-Success "Azure CLI is installed (version: $($azVersion.'azure-cli'))"
    }
    catch {
        Write-ErrorMsg "Azure CLI is not installed. Please install from: https://aka.ms/installazurecliwindows"
        throw "Azure CLI is required"
    }

    # Ensure user is logged in
    Write-Info "Checking Azure login status..."
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if (-not $account) { throw "Not logged in" }
        Write-Success "Logged in to Azure (Subscription: $($account.name))"
    }
    catch {
        Write-ErrorMsg "Not logged in to Azure. Please run: az login"
        throw "Azure login is required"
    }
}

function Main {
    try {
        $ErrorActionPreference = "Stop"

        Show-ScriptBanner -Title "Get Bing Resource Name"
        Test-AzPrerequisites | Out-Null

        $bingResources = Get-BingResourcesInResourceGroup -ResourceGroupName $ResourceGroupName

        if (-not $bingResources -or $bingResources.Count -eq 0) {
            Write-Warning "No Bing.Search.v8 resources found in resource group '$ResourceGroupName'."
            return
        }

        Write-Header "Bing Resource(s) Found"
        $bingTable = $bingResources | Select-Object name, location, kind, id
        $bingTable | Format-Table -AutoSize

        foreach ($bing in $bingResources) {
            Write-Success "BingName: $($bing.name)"
        }

        # If there's only one, also print just the name for easy copy/paste
        if ($bingResources.Count -eq 1) {
            Write-Host "" 
            Write-Host $bingResources[0].name
        }
    }
    catch {
        Write-ErrorMsg "An error occurred: $_"
        exit 1
    }
}

Main
