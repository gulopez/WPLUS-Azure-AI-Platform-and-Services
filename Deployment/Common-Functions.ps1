<#
.SYNOPSIS
    Common functions and utilities for Azure deployment scripts

.DESCRIPTION
    This script contains reusable functions that can be dot-sourced into other scripts:
    - Color output functions for consistent formatting
    - Prerequisites checking (Azure CLI, login status)
    - Common header formatting
    
    Usage: . .\Common-Functions.ps1

.NOTES
    This script is designed to be dot-sourced, not executed directly.
    Use it at the beginning of your deployment scripts:
    
    . .\Common-Functions.ps1
    
    Then call any of the exported functions.
#>

# ═══════════════════════════════════════════════════════════════
# Color Output Functions
# ═══════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════
# Prerequisites Checking
# ═══════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Check prerequisites for Azure deployment scripts

.DESCRIPTION
    Verifies that:
    - Azure CLI is installed
    - User is logged in to Azure CLI
    - Returns account information

.OUTPUTS
    PSCustomObject with account information (subscription, tenant, etc.)

.EXAMPLE
    $accountInfo = Test-Prerequisites
    Write-Host "Using subscription: $($accountInfo.name)"
#>
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
        throw "Azure CLI is required but not installed"
    }
    
    # Check if logged in to Azure
    Write-Info "Checking Azure login status..."
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if (!$account) {
            throw "Not logged in"
        }
        Write-Success "Logged in to Azure (Subscription: $($account.name))"
        Write-Info "Subscription ID: $($account.id)"
        Write-Info "Tenant ID: $($account.tenantId)"
        return $account
    }
    catch {
        Write-ErrorMsg "Not logged in to Azure. Please run: az login"
        throw "Azure login is required"
    }
}

# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Display a formatted banner with title

.DESCRIPTION
    Shows a decorative banner at the start of scripts

.PARAMETER Title
    The title text to display in the banner

.EXAMPLE
    Show-ScriptBanner -Title "Azure AI Foundry Deployment"
#>
function Show-ScriptBanner {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║                                                                ║" -ForegroundColor Blue
    Write-Host "║  $($Title.PadRight(60))║" -ForegroundColor Blue
    Write-Host "║                                                                ║" -ForegroundColor Blue
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
}

<#
.SYNOPSIS
    Verify that a resource group exists

.DESCRIPTION
    Checks if the specified resource group exists in the current subscription

.PARAMETER ResourceGroupName
    The name of the resource group to verify

.OUTPUTS
    Boolean indicating if the resource group exists

.EXAMPLE
    if (Test-ResourceGroupExists -ResourceGroupName "myRG") {
        Write-Host "Resource group exists"
    }
#>
function Test-ResourceGroupExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    
    $exists = az group exists --name $ResourceGroupName 2>$null
    return ($exists -eq "true")
}

<#
.SYNOPSIS
    Create a resource group if it doesn't exist

.DESCRIPTION
    Ensures a resource group exists, creating it if necessary

.PARAMETER ResourceGroupName
    The name of the resource group

.PARAMETER Location
    The Azure region for the resource group

.EXAMPLE
    Initialize-ResourceGroup -ResourceGroupName "myRG" -Location "eastus2"
#>
function Initialize-ResourceGroup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$Location
    )
    
    Write-Info "Checking if resource group '$ResourceGroupName' exists..."
    
    if (Test-ResourceGroupExists -ResourceGroupName $ResourceGroupName) {
        Write-Success "Resource group '$ResourceGroupName' already exists"
        return $true
    }
    else {
        Write-Info "Creating resource group '$ResourceGroupName' in location '$Location'..."
        try {
            az group create --name $ResourceGroupName --location $Location --output none 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Resource group created successfully"
                return $true
            }
            else {
                Write-ErrorMsg "Failed to create resource group"
                return $false
            }
        }
        catch {
            Write-ErrorMsg "Error creating resource group: $_"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Generate a secure random password

.DESCRIPTION
    Creates a secure password meeting Azure requirements (uppercase, lowercase, numbers, special characters)

.PARAMETER Length
    Length of the password (default: 16)

.OUTPUTS
    String containing the generated password

.EXAMPLE
    $pwd = New-SecurePassword -Length 20
#>
function New-SecurePassword {
    param(
        [Parameter(Mandatory=$false)]
        [int]$Length = 16
    )
    
    # Generate a complex password that meets Azure SQL requirements
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghijkmnopqrstuvwxyz"
    $numbers = "23456789"
    $special = "!@#$%^&*()-_=+"
    
    $password = ""
    $password += $upper[(Get-Random -Maximum $upper.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $numbers[(Get-Random -Maximum $numbers.Length)]
    $password += $special[(Get-Random -Maximum $special.Length)]
    
    $allChars = $upper + $lower + $numbers + $special
    for ($i = 4; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle the password
    $passwordArray = $password.ToCharArray()
    $shuffled = $passwordArray | Get-Random -Count $passwordArray.Length
    return -join $shuffled
}

# ═══════════════════════════════════════════════════════════════
# Export Module Members (for informational purposes)
# ═══════════════════════════════════════════════════════════════

# When dot-sourced, all functions are automatically available
# This list documents the public API

$ExportedFunctions = @(
    'Write-Success',
    'Write-Info',
    'Write-Warning',
    'Write-ErrorMsg',
    'Write-Header',
    'Test-Prerequisites',
    'Show-ScriptBanner',
    'Test-ResourceGroupExists',
    'Initialize-ResourceGroup',
    'New-SecurePassword'
)

# Display dot-source success message if run interactively
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Common Functions Library" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This script should be dot-sourced into other scripts:" -ForegroundColor Cyan
    Write-Host "  . .\Common-Functions.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Available functions:" -ForegroundColor Cyan
    foreach ($func in $ExportedFunctions) {
        Write-Host "  • $func" -ForegroundColor White
    }
    Write-Host ""
}
