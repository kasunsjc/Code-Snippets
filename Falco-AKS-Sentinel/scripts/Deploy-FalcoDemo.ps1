<#
.SYNOPSIS
    Deployment Script for Falco AKS Demo

.DESCRIPTION
    This script deploys the complete Falco on AKS with Azure Sentinel integration demo.
    It creates all necessary Azure resources, installs Falco, and configures Sentinel analytics rules.

.EXAMPLE
    .\Deploy-FalcoDemo.ps1

.NOTES
    Prerequisites:
    - Azure PowerShell modules (Az.Accounts, Az.Resources, Az.OperationalInsights, Az.Aks)
    - Azure CLI (for Bicep deployment with .bicepparam support)
    - kubectl
    - Helm
    - PowerShell 7+ recommended
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$EnableRulesOnly,

    [Parameter(Mandatory=$false)]
    [switch]$SkipRules,

    [Parameter(Mandatory=$false)]
    [switch]$NoWait,

    [Parameter(Mandatory=$false)]
    [int]$WaitTimeoutMinutes = 20
)

# Configuration
$LOCATION = "eastus"
$SUBSCRIPTION_ID = ""
$DEPLOYMENT_NAME = "main-subscription"

# Random 6-character hex suffix to ensure unique resource names.
# Generated once per run so all resources share the same suffix.
$RANDOM_SUFFIX = [System.BitConverter]::ToString(
    [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(3)
).Replace('-', '').ToLower()

# These are populated from deployment outputs after Deploy-Infrastructure
$RESOURCE_GROUP = ""

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

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check required Azure PowerShell modules
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.OperationalInsights', 'Az.Aks')
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-ErrorMessage "Missing required Azure PowerShell modules: $($missingModules -join ', ')"
        Write-Info "Install missing modules with: Install-Module -Name $($missingModules -join ', ') -Repository PSGallery -Force"
        exit 1
    }
    
    # Import required modules
    Write-Info "Importing Azure PowerShell modules..."
    foreach ($module in $requiredModules) {
        Import-Module $module -ErrorAction Stop
    }
    
    # Check Azure CLI (needed for Bicep deployment with .bicepparam)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "Azure CLI is not installed. Required for Bicep deployment with .bicepparam files."
        Write-Info "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    }
    
    # Check kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "kubectl is not installed. Please install it from https://kubernetes.io/docs/tasks/tools/"
        exit 1
    }
    
    # Check helm
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "Helm is not installed. Please install it from https://helm.sh/docs/intro/install/"
        exit 1
    }
    
    Write-Info "All prerequisites are met!"
}

function Connect-AzureAccount {
    Write-Info "Checking Azure login status..."
    
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Info "Not logged in to Azure. Logging in..."
            Connect-AzAccount
            $context = Get-AzContext
        }
    }
    catch {
        Write-Info "Not logged in to Azure. Logging in..."
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    # Get subscription ID
    $script:SUBSCRIPTION_ID = $context.Subscription.Id
    Write-Info "Using subscription: $SUBSCRIPTION_ID ($($context.Subscription.Name))"
}

function New-ResourceGroup {
    Write-Info "Resource group will be created by Bicep deployment..."
}

