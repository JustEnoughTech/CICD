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
| `security / sast` | opengrep (vendored rules), njsscan, bandit, eslint-plugin-security | `sast` | findings ≥ `ERROR` | `sast-severity` |
| `security / sca` | osv-scanner | `sca` | **fixable** vulns ≥ `CRITICAL` | `sca-severity`, `sca-fixable-only` |
| `security / sbom` | syft | `sbom` | **nothing — artifact-only** | *(none by design)* |
| `security / trivy-image` | trivy | `trivy-image` | fixable `CRITICAL` in the built image | `trivy-image-severity` |
| `security / versions` | curl | `versions-check` | any pinned version no longer downloadable | *(n/a)* |
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
- **`trivy-image` with no image** — the repo must set `TRIVY_IMAGE_OPT_OUT=true` with a reason.
  An unset `IMAGE` **hard-fails**: a container lane that scans nothing looks exactly like a
  container with no vulnerabilities.
- **`sast` with a missing or empty rules directory** — hard-fails. A scan with no rules finds
  nothing and is indistinguishable from clean code.

### What `ci / dast` actually buys you today

Be clear-eyed about this one. ZAP's baseline profile marks almost nothing as `FAIL` by default,
so with `zap-fail-on: FAIL` the lane tolerates the WARN-level findings a typical service produces
(missing CSP, `X-Content-Type-Options`, clickjacking headers). **Its proven value today is
catching a service that does not come up at all** (ZAP exit 3) — real, but modest. This is
passive scanning only; it is **not** full dynamic coverage and should not be read as such.
Giving the lane teeth means a ZAP rules config promoting specific rules to `FAIL`; that is a
filed follow-up, not something this pipeline does yet.

## Runner prerequisites

All lanes were proven on GitHub-hosted `ubuntu-latest`. The 15 GT repos will run on a
**self-hosted runner**, so its image must provide:

| Requirement | Needed by | Why |
|---|---|---|
| **Actions runner ≥ v2.329.0** | checkout v7, upload-artifact v7, cache v6 | v2.327.1 is the Node 24 floor — below it **all three actions fail**, not just one. v2.329.0 additionally covers checkout v6's credential-file change for Docker container actions. |
| `docker` (daemon reachable) | `ci / dast`, `security / trivy-image` | ZAP runs as a container; the image scan needs a built image. |
| `python3` + `pip` | `security / sast` | bandit, njsscan. |
| `node` + `npx` | `security / sast` | eslint-plugin-security. |
| write access to `/usr/local/bin` | trivy, syft, osv-scanner, opengrep, gitleaks | the pinned-installer targets install there. |
| `curl`, `jq`, `git`, `make` | everything | assumed present. |

`actions/upload-artifact@v4+` is **not supported on GHES** — if that runner attaches to a GitHub
Enterprise Server instance, artifacts need a different approach.

## Dependabot

`templates/dependabot.yml` (consumers: actions/npm/pip) and `.github/dependabot.yml` (this repo:
actions). It runs **GitHub-side — no runner, no Actions minutes**, so it is unaffected by the org's
`$0` spending limit. While CI is unfunded, it is the only dependency control that actually
executes.

⚠️ **Committing the file does not enable it.** Dependabot is a per-repo (or org-default) setting
the owner must switch on — *Settings → Code security*. Version updates and security updates are
**separate toggles**; turn both on. A config file with the feature disabled is exactly the
"documented but off" pattern this repo drops lanes to avoid, so verify it per repo.

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
- **No CodeQL in any mandatory path.** The GT repos are private, and CodeQL's licence forbids use
  on non-open-source code without GitHub Advanced Security. `codeql.yml` stays opt-in.

## SAST coverage — what it is and is not

The opengrep lane runs **245 vendored rules from four MIT-licensed sources**, pinned by commit
SHA with per-source licence provenance in [`rules/README.md`](rules/README.md). **123 of them are
`ERROR` severity and can therefore fail a build**; the rest report into the artifact only.

Rules are **vendored, never fetched**. `--config p/ci` would resolve to Semgrep Inc.'s registry
under the proprietary **Semgrep Rules License v1.0** (*"only for your own internal business
purposes… does not allow you to distribute the rules"*) — which also rules out
`semgrep/semgrep-rules` itself, relicensed to those same terms on 2024-12-13 and never plain
LGPL-2.1 before that (it was LGPL-2.1 **+ Commons Clause**). A registry fetch also cannot work in
the air-gapped delivery flavour.

**This is a deliberate, auditable subset — not parity with the Semgrep registry**, which carries
thousands of rules. Coverage is uneven by design of what is available under MIT: Go, C/C++ and
malicious-code/obfuscation patterns are well covered; **Python, JS/TS and C# are thin**, which is
why `sast` also runs bandit (Python), njsscan and eslint-plugin-security (Node). There is no
broad language-agnostic injection ruleset. Buying registry breadth is a **licensing decision to
be made consciously**, not a gap to close by quietly re-adding `p/ci`.

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
security / trivy-image
security / versions
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
