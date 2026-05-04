<#
.SYNOPSIS
    Cleanup Script for Falco AKS Demo

.DESCRIPTION
    This script removes all resources created for the Falco AKS Demo by deleting the resource group.

.PARAMETER Force
    Skip the confirmation prompt and proceed with deletion immediately.

.EXAMPLE
    .\Remove-FalcoDemo.ps1

.EXAMPLE
    .\Remove-FalcoDemo.ps1 -Force

.NOTES
    Prerequisites:
    - Azure PowerShell modules (Az.Accounts, Az.Resources)
    WARNING: This action cannot be undone!
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Configuration
$RESOURCE_GROUP = "rg-falco-demo"

# Script variables
$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Confirm-Deletion {
    if ($Force) {
        return $true
    }
    
    Write-Warning "This will delete the resource group: $RESOURCE_GROUP"
    Write-Warning "This action cannot be undone!"
    Write-Host ""
    
    $confirmation = Read-Host "Are you sure you want to continue? (yes/no)"
    
    if ($confirmation -ne "yes") {
        Write-Info "Cleanup cancelled."
        return $false
    }
    
    return $true
}

function Remove-Resources {
    Write-Info "Starting cleanup process..."
    
    # Import required modules
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Resources -ErrorAction Stop
    
    # Ensure we're logged in
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Info "Not logged in to Azure. Logging in..."
            Connect-AzAccount
        }
    }
    catch {
        Write-Info "Not logged in to Azure. Logging in..."
        Connect-AzAccount
    }
    
    # Check if resource group exists
    $rg = Get-AzResourceGroup -Name $RESOURCE_GROUP -ErrorAction SilentlyContinue
    
    if ($rg) {
        Write-Info "Deleting resource group: $RESOURCE_GROUP..."
        
        Remove-AzResourceGroup `
            -Name $RESOURCE_GROUP `
            -Force `
            -AsJob | Out-Null
        
        Write-Info "Resource group deletion initiated."
        Write-Info "Note: Deletion may take several minutes to complete."
    }
    else {
        Write-Warning "Resource group $RESOURCE_GROUP does not exist."
    }
}

#endregion

#region Main Execution

function Main {
    Write-Info "Falco AKS Demo Cleanup"
    Write-Info "======================"
    Write-Host ""
    
    try {
        if (Confirm-Deletion) {
            Remove-Resources
            Write-Info "`nCleanup completed!"
        }
    }
    catch {
        Write-ErrorMessage "An error occurred during cleanup: $_"
        Write-ErrorMessage $_.ScriptStackTrace
        exit 1
    }
}

# Run main function
Main

#endregion
