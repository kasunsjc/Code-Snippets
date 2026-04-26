using './main.bicep'

param location = 'northeurope'
param namePrefix = 'plkdemo'
param adminUsername = 'azureuser'

// Replace with your own SSH public key, or let deploy.sh inject it from
// ~/.ssh/id_rsa.pub at deployment time.
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')

param vmSize = 'Standard_B2s'