function Deploy-Infrastructure {
    Write-Info "Deploying Azure infrastructure with Bicep (subscription-level deployment)..."
    
    # Get the current user's object ID for RBAC
    Write-Info "Getting current user's object ID for AKS RBAC assignment..."
    $context = Get-AzContext
    $USER_OBJECT_ID = (Get-AzADUser -UserPrincipalName $context.Account.Id).Id
    if (-not $USER_OBJECT_ID) {
        # If user principal lookup fails, try getting from context
        $USER_OBJECT_ID = $context.Account.ExtendedProperties.HomeAccountId.Split('.')[0]
    }
    Write-Info "User Object ID: $USER_OBJECT_ID"
    
    $scriptPath = Split-Path -Parent $PSCommandPath
    $mainBicep = Join-Path (Split-Path -Parent $scriptPath) "main-subscription.bicep"
    $mainBicepParam = Join-Path (Split-Path -Parent $scriptPath) "main-subscription.bicepparam"
    
    Write-Info "Resource name suffix: $RANDOM_SUFFIX"

    # Use Azure CLI for subscription-level deployment to support .bicepparam files
    az deployment sub create `
        --location $LOCATION `
        --template-file $mainBicep `
        --parameters $mainBicepParam `
        --parameters aksAdminPrincipalId=$USER_OBJECT_ID `
        --parameters resourceGroupName="rg-falco-demo-$RANDOM_SUFFIX" `
        --parameters aksClusterName="aks-falco-demo-$RANDOM_SUFFIX" `
        --parameters logAnalyticsWorkspaceName="law-falco-demo-$RANDOM_SUFFIX" `
        --name $DEPLOYMENT_NAME `
        --output table
    
    if ($LASTEXITCODE -ne 0) {
        throw "Bicep deployment failed"
    }
    
    Write-Info "Infrastructure deployed successfully!"
}

function Get-DeploymentOutputs {
    Write-Info "Retrieving deployment outputs..."
    
    $deployment = Get-AzDeployment -Name $DEPLOYMENT_NAME
    
    $script:RESOURCE_GROUP    = $deployment.Outputs.resourceGroupName.Value
    $script:AKS_NAME          = $deployment.Outputs.aksClusterName.Value
    $script:LAW_NAME          = $deployment.Outputs.logAnalyticsWorkspaceName.Value
    $script:WORKSPACE_ID      = $deployment.Outputs.workspaceCustomerId.Value
    $script:LOGIC_APP_NAME    = $deployment.Outputs.logicAppName.Value
    $script:LOGIC_APP_TRIGGER = $deployment.Outputs.logicAppTriggerName.Value
    
    Write-Info "Resource Group: $RESOURCE_GROUP"
    Write-Info "AKS Cluster: $AKS_NAME"
    Write-Info "Log Analytics Workspace: $LAW_NAME"
    Write-Info "Workspace ID: $WORKSPACE_ID"
    Write-Info "Logic App: $LOGIC_APP_NAME"
}

# Fetches the Logic App callback URL at runtime. The value is treated as a
# secret (it carries an HMAC SAS) and is NEVER printed to the console.
function Get-WebhookUrlSilently {
    Write-Info "Fetching Logic App callback URL (value will not be printed)..."
    $uri = "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/$LOGIC_APP_TRIGGER/listCallbackUrl?api-version=2017-07-01"
    $url = az rest --method post --url $uri --query value -o tsv 2>$null
    if (-not $url -or $url -eq "null") {
        throw "Could not retrieve Logic App callback URL"
    }
    $script:WEBHOOK_URL = $url
    Write-Info "Webhook URL retrieved (redacted)."
}

function Set-KubectlContext {
    Write-Info "Configuring kubectl..."
    
    # Use Azure CLI for getting AKS credentials (handles authentication better)
    az aks get-credentials `
        --resource-group $RESOURCE_GROUP `
        --name $AKS_NAME `
        --overwrite-existing
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get AKS credentials"
    }
    
    Write-Info "kubectl configured successfully!"
    kubectl cluster-info
}

function Install-Falco {
    Write-Info "Installing Falco on AKS cluster..."
    
    $scriptPath = Split-Path -Parent $PSCommandPath
    $k8sPath = Join-Path (Split-Path -Parent $scriptPath) "k8s"
    
    # Add Falco Helm repository
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update
    
    # Create namespace
    $namespaceFile = Join-Path $k8sPath "falco-namespace.yaml"
    kubectl apply -f $namespaceFile
    
    # Install Falco with Falcosidekick configured to use Logic App webhook
    $valuesFile = Join-Path $k8sPath "falco-values.yaml"
    helm upgrade --install falco falcosecurity/falco `
        --namespace falco `
        --values $valuesFile `
        --set "falcosidekick.config.webhook.address=$WEBHOOK_URL" `
        --wait
    
    Write-Info "Falco installed successfully!"
    Write-Info "Falcosidekick configured to send alerts to Logic App webhook"
}

function Test-Deployment {
    Write-Info "Verifying deployment..."
    
    Write-Info "Checking Falco pods:"
    kubectl get pods -n falco
    
    Write-Info "`nWaiting for Falco pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falco -n falco --timeout=300s
    
    Write-Info "`nWaiting for Falcosidekick pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falcosidekick -n falco --timeout=300s
    
    Write-Info "`nChecking Falco logs:"
    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
    
    Write-Info "`nChecking Falcosidekick logs:"
    kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick --tail=20
    
    Write-Info "`nDeployment verification complete!"
}

