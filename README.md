# CICD — org security & CI/CD baseline

Enterprise-grade, Free-tier-aware GitHub org rulesets plus reusable CI/security workflows.

## What's here
- **`rulesets/`** — org repository rulesets (branch/tag/push), an idempotent `apply.sh`, and
  `capture-contexts.sh` to verify required-check names before locking enforcement.
  **Start with [`rulesets/README.md`](rulesets/README.md)** — full guide, tiers, rollout order.
- **`.github/workflows/`** — reusable workflows called by every repo:
  - `ci.yml` — `lint · format · test · e2e · build(+smoke)` (language-agnostic, via `make`)
  - `security.yml` — gitleaks · trivy · CodeQL (opt-in)
- **`templates/`** — drop-in files each consuming repo copies: caller workflows, the `Makefile`
  contract, `CODEOWNERS`, `lefthook.yml` (client hooks), `.gitleaks.toml`, `.trivyignore`.

## How it fits
Each repo adds ~5-line caller workflows (`templates/caller-*.yml`) that call the reusable
workflows here at a pinned tag (`@v1`). The repo implements the `make` contract for its stack.
Reusable-workflow jobs surface as checks (`ci / lint`, `security / trivy`, ...) that the org
rulesets require. Merges are gated on those checks + review + signed (squash) commits.

## Quick start
See [`rulesets/README.md`](rulesets/README.md) → *Rollout order*: tag `v1` → seed a pilot repo →
`capture-contexts.sh` → apply scoped to pilot → widen to `~ALL`.
