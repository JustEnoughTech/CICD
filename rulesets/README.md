# Org Rulesets — Enterprise Baseline

Org-wide GitHub rulesets for security + performance. API JSON, all repos (`~ALL`),
`active` enforcement with an org-admin break-glass bypass (`pull_request` mode where it matters).

## Files

| File | Target | Enforces | Tier needed |
|------|--------|----------|-------------|
| `01-branch-default.json` | default branch | PR (1 approval, code owners, stale dismiss, last-push approval), status checks (strict), signed commits, linear history, no force-push, no delete | Free (public) / Team (private) |
| `02-branch-release.json` | `release/*`, `hotfix/*` | Same as default, tighter | Free (public) / Team (private) |
| `03-tag-release.json` | `v*`, `release-*` tags | No delete/update, signed tags, semver name pattern | Free (public) / Team (private) |
| `04-push-hardening.json` | push | Max 100 MB file, block secret/binary extensions + paths, path length cap | **Enterprise only** |
| `05-branch-metadata.json` | all branches | Corp-domain author email, conventional-commit subject | **Enterprise** (org scope) |

## Tier note (you're on Free/unsure)
- **Public repos**: 01–03 work now, free.
- **Private repos**: need **Team** for org-wide 01–03.
- **04 + 05**: **Enterprise Cloud** only — comment them out of `apply.sh` until then.

## Before applying — edit these
1. `05-branch-metadata.json` → replace `@YOURDOMAIN.com` with your org domain (or delete file 05).
2. Bypass = break-glass **team**. Set `BREAK_GLASS_TEAM=<team-slug>` when running `apply.sh` —
   it resolves the slug to an id and injects it (`pull_request` mode) into every ruleset.
   Unset = falls back to the `OrganizationAdmin` bypass baked in each JSON.
   PR approvals required = **1**.
3. `required_status_checks` contexts (`ci / lint`, `ci / format`, `ci / test`, `ci / e2e`,
   `ci / build`, `security / secrets`, `security / trivy`) must match the REAL check-run names.
   Verify with `capture-contexts.sh` on a pilot repo first (see rollout below) — a wrong string
   leaves every PR hung on a check that never reports.
4. **Repo-level merge settings (L2)** — each target repo's Settings → General → Pull Requests
   must have **"Allow squash merging" ON** and **"Allow merge commits" + "Allow rebase merging"
   OFF**, to match the squash-only ruleset (`allowed_merge_methods: ["squash"]`). Mismatch =
   contributors see merge options the ruleset then rejects. Also enable
   **"Automatically delete head branches"** to keep the branch list clean.

## Enforcement modes
- `active` — enforced, blocks violations. (set here)
- `evaluate` — audit-only, logs but blocks nothing. **Enterprise only.** Good first-rollout step.
- `disabled` — saved, inert.

Bypass `bypass_mode`: `always` (skip anytime) vs `pull_request` (only via PR merge, still audited).

## Apply (nothing runs until you do this)
```bash
gh auth login                       # scope: admin:org
cd rulesets
ORG=my-org BREAK_GLASS_TEAM=sre DRY_RUN=1 ./apply.sh   # preview, no API calls
ORG=my-org BREAK_GLASS_TEAM=sre ./apply.sh             # create rulesets
gh api /orgs/my-org/rulesets | jq '.[].name'   # verify
```

## Rollback
```bash
# list ids
gh api /orgs/my-org/rulesets | jq '.[] | {id, name}'
# delete one
gh api --method DELETE /orgs/my-org/rulesets/<id>
```

## Layer 2 — the workflows that PRODUCE these checks
The ruleset is only the gate. The checks it requires come from reusable workflows in this repo:

```
.github/workflows/ci.yml         reusable: jobs lint, format, test, e2e, build(+smoke)
.github/workflows/security.yml   reusable: jobs secrets (gitleaks), trivy (make trivy)  [contents:read only]
.github/workflows/codeql.yml     reusable: CodeQL analyze — OPT-IN (needs security-events:write)
templates/caller-ci.yml          copy to each repo -> .github/workflows/ci.yml
templates/caller-security.yml    copy to each repo -> .github/workflows/security.yml
templates/caller-codeql.yml      OPT-IN -> .github/workflows/codeql.yml (grants security-events:write)
templates/Makefile               the language-agnostic contract each repo implements
templates/CODEOWNERS             copy to each repo -> .github/CODEOWNERS
templates/lefthook.yml           copy to each repo root -> client-side hooks (make hooks)
templates/.gitleaks.toml         copy to each repo root -> secret-scan false-positive allowlist
templates/.trivyignore           copy to each repo root -> accepted trivy findings by ID
```

**Trivy scope (M4):** `make trivy` gates on **`vuln` only** (HIGH/CRITICAL, fixable CVEs in deps)
— low false-positive signal. `misconfig` (noisy IaC nits) and `secret` (gitleaks already owns it)
are dropped from the blocker; a commented line in `templates/Makefile` opts them back in per repo.

**Secret scan rollout (C3):** PR runs scan only the PR's new commits (`base..head`) — legacy
secrets already in history don't block merges. The weekly schedule scans full history as an
alert. Tune false positives via `.gitleaks.toml` (rule-level) or `.gitleaksignore` (per-finding
fingerprint from a failed run). Real secrets → rotate + purge, never allowlist.

