# Copilot Instructions

## Branching Strategy

- The `main` branch is **protected** and does not accept direct pushes.
- Always create a **feature branch** before making any changes.
- Use the naming convention: `feature/<short-description>` (e.g., `feature/add-cilium-gateway-api`).
- Commit changes to the feature branch and open a **pull request** to merge into `main`.

## Coding Best Practices

- Follow existing code style and conventions in each project folder.
- Use descriptive commit messages that explain *what* changed and *why*.
- Keep changes focused — one logical change per branch/PR.
- Do not commit secrets, credentials, or sensitive values. Use environment variables or parameter files.
- Ensure shell scripts use `set -e` for strict error handling.
- Test scripts and templates locally before committing when possible.
- Use consistent indentation (spaces, not tabs) across all file types.

## AKS Conventions

- Always specify a **readable, custom node resource group name** instead of relying on AKS defaults (e.g., `MC_<rg>_<cluster>_<region>`).
- Use the `nodeResourceGroup` property in Bicep or the `--node-resource-group` flag in Azure CLI.
- Follow the naming pattern: `rg-<project>-<env>-nodes` (e.g., `rg-agfc-demo-dev-nodes`).

## IaC Tools
- Use **Terraform** for infrastructure provisioning and management.
- When cleaning up, use `terraform destroy` or the provided cleanup script to avoid orphaned resources. 
- Use `terraform fmt` to format Terraform files before committing.
- Use `terraform validate` to check for syntax errors and configuration issues.
- When cleanup script is run, ensure that all resources are destroyed and no orphaned resources remain in Azure. and also remove any local state files if applicable.
- Remove any sensitive information from Terraform state files before committing to version control. Use remote state storage with proper access controls for production environments.
- Remove the Terraform provider folder when cleanup script is run to avoid any potential issues with provider versions in future deployments.