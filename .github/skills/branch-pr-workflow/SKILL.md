---
name: branch-pr-workflow
description: Enforce this repository's branching and pull request workflow before making or committing any changes. Use this at the start of any task that will modify files in this repository, including small edits, to ensure work happens on a feature branch instead of main.
license: MIT
---

The `main` branch is **protected** and must never be committed to directly.

## Before making any change

1. Check the current branch: `git branch --show-current`.
2. If on `main` (or any other protected/shared branch), create a new branch
   first:

   ```bash
   git checkout -b feature/<short-description>
   ```

   Use a short, kebab-case description of the change, e.g.
   `feature/add-cilium-gateway-api`, `feature/fix-keda-scaler-bug`.
3. Only then start editing files.

## While working

- Keep each branch/PR focused on **one logical change** — don't mix unrelated
  fixes or features.
- Write descriptive commit messages explaining *what* changed and *why*, not
  just *what*.
- Re-run any relevant linters/validators for the files you touched (see the
  `scaffold-new-demo` and `terraform-lifecycle` skills) before committing.

## Opening the PR

```bash
git push -u origin feature/<short-description>
gh pr create --base main --title "<concise summary>" --body "<what changed and why>"
```

Target `main` as the base branch. Do not merge directly to `main` without a
pull request, even for trivial changes.
