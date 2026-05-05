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
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "main-subscription"
)

# Configuration — resolved dynamically from the deployment outputs / param file
# unless the caller passes -ResourceGroup or sets the env var.
$RESOURCE_GROUP = $env:RESOURCE_GROUP

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

function Resolve-ResourceGroup {
    if ($ResourceGroup) { $script:RESOURCE_GROUP = $ResourceGroup; return }
    if ($script:RESOURCE_GROUP) { return }

    # Try the recorded subscription deployment outputs first
    try {
        $rg = (Get-AzDeployment -Name $DeploymentName -ErrorAction SilentlyContinue).Outputs.resourceGroupName.Value
        if ($rg) { $script:RESOURCE_GROUP = $rg; return }
    } catch {}

    # Fall back to parsing main-subscription.bicepparam
    $scriptPath = Split-Path -Parent $PSCommandPath
    $paramFile  = Join-Path (Split-Path -Parent $scriptPath) "main-subscription.bicepparam"
    if (Test-Path $paramFile) {
        $line = Get-Content $paramFile | Where-Object { $_ -match "^\s*param\s+resourceGroupName\s*=\s*'([^']+)'" } | Select-Object -First 1
        if ($line -and $matches[1]) { $script:RESOURCE_GROUP = $matches[1]; return }
    }

    throw "Could not determine resource group. Pass -ResourceGroup <name> or set `$env:RESOURCE_GROUP."
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
        # Import early so we can query Get-AzDeployment for resource group resolution
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Resources -ErrorAction Stop
        try {
            $context = Get-AzContext
            if (-not $context) { Connect-AzAccount | Out-Null }
        } catch { Connect-AzAccount | Out-Null }

        Resolve-ResourceGroup

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
