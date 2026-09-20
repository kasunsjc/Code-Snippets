---
name: terraform-lifecycle
description: Apply this repository's Terraform and AKS infrastructure-as-code conventions when creating, formatting, validating, or tearing down Terraform-based demos. Use this when asked to write, review, or clean up Terraform code, or provision/destroy an AKS cluster in this repo.
license: MIT
---

This repository uses **Terraform** as its IaC tool of choice (see
`.github/copilot-instructions.md` → IaC Tools). Apply these conventions to any
Terraform-based demo folder.

## Authoring

- Set an explicit `node_resource_group` for every AKS cluster resource —
  never rely on the AKS-generated default (`MC_<rg>_<cluster>_<region>`).
  Follow the naming pattern `rg-<project>-<env>-nodes`, e.g.
  `rg-agfc-demo-dev-nodes`. See `AKS-ArgoCD-Extension/terraform/main.tf` and
  `AKS-ACNS-Cilium-Terraform/terraform/main.tf` for existing examples.
- Prefer ID-based arguments for related AzureRM resources when the provider
  supports them (e.g. `storage_account_id`, `user_assigned_identity_id`) rather
  than name/legacy arguments — see `AKS-KEDA-Demo/terraform/modules/`.
- Never commit secrets, subscription IDs, or credentials — use variables or
  `.tfvars` files (excluded from git) instead.
- Always format before committing:

  ```bash
  terraform -chdir=<demo>/terraform fmt
  ```

## Validating (mirrors CI)

`terraform-validate-scheduled.yml` and the PR-triggered `validate-terraform` job
in `pr-validation.yml` run, for each changed Terraform directory:

```bash
terraform -chdir=<demo>/terraform fmt -check
terraform -chdir=<demo>/terraform init -backend=false -input=false
terraform -chdir=<demo>/terraform validate
```

Run these locally before opening a PR to catch formatting/validation failures
early.

## Cleanup

Every Terraform demo should ship (or document) a cleanup path that:

1. Runs `terraform destroy` (or the folder's provided cleanup script) to remove
   all provisioned Azure resources and avoid orphaned resources/cost.
2. Removes local Terraform state files (`terraform.tfstate`,
   `terraform.tfstate.backup`) — scrub any sensitive data before ever committing
   state; prefer remote state with access controls for anything beyond a demo.
3. Removes the local `.terraform` provider/plugin cache folder so future runs
   aren't affected by stale provider versions.

When asked to "clean up" or "tear down" a Terraform demo in this repo, perform
all three steps above, not just `terraform destroy`.
