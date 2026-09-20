---
name: readme-sync
description: Regenerate the root README.md table of contents, category listings, and blog mappings for this repository. Use this after adding, renaming, removing, or re-describing a demo folder, or whenever the root README's auto-generated content looks stale.
license: MIT
---

The root `README.md` has an auto-generated section between the
`<!-- AUTO-GENERATED CONTENT BELOW - DO NOT EDIT MANUALLY -->` and
`<!-- AUTO-GENERATED CONTENT ABOVE - DO NOT EDIT MANUALLY -->` markers. **Never
hand-edit this section** — it is produced by `scripts/generate-readme.sh` and is
also regenerated automatically by the `update-readme.yml` GitHub Actions workflow.

## Regenerating locally

```bash
bash scripts/generate-readme.sh
```

This script:
1. Scans every top-level directory (skipping `.git`, `.github`, `scripts`,
   `node_modules`, `.DS_Store`).
2. Categorizes each one via the `categorize()` function (Kubernetes / Docker /
   Azure / Other — see the `scaffold-new-demo` skill for the exact prefix rules).
3. Extracts a title (first `# ` heading) and description (first non-empty line
   after the heading, truncated to ~100 chars) from each folder's `README.md`.
4. Calls `scripts/generate_blog_mappings.py` to emit the "Related Blog Posts"
   table by matching blog RSS feed entries to demo folders. This step is
   best-effort: if all feeds are unreachable it must not fail README
   generation — treat any errors here as non-fatal.
5. Rewrites `README.md` with updated stats, table of contents, and per-category
   sections.

## Validating the generator itself

If you changed `scripts/generate-readme.sh` or `scripts/generate_blog_mappings.py`,
run the existing test script rather than hand-verifying output:

```bash
bash scripts/test-generate-readme.sh
```

This builds a throwaway temp repo with sample demo folders/READMEs, runs the
generator against it, and asserts on specific lines/counts in the resulting
README (e.g. blog mappings appearing exactly once, correct title/description
extraction).

## Workflow

1. Make sure demo folder README.md files have a clean H1 title and a short,
   link-free description line right after it (this is what ends up in the table).
2. Run `bash scripts/generate-readme.sh`.
3. Diff `README.md` and confirm only the auto-generated section changed.
4. Commit the regenerated `README.md` alongside your other changes on the
   feature branch — do not rely solely on the scheduled/CI `update-readme.yml`
   workflow if the PR should show the updated README immediately.
