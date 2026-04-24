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
