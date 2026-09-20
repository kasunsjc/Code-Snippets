---
name: scaffold-new-demo
description: Scaffold a new demo folder in this repository (Code-Snippets) so it follows repo conventions and is picked up correctly by the README generator. Use this when asked to add a new demo, example, sample, or tutorial folder to the repository.
license: MIT
---

Use this skill whenever a new top-level demo/example folder is being added to this
repository (e.g. `AKS-<Feature>-Demo`, `Docker-<Feature>`, `ACR-<Feature>`, etc.).

## 1. Branch first

Always create a `feature/<short-description>` branch before creating any files
(the `main` branch is protected — see the repo's Coding Best Practices).

## 2. Choose a folder name that matches the auto-categorizer

`scripts/generate-readme.sh` assigns a category to every top-level folder based on
its name prefix (see the `categorize()` function):

- `AKS-*`, `Agentic-CLI-AKS`, `BYO-CNI-AKS`, `Custom-AKS-Copilot-Agent`,
  `Platform-Enginering-AKS-ArgoCD-ASO` → **Kubernetes**
- `Docker-*` → **Docker**
- `ACR-*` → **Azure**
- anything else → **Other**

Pick a prefix that matches the intended category, or update `categorize()` in
`scripts/generate-readme.sh` if a new prefix/category is genuinely needed.

## 3. Required folder contents

- `README.md` is **mandatory** — the `check-readme-exists` CI job warns on any
  top-level demo folder missing one. The generator extracts:
  - **Title**: the first `# ` (H1) heading.
  - **Description**: the first non-empty line right after the H1 (truncated to
    ~100 chars in the root README table), so keep that line a short, plain-English
    summary — no markdown links/badges on that specific line.
- If the demo has Terraform, follow the AKS/IaC conventions already documented in
  `.github/copilot-instructions.md`:
  - Set an explicit, readable `node_resource_group` (Bicep) or
    `--node-resource-group` (Azure CLI) for any AKS cluster, following the pattern
    `rg-<project>-<env>-nodes`.
  - Include/point to a cleanup script that runs `terraform destroy` and removes
    local state files and the `.terraform` provider folder.
- Shell scripts must start with a shebang and should use `set -e` (or
  `set -euo pipefail`) for strict error handling — `lint-shell-scripts` in
  `pr-validation.yml` runs `shellcheck -S warning -e SC2034,SC2046,SC2207` on every
  `*.sh` file that has a shebang.
- YAML files are linted with `yamllint` (relaxed ruleset, 200 char line length) —
  see the `validate-yaml` job in `.github/workflows/pr-validation.yml`.
- Bicep files are validated with `bicep build`; Terraform files are checked with
  `terraform fmt -check` and `terraform validate` for any changed directory.
- Do not commit secrets, credentials, or subscription-specific values — use
  variables/parameter files instead.

## 4. Regenerate the root README

After adding the folder and its README.md, invoke the `readme-sync` skill (or run
`bash scripts/generate-readme.sh` directly) to regenerate the root `README.md`
table of contents and category sections. Do not hand-edit the auto-generated
block between the `AUTO-GENERATED CONTENT` markers.

## 5. Validate before opening the PR

Run the checks relevant to the files you added, mirroring CI:

```bash
# Shell scripts with a shebang
shellcheck -S warning -e SC2034,SC2046,SC2207 path/to/script.sh

# Terraform (per changed directory)
terraform -chdir=path/to/terraform fmt -check
terraform -chdir=path/to/terraform init -backend=false -input=false
terraform -chdir=path/to/terraform validate

# YAML
pip install yamllint
yamllint path/to/file.yaml
```

Then commit on the feature branch and open a PR into `main`.
