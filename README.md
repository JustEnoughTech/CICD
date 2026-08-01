# CICD — org security & CI/CD baseline

Enterprise-grade, Free-tier-aware GitHub org rulesets plus reusable CI/security workflows.

## What's here
- **`rulesets/`** — org repository rulesets (branch/tag/push), an idempotent `apply.sh`, and
  `capture-contexts.sh` to verify required-check names before locking enforcement.
  **Start with [`rulesets/README.md`](rulesets/README.md)** — full guide, tiers, rollout order.
- **`.github/workflows/`** — reusable workflows called by every repo:
  - `ci.yml` — `lint · format · test · e2e · build(+smoke) · dast` (language-agnostic, via `make`)
  - `security.yml` — `secrets · trivy · sast · sca · sbom`
  - `codeql.yml` — separate and **opt-in** (needs `security-events: write`)
- **`templates/`** — drop-in files each consuming repo copies: caller workflows, the `Makefile`
  contract, `CODEOWNERS`, `lefthook.yml` (client hooks), `.gitleaks.toml`, `.trivyignore`.

## The lanes

Every lane **either gates on a stated threshold or is documented artifact-only**. There is no
third category — a scanner that only warns is decoration.

| Check context | Tool | `make` target | Gates on | Threshold input |
|---|---|---|---|---|
| `security / secrets` | gitleaks | *(in-workflow)* | any secret in the PR range | — |
| `security / trivy` | trivy | `trivy` | fixable `HIGH,CRITICAL` | *(in the Makefile)* |
| `security / sast` | njsscan (Node), bandit (Python) | `sast` | findings ≥ `ERROR` | `sast-severity` |
| `security / sca` | osv-scanner | `sca` | **fixable** vulns ≥ `CRITICAL` | `sca-severity`, `sca-fixable-only` |
| `security / sbom` | syft | `sbom` | **nothing — artifact-only** | *(none by design)* |
| `ci / dast` | OWASP ZAP baseline | `dast-up` / `dast-down` | ZAP `FAIL`-level alerts | `zap-fail-on` |

Every tool version is also an input (`trivy-version`, `osv-scanner-version`, `syft-version`,
`bandit-version`, `njsscan-version`, `gitleaks-version`, `zap-image`), so a caller can pin or
bump without editing this repo.

### Why the defaults start loose, and the ratchet

SCA and container lanes default to **fixable CRITICAL**, SAST to **ERROR**. Fixable-only is
deliberate: an unfixable upstream CVE would otherwise block every merge with no remediation
available to the person blocked by it. This is a deliberate **first step, not the target
posture** — the ratchet is CRITICAL → HIGH once the repos are clean. Tighten per-repo from the
caller (`sca-severity: HIGH`) before changing the default here.

### Honest degradation

Lanes that cannot run must say so out loud. None of these is a silent pass:

- **`sca` with no lockfile** — osv-scanner exits `128`; the lane passes and *prints why*. Any
  exit other than `0`/`1`/`128` is an infrastructure failure and goes **red**.
- **`dast` with no bootable HTTP service** — the repo must set `DAST_OPT_OUT=true` with a
  reason. Leaving `DAST_TARGET` unset **hard-fails**, so a missing config can't read as green.
- **`dast` with an unreachable target** — ZAP exit `3` means nothing was scanned. That is an
  **infrastructure failure, red**, never a clean pass.

## Deliberately NOT here

- **No SARIF upload in any mandatory lane.** `github/codeql-action/upload-sarif` needs GHAS on
  private repos and would `403` on all 15 GT repos. Findings ship as **workflow artifacts**;
  the exit code is the gate. CodeQL stays in its own opt-in workflow for the same reason
  (`security-events: write` triggered a startup escalation error for every caller).
- **No CBOM lane.** CBOMkit is a web application requiring Postgres, and `cbomkit-theia` ships
  no prebuilt binaries and has no fail-on-findings concept at all. Neither can act as a PR gate.
  **CBOM is a release-time aggregation activity, not a PR gate** — it belongs where the
  consuming project already places it. An absent lane, documented, beats a present lane that
  proves nothing.
- **No signing / attestation lane — deliberately deferred.** It needs `id-token: write` +
  `attestations: write`, so it lands in its own opt-in `supply-chain.yml`, **together with the
  verifier that consumes it**. Building an attestation nothing verifies is unverified
  machinery — the same trap as a gate never observed failing.
- **No opengrep lane yet — blocked on rule licensing, not on the engine.** The opengrep engine
  is LGPL-2.1 and genuinely free. Its *rules* are the problem. `semgrep/semgrep-rules` was
  relicensed on **2024-12-13** to the proprietary **Semgrep Rules License v1.0** ("You may use
  the rules only for your own internal business purposes… does not allow you to distribute the
  rules"), which forbids vendoring them into **this public repo**. Before that it was LGPL-2.1
  **+ Commons Clause** — never plain LGPL, and never OSI-approved. `opengrep/opengrep-rules` is
  archived, self-contradictory on licensing, and self-described as for research only. Clean
  MIT-licensed alternatives exist (apiiro, elttam, dgryski/semgrep-go, 0xdea) and are the
  intended path; wiring them is a follow-up. **`sast` is not empty in the meantime** — bandit
  (Apache-2.0) and njsscan (LGPLv3+) ship their own rules with no licensing question.

## Adding these to the ruleset

`rulesets/*.json` is **deliberately untouched** by the change that added these lanes. A required
check that never reports blocks merges permanently, and the consuming org has no working CI and
no self-hosted runner registered yet — wiring them in now would hard-block every PR in 15 repos.

The rollout is mechanical once the lanes are observed green on a real repo. Add these exact
context strings to `required_status_checks` in `rulesets/01-branch-default.json`:

```
security / sast
security / sca
security / sbom
ci / dast
```

Verify them first with `rulesets/capture-contexts.sh`, then `rulesets/apply.sh`.

## How it fits
Each repo adds ~5-line caller workflows (`templates/caller-*.yml`) that call the reusable
workflows here at a pinned tag (`@v1`). The repo implements the `make` contract for its stack.
Reusable-workflow jobs surface as checks (`ci / lint`, `security / trivy`, ...) that the org
rulesets require. Merges are gated on those checks + review + signed (squash) commits.

## Quick start
See [`rulesets/README.md`](rulesets/README.md) → *Rollout order*: tag `v1` → seed a pilot repo →
`capture-contexts.sh` → apply scoped to pilot → widen to `~ALL`.
