<#
.SYNOPSIS
    Deploy Azure SQL Server and Database

.DESCRIPTION
    This script creates an Azure SQL Server and a SQL Database with vector-capable settings.
    If the server or database already exists, it reports the existing resources.

.PARAMETER ResourceGroupName
    The name of the resource group containing the SQL resources (Required)

.PARAMETER ServerName
    The name of the SQL Server to create (Required)

.PARAMETER Location
    The Azure region for deployment (default: eastus2)

.PARAMETER DatabaseName
    The name of the SQL Database to create (default: vectordb)

.PARAMETER AdminUser
    The SQL Server administrator username (default: sqladmin)

.EXAMPLE
    .\Deploy-SQLDB.ps1 -ResourceGroupName "WPLUS-Foundry" -ServerName "sqlaivector-12345"

.EXAMPLE
    .\Deploy-SQLDB.ps1 -ResourceGroupName "myRG" -ServerName "my-sql" -DatabaseName "mydb" -AdminUser "sqladmin"

.NOTES
    Prerequisites:
    - Azure CLI must be installed and logged in
    - Appropriate permissions to create SQL resources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true, HelpMessage="SQL Server name")]
    [string]$ServerName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = "vectordb",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminUser = "sqladmin"
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

# Create SQL Server and Database
function New-SQLServerAndDatabase {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$AdminUser,
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    Write-Header "Creating SQL Server and Database"
    
    Write-Info "Creating SQL Server: $ServerName"
    Write-Info "Configuration: GP_Gen5 (2 vCores), 32GB max size"
    
    # Generate secure password
    $adminPassword = New-SecurePassword -Length 16
    
    # Check if SQL Server exists
    $existingServer = az sql server show `
        --name $ServerName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingServer) {
        Write-Warning "SQL Server '$ServerName' already exists"
        Write-Warning "Cannot retrieve existing password. You may need to reset it manually."
        Write-Info "Please ensure you have the admin password for existing server"
    }
    else {
        # Create SQL Server
        try {
            Write-Info "Creating SQL Server (this may take 3-5 minutes)..."
            $server = az sql server create `
                --name $ServerName `
                --resource-group $ResourceGroupName `
                --location $Location `
                --admin-user $AdminUser `
                --admin-password $adminPassword `
                --enable-public-network true `
                --output json | ConvertFrom-Json
            
            Write-Success "SQL Server created successfully"
            Write-Info "Admin User: $AdminUser"
            Write-Info "Admin Password: [Generated securely - will be saved to .env]"
            
            # Add firewall rule to allow Azure services
            Write-Info "Configuring firewall rules..."
            az sql server firewall-rule create `
                --name "AllowAzureServices" `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --start-ip-address 0.0.0.0 `
                --end-ip-address 0.0.0.0 `
                --output none
            
            # Add firewall rule to allow all IPs (for lab purposes)
            az sql server firewall-rule create `
                --name "AllowAllIPs" `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --start-ip-address 0.0.0.0 `
                --end-ip-address 255.255.255.255 `
                --output none
            
            Write-Success "Firewall rules configured"
        }
        catch {
            Write-ErrorMsg "Failed to create SQL Server: $_"
            Write-Info "You may need to create this resource manually in the portal"
            return $null
        }
    }
    
    # Create SQL Database
    Write-Info "Creating SQL Database: $DatabaseName"
    $existingDb = az sql db show `
        --name $DatabaseName `
        --server $ServerName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingDb) {
        Write-Warning "Database '$DatabaseName' already exists"
    }
    else {
        try {
            Write-Info "Creating database with GP_Gen5 SKU (this may take 2-3 minutes)..."
            $database = az sql db create `
                --name $DatabaseName `
                --server $ServerName `
                --resource-group $ResourceGroupName `
                --edition GeneralPurpose `
                --family Gen5 `
                --capacity 2 `
                --compute-model Provisioned `
                --max-size 32GB `
                --backup-storage-redundancy Geo `
                --zone-redundant false `
                --read-scale Disabled `
                --no-wait `
                --output json 2>$null
            
            Write-Success "Database creation initiated"
            Write-Info "Database: $DatabaseName | Edition: GeneralPurpose (Gen5) | vCores: 2"
        }
        catch {
            Write-Warning "Could not create database: $_"
            Write-Info "You may need to create the database manually in the portal"
        }
    }
    
    Write-Success "SQL Server setup completed"
    
    return @{
        ServerName = $ServerName
        DatabaseName = $DatabaseName
        AdminUser = $AdminUser
        AdminPassword = $adminPassword
        FullyQualifiedName = "$ServerName.database.windows.net"
    }
}

# Main execution
function Main {
    try {
        $ErrorActionPreference = "Stop"
        
        Show-ScriptBanner -Title "SQL Server and Database Deployment Script"
        
        # Check prerequisites
        $accountInfo = Test-Prerequisites
        
        # Create SQL Server and Database
        $sqlInfo = New-SQLServerAndDatabase `
            -ServerName $ServerName `
            -DatabaseName $DatabaseName `
            -AdminUser $AdminUser `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location
        
        if (-not $sqlInfo) {
            Write-ErrorMsg "SQL Server/Database creation failed"
            exit 1
        }
        
        Write-Host ""
        Write-Success "SQL Server and Database are ready"
        Write-Info "Server: $($sqlInfo.FullyQualifiedName)"
        Write-Info "Database: $($sqlInfo.DatabaseName)"
        Write-Info "Admin User: $($sqlInfo.AdminUser)"
        Write-Info "Admin Password: $($sqlInfo.AdminPassword)"
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