**CI minutes (Free org)**
- Callers use a **PR-only** trigger (no `push`) + draft-skip + `concurrency` cancel → ~1 run per
  meaningful PR update. No `paths-ignore` (it strands required checks in "pending" forever).
- **Lever 1 — client hooks** (`templates/lefthook.yml` + `make hooks`): runs the same `make`
  lanes at commit/push on the dev's machine (0 Actions minutes), so failures are caught before
  CI. Advisory only (`--no-verify` bypasses); CI stays the server-side gate.
  - pre-commit: `format-check`, `lint`, `secrets` (gitleaks staged scan — stops a secret
    before it's even committed)
  - pre-push: `test`, `trivy`

**Supply chain (H2):** `make trivy`/`secrets` install pinned, **sha256-verified** release
binaries (no `curl|sh` from an unpinned branch); self-guard so `brew`-installed tools are
reused. CI caches the trivy vuln DB weekly (`~/.cache/trivy`). Gitleaks download in CI is
checksum-verified too.

**How it fits together**
1. This repo hosts the reusable workflows. Tag it `v1` (`git tag v1 && git push origin v1`).
2. Each repo drops in the two caller files + a `Makefile` implementing the contract targets.
3. Reusable jobs surface as checks named `ci / lint`, `ci / test`, `security / secrets`, ... —
   exactly the contexts required in `01`/`02`. Names MUST match or merges hang forever.

**Language-agnostic contract** (`templates/Makefile`): CI shells out to
`make lint | format-check | test | e2e | build | smoke`. Each repo implements them for its
stack (npm/go/pytest/...). No lane? Make it `@true` — explicit opt-out, never a silent skip.
Toolchain setup goes in `bootstrap`; lanes depend on it, so the workflow stays stack-neutral.

**Deploy gate = build-only**: `make build` builds the image, `make smoke` boots it and hits
the healthcheck. No live deploy in CI.

**Rollout order — pilot → verify names → lock → widen** (avoids the trap where a required
check that GitHub never reports leaves every PR hung on "Expected — Waiting for status"):

1. **Tag** this repo `v1` (`git tag v1 && git push origin v1`).
2. **Seed a pilot repo**: copy `templates/` (callers, Makefile, CODEOWNERS, lefthook.yml,
   .gitleaks.toml), implement the `make` targets, open a PR so the workflows run once.
3. **Verify the exact check names** — reusable-workflow checks are `<caller-job> / <job>`, and
   if the ruleset requires a string GitHub never emits, PRs hang forever:
   ```bash
   rulesets/capture-contexts.sh <ORG> <pilot-repo>     # OK / MISSING per required context
   ```
   Fix any `MISSING` (rename ruleset context or the job) before enforcing.
4. **Lock on the pilot only**: narrow `repository_name.include` to the pilot, `apply.sh`, shake out.
5. **Widen to `~ALL`** once green. Seed callers/Makefile into other repos via a script or an
   org template repo first, so they have the checks before the ruleset demands them.

> Free-org note: `evaluate` (audit) mode is Enterprise-only, so this pilot-scoped rollout **is**
> your safe substitute for audit mode.

## Review policy (M2 — small 2-3 team)
- `required_approving_review_count: 1`, `require_code_owner_review: true`,
  `dismiss_stale_reviews_on_push: true` (approval cleared when code changes),
  **`require_last_push_approval: false`** (removes the "a *different* person must approve the
  last push" deadlock that stalls small teams).
- **Bot / 2nd-account reviewer path** (your chosen no-reviewer fallback). Two hard constraints:
  - GitHub **Apps cannot approve PRs** — use a real **machine user account** (service account)
    with write access, not an App.
  - For its approval to satisfy `require_code_owner_review`, that account **must be listed in
    `CODEOWNERS`** — otherwise the approval doesn't count as a code-owner review.
  - It consumes the single required approval. Use it for genuine solo/stuck cases; a bot that
    auto-approves everything nullifies review. Gate its approval on CI-green if you automate it.

## Commit signing (M1 — zero-friction path)
`required_signatures` stays **on**, but `allowed_merge_methods` is **squash-only**. Every commit
reaching a protected branch is a GitHub-*created* squash commit, which GitHub signs → the rule is
satisfied **without any developer configuring GPG/SSH signing**. Direct pushes to `main` are
blocked (PR required), so there's no unsigned path in. Trade-off: no rebase-merge (each PR
collapses to one commit on `main`). To keep per-commit history instead, switch to rebase +
roll out SSH signing to all devs and bots — heavier onboarding.

## Also enable (not rulesets, but pairs with them)
- Secret scanning + **push protection** (org settings → Code security) — complements gitleaks
- Dependabot alerts + security updates
- Require 2FA for org members
- CODEOWNERS per repo (`templates/CODEOWNERS`) — file 01 requires code-owner review
- CodeQL: opt in per repo by adding `templates/caller-codeql.yml` (it grants the required
  `security-events:write`); then optionally add a `code_scanning` alert-gate rule + require the
  `codeql / analyze` context in `01`
