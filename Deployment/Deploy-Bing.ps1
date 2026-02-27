<#
.SYNOPSIS
    Deploy Bing Grounding (Bing Search v8) resource

.DESCRIPTION
    This script creates a Bing Search v8 Cognitive Services account for Bing Grounding.
    If the resource already exists, it returns the existing resource information.

.PARAMETER ResourceGroupName
    The name of the resource group containing the Bing resource (Required)

.PARAMETER BingName
    The name of the Bing resource to create (Required)

.PARAMETER Location
    The Azure region for the Bing resource (default: global)

.EXAMPLE
    .\Deploy-Bing.ps1 -ResourceGroupName "WPLUS-Foundry" -BingName "gwbing-12345"

.EXAMPLE
    .\Deploy-Bing.ps1 -ResourceGroupName "myRG" -BingName "myBing" -Location "global"

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to create Cognitive Services resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true, HelpMessage="Bing resource name")]
    [string]$BingName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "global"
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

# Create Bing Grounding resource
function New-BingResource {
    param(
        [string]$BingName,
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    Write-Header "Creating Bing Grounding Resource"
    
    Write-Info "Creating Bing resource: $BingName"
    Write-Info "Location: $Location"
    
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
            --kind Bing.Search.v8 `
            --sku S1 `
            --location $Location `
            --yes `
            --output json | ConvertFrom-Json
        
        
        return $bing
    }
    catch {
        Write-ErrorMsg "Failed to create Bing resource: $_"
        Write-Info "You may need to create this resource manually in the portal"
        return $null
    }
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Show-ScriptBanner -Title "Bing Grounding Deployment Script"
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Create Bing resource
        $bing = New-BingResource -BingName $BingName -ResourceGroupName $ResourceGroupName -Location $Location
        
        if (-not $bing) {
            Write-ErrorMsg "Bing resource creation failed"
            exit 1
        }
        else
        {
            Write-Success "Bing resource created successfully"
        }
       
        
        Write-Host ""
        Write-Success "Bing Grounding resource is ready"
        Write-Info "Name: $($bing.name)"
        Write-Info "Location: $($bing.location)"
        Write-Info "Kind: $($bing.kind)"
        Write-Info "SKU: $($bing.sku.name)"
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