function Get-DeterministicId {
    param(
        [Parameter(Mandatory=$true)][string]$WorkspaceResourceId,
        [Parameter(Mandatory=$true)][string]$DisplayName
    )
    $sha1  = [System.Security.Cryptography.SHA1]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$WorkspaceResourceId::$DisplayName")
    $hex   = ($sha1.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    return "{0}-{1}-{2}-{3}-{4}" -f `
        $hex.Substring(0,8),  $hex.Substring(8,4), `
        $hex.Substring(12,4), $hex.Substring(16,4), `
        $hex.Substring(20,12)
}

function Wait-ForFalcoLogs {
    if ($NoWait) {
        Write-Warning "Skipping wait-for-logs gate (-NoWait set)."
        return
    }

    Write-Info "Waiting for Falco events to land in Log Analytics (FalcoLogs_CL)..."
    Write-Info "This can take 5-15 minutes after Falco starts emitting events."

    # Generate a benign event so the FalcoLogs_CL table is materialised sooner.
    # We trigger the "Package Management in Container" rule (apk update inside
    # an alpine pod) instead of touching /etc/shadow, so the warm-up doesn't
    # itself look like a credential-theft event in unrelated monitoring tools.
    try {
        kubectl run falco-warmup --rm --restart=Never --image=alpine:3.19 -i `
            --command -- sh -c 'apk update >/dev/null 2>&1 || true; echo done' 2>$null | Out-Null
    } catch { }

    $deadline = (Get-Date).AddMinutes($WaitTimeoutMinutes)
    $attempt  = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $count = az monitor log-analytics query `
            --workspace $WORKSPACE_ID `
            --analytics-query "FalcoLogs_CL | where TimeGenerated > ago(1h) | count" `
            --query "[0].Count" -o tsv 2>$null

        if ($count -and ($count -as [int]) -gt 0) {
            Write-Info "FalcoLogs_CL is populated (rows in last 1h: $count). Proceeding."
            return
        }
        Write-Info "  Attempt #${attempt}: FalcoLogs_CL not populated yet — sleeping 30s..."
        Start-Sleep -Seconds 30
    }

    Write-Warning "Timed out after ${WaitTimeoutMinutes}m waiting for FalcoLogs_CL."
    Write-Warning "Re-run with -EnableRulesOnly once data is flowing."
}

function Import-SentinelRules {
    Write-Info "Importing Sentinel analytics rules..."
    
    # Get workspace resource ID
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $RESOURCE_GROUP -Name $LAW_NAME
    $WORKSPACE_RESOURCE_ID = $workspace.ResourceId
    
    # Read the analytics rules JSON file
    $scriptPath = Split-Path -Parent $PSCommandPath
    $k8sPath = Join-Path (Split-Path -Parent $scriptPath) "k8s"
    $RULES_FILE = Join-Path $k8sPath "sentinel-analytics-rules.json"
    
    if (-not (Test-Path $RULES_FILE)) {
        Write-Warning "Analytics rules file not found at $RULES_FILE"
        return
    }
    
    # Read and parse the JSON file
    $rulesJson = Get-Content $RULES_FILE -Raw | ConvertFrom-Json
    $rules = $rulesJson.analyticsRules
    
    Write-Info "Found $($rules.Count) analytics rules to import"
    
    foreach ($rule in $rules) {
        Write-Info "  $($rule.displayName)"

        # Deterministic GUID — re-running the script updates the existing rule
        # instead of creating a duplicate.
        $RULE_ID = Get-DeterministicId -WorkspaceResourceId $WORKSPACE_RESOURCE_ID -DisplayName $rule.displayName

        # Pass all fields from the JSON through as-is so nothing is silently
        # dropped (matches the bash script behaviour of `{kind, properties: $r}`).
        $ruleBody = @{ kind = "Scheduled"; properties = $rule } | ConvertTo-Json -Depth 20

        # Create a temporary file for the body
        $tempFile = New-TemporaryFile
        $ruleBody | Out-File -FilePath $tempFile.FullName -Encoding utf8 -NoNewline

        try {
            # Create the analytics rule using Azure CLI REST API
            $uri = "https://management.azure.com${WORKSPACE_RESOURCE_ID}/providers/Microsoft.SecurityInsights/alertRules/${RULE_ID}?api-version=2023-02-01"

            $result = az rest --method put --url $uri --body "@$($tempFile.FullName)" 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Info "    ✓ created/updated"
            } else {
                Write-Warning "    ✗ failed (rerun with -EnableRulesOnly later)"
                Write-Host "Error details: $result" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "    ✗ failed: $($_.Exception.Message)"
        }
        finally {
            Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
        }
    }
    
    Write-Info "Sentinel analytics rules import completed!"
}

function Deploy-Workbook {
    Write-Info "Deploying Falco Security Dashboard workbook..."
    
    # Get workspace resource ID
    $WORKSPACE_RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LAW_NAME"
    
    $scriptPath = Split-Path -Parent $PSCommandPath
    $workbookFile = Join-Path (Split-Path -Parent $scriptPath) "workbooks" "falco-security-dashboard.json"
    
    if (-not (Test-Path $workbookFile)) {
        Write-Warning "Workbook file not found at $workbookFile"
        return
    }
    
    # Deterministic ID — re-running updates the existing workbook
    $WORKBOOK_ID = Get-DeterministicId -WorkspaceResourceId $WORKSPACE_RESOURCE_ID -DisplayName "Falco Security Dashboard"
    
    # Read the workbook template
    $serializedData = Get-Content $workbookFile -Raw
    
    # Create the workbook resource JSON
    Write-Info "Creating workbook: Falco Security Dashboard"
    
    $workbookBody = @{
        type = "Microsoft.Insights/workbooks"
        name = $WORKBOOK_ID
        location = $LOCATION
        kind = "shared"
        tags = @{
            "hidden-sentinelWorkspaceId" = $WORKSPACE_RESOURCE_ID
            "hidden-sentinelContentType" = "Workbook"
        }
        properties = @{
            displayName = "Falco Security Dashboard"
            serializedData = $serializedData
            version = "1.0"
            sourceId = $WORKSPACE_RESOURCE_ID
            category = "sentinel"
        }
    } | ConvertTo-Json -Depth 10
    
    # Create a temporary file for the body
    $tempFile = New-TemporaryFile
    $workbookBody | Out-File -FilePath $tempFile.FullName -Encoding utf8 -NoNewline
    
    try {
        # Create the workbook using Azure CLI REST API
        $uri = "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/${WORKBOOK_ID}?api-version=2022-04-01"
        
        $result = az rest --method put --url $uri --body "@$($tempFile.FullName)" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Info "✓ Successfully deployed Falco Security Dashboard workbook"
            Write-Info "View workbook in Azure Portal: Monitor > Workbooks > Falco Security Dashboard"
        } else {
            Write-Warning "✗ Failed to deploy workbook"
            Write-Host "Error details: $result" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to deploy workbook: $($_.Exception.Message)"
    }
    finally {
        # Clean up temp file
        Remove-Item $tempFile.FullName -ErrorAction SilentlyContinue
    }
    
    Write-Info "Workbook deployment completed!"
}

function Show-NextSteps {
    Write-Info "`n=========================================="
    Write-Info "Deployment Complete!"
    Write-Info "=========================================="
    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host "1. Access Azure Portal and navigate to Microsoft Sentinel"
    Write-Host "2. Select the workspace: $LAW_NAME"
    Write-Host "3. Go to Analytics > Active rules to view imported rules"
    Write-Host "4. View Falco Security Dashboard: Monitor > Workbooks > Falco Security Dashboard"
    Write-Host "5. Test Falco by running: kubectl run test-pod --image=alpine --rm -it -- sh"
    Write-Host "6. Check logs in Log Analytics with query: FalcoLogs_CL | take 10"
    Write-Host ""
    Write-Info "Logic App Webhook:"
    Write-Host "- The webhook URL contains a SAS signature and is intentionally not printed."
    Write-Host "- To inspect locally: az logic workflow show-callback-url -g $RESOURCE_GROUP -n $LOGIC_APP_NAME --trigger-name $LOGIC_APP_TRIGGER --query value -o tsv"
    Write-Host "- View Logic App runs in Azure Portal: Logic Apps > $LOGIC_APP_NAME > Overview"
    Write-Host ""
    Write-Info "Useful Commands:"
    Write-Host "- View Falco logs: kubectl logs -n falco -l app.kubernetes.io/name=falco -f"
    Write-Host "- View Falcosidekick logs: kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick -f"
    Write-Host "- Test with a violation: kubectl exec -it <pod-name> -- cat /etc/shadow"
    Write-Host ""
}

#endregion

#region Main Execution

function Main {
    Write-Info "Starting Falco AKS Demo Deployment"
    Write-Info "===================================="
    
    try {
        Test-Prerequisites
        Connect-AzureAccount

        if ($EnableRulesOnly) {
            Get-DeploymentOutputs
            Wait-ForFalcoLogs
            Import-SentinelRules
            Deploy-Workbook
            return
        }

        New-ResourceGroup
        Deploy-Infrastructure
        Get-DeploymentOutputs
        Get-WebhookUrlSilently
        Set-KubectlContext
        Install-Falco
        Test-Deployment

        if ($SkipRules) {
            Write-Info "Skipping Sentinel rules (per -SkipRules). Run again with -EnableRulesOnly later."
        } else {
            Wait-ForFalcoLogs
            Import-SentinelRules
            Deploy-Workbook
        }

        Show-NextSteps
    }
    catch {
        Write-ErrorMessage "An error occurred during deployment: $_"
        Write-ErrorMessage $_.ScriptStackTrace
        exit 1
    }
}

# Run main function
Main

#endregion
