using './main.bicep'

param location = 'northeurope'
param namePrefix = 'plkdemo'
param adminUsername = 'azureuser'

// Password is injected at deploy time from deploy.sh via the ADMIN_PASSWORD
// env var (auto-generated, Azure-compliant). You can override by exporting
// ADMIN_PASSWORD before running ./deploy.sh.
param adminPassword = readEnvironmentVariable('ADMIN_PASSWORD', '')

param vmSize = 'Standard_B2s'
