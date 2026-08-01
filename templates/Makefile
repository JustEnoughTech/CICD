# CI contract. The reusable CI workflow calls these targets by name.
# Every repo MUST define all of them. No lane for your repo? Make it a no-op
# (`@true`) — an explicit, visible opt-out beats a silently skipped check.
#
# Put toolchain/dependency install in `bootstrap`; lanes depend on it, so CI
# never needs stack-specific setup steps.
.PHONY: bootstrap lint format-check format test e2e build smoke trivy secrets hooks \
        sast njsscan bandit sca sbom dast dast-target dast-up dast-down \
        _ensure-trivy _ensure-gitleaks _ensure-osv _ensure-syft

# Install deps / toolchain. Examples:
#   npm ci   |   pnpm i --frozen-lockfile   |   go mod download   |   pip install -r requirements.txt
bootstrap:
	@true

# Static analysis. eslint / golangci-lint / ruff / clippy ...
lint: bootstrap
	@echo "define: lint" && false

# Formatting must be standardized and VERIFIED (not auto-applied) in CI.
# prettier --check . | gofmt -l . | black --check . | cargo fmt --check
format-check: bootstrap
	@echo "define: format-check" && false

# Local convenience: auto-fix formatting (not run in CI).
format:
	@echo "define: format (prettier --write / gofmt -w / black .)"

# Install client-side git hooks (Lever 1). Run once after cloning.
# lefthook.yml drives which make targets fire at commit/push.
hooks:
	@command -v lefthook >/dev/null 2>&1 || { \
	  echo "lefthook not found — install: https://github.com/evilmartians/lefthook#install"; \
	  echo "  (brew install lefthook | npm i -D lefthook | go install github.com/evilmartians/lefthook@latest)"; \
	  exit 1; }
	lefthook install

# Unit + sanity tests. vitest / jest / go test ./... / pytest
test: bootstrap
	@echo "define: test" && false

# End-to-end. playwright test / cypress run / go test -tags e2e ...
# No e2e yet? Replace body with `@true` to opt out explicitly.
e2e: bootstrap
	@echo "define: e2e (or @true to opt out)" && false

# Build the deployable artifact/image. docker build / go build / npm run build
build: bootstrap
	@echo "define: build" && false

# Build-only deploy gate: boot the artifact and hit its healthcheck.
# e.g. docker run -d --name smoke -p 8080:8080 img && \
#      for i in $$(seq 1 30); do curl -fsS localhost:8080/health && exit 0; sleep 2; done; exit 1
smoke: build
	@echo "define: smoke" && false

# Trivy vuln/misconfig/secret scan. Fails on HIGH+CRITICAL. Adapter: swap the
# `fs` scan for an image scan (`trivy image $(IMAGE)`) if you build one in `build`.
# `.trivyignore` in repo root suppresses accepted findings. Install = pinned
# release tarball + sha256 verify (no curl|sh from an unpinned branch).
TRIVY_VERSION ?= 0.55.0
trivy: bootstrap _ensure-trivy
	trivy fs --scanners vuln \
	  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress .
# Opt in to IaC/Dockerfile + secret scanning per repo by using this instead
# (secrets already covered by gitleaks; misconfig is noisier). `.trivyignore`
# in the repo root suppresses accepted findings by ID.
#	trivy fs --scanners vuln,misconfig,secret \
#	  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress .

# Pinned, checksum-verified trivy install. Self-guards: no-op when trivy is
# present (devs with `brew install trivy`), installs only in CI.
_ensure-trivy:
	@command -v trivy >/dev/null 2>&1 && exit 0; \
	  set -eu; ver="$(TRIVY_VERSION)"; \
	  os="$$(uname -s)"; arch="$$(uname -m)"; \
	  case "$$os" in Darwin) os=macOS;; Linux) os=Linux;; esac; \
	  case "$$arch" in x86_64|amd64) arch=64bit;; arm64|aarch64) arch=ARM64;; esac; \
	  tar="trivy_$${ver}_$${os}-$${arch}.tar.gz"; \
	  base="https://github.com/aquasecurity/trivy/releases/download/v$${ver}"; \
	  tmp="$$(mktemp -d)"; \
	  curl -sSfL "$$base/$$tar" -o "$$tmp/$$tar"; \
	  curl -sSfL "$$base/trivy_$${ver}_checksums.txt" -o "$$tmp/sums.txt"; \
	  if command -v sha256sum >/dev/null 2>&1; then sha="sha256sum"; else sha="shasum -a 256"; fi; \
	  ( cd "$$tmp" && grep " $$tar$$" sums.txt | $$sha -c - ); \
	  tar -xzf "$$tmp/$$tar" -C "$$tmp" trivy; \
	  install -m0755 "$$tmp/trivy" /usr/local/bin/trivy; \
	  rm -rf "$$tmp"

# Local secret scan for the pre-commit hook: scans STAGED changes only (fast).
# CI scans history/PR-range separately (see security.yml). Same tool, different mode.
GITLEAKS_VERSION ?= 8.18.4
secrets: _ensure-gitleaks
	gitleaks protect --staged --redact --no-banner --exit-code 1

_ensure-gitleaks:
	@command -v gitleaks >/dev/null 2>&1 && exit 0; \
	  set -eu; ver="$(GITLEAKS_VERSION)"; \
	  os="$$(uname -s | tr '[:upper:]' '[:lower:]')"; arch="$$(uname -m)"; \
	  case "$$arch" in x86_64|amd64) arch=x64;; arm64|aarch64) arch=arm64;; esac; \
	  tar="gitleaks_$${ver}_$${os}_$${arch}.tar.gz"; \
	  base="https://github.com/gitleaks/gitleaks/releases/download/v$${ver}"; \
	  tmp="$$(mktemp -d)"; \
	  curl -sSfL "$$base/$$tar" -o "$$tmp/$$tar"; \
	  curl -sSfL "$$base/gitleaks_$${ver}_checksums.txt" -o "$$tmp/sums.txt"; \
	  if command -v sha256sum >/dev/null 2>&1; then sha="sha256sum"; else sha="shasum -a 256"; fi; \
	  ( cd "$$tmp" && grep " $$tar$$" sums.txt | $$sha -c - ); \
	  tar -xzf "$$tmp/$$tar" -C "$$tmp" gitleaks; \
	  install -m0755 "$$tmp/gitleaks" /usr/local/bin/gitleaks; \
	  rm -rf "$$tmp"

# ---------------------------------------------------------------------------
# SCA — osv-scanner (lockfile vulnerabilities). Complements `trivy` (OS pkgs).
#
# THRESHOLD: fails on vulnerabilities at/above SCA_SEVERITY that HAVE A FIX.
# Fixable-only is deliberate: an unfixable upstream CVE would otherwise block
# every merge in the repo with no action available to unblock it. Ratchet plan
# is CRITICAL now -> HIGH once the repos are clean (see CICD README).
#
# osv-scanner has NO native severity threshold and NO --severity flag of any
# kind; the filtering below is ours, applied to its JSON. Do not "simplify" it
# into a bare `osv-scanner ...` call — you would lose the threshold entirely.
#
# !! EXIT CODES ARE LOAD-BEARING. Read before touching:
#      0   scanned, no vulns
#      1   vulns found            -> filter by threshold, may still pass
#    128   NO PACKAGES FOUND      -> no lockfile in repo; explicit pass + reason
#    else  infrastructure failure -> RED, never a pass
#    Wrapping this in `|| true` turns every real finding green. That exact
#    pattern is the defining defect class this pipeline exists to prevent.
OSV_VERSION ?= 2.4.0
SCA_SEVERITY ?= CRITICAL
SCA_FIXABLE_ONLY ?= true
sca: bootstrap _ensure-osv
	@set -eu; \
	case "$(SCA_SEVERITY)" in \
	  CRITICAL) min=9.0;; HIGH) min=7.0;; MEDIUM) min=4.0;; LOW) min=0.1;; \
	  *) echo "FAIL(sca): SCA_SEVERITY must be CRITICAL|HIGH|MEDIUM|LOW, got '$(SCA_SEVERITY)'"; exit 1;; \
	esac; \
	rc=0; osv-scanner scan source -r . --format json --output-file osv.json || rc=$$?; \
	if [ "$$rc" -eq 128 ]; then \
	  echo "SKIP(sca): osv-scanner found no supported lockfile here — nothing to scan."; \
	  echo "  Explicit pass. If this repo DOES have a lockfile, osv-scanner did not"; \
	  echo "  recognise it: fix that rather than accepting this message."; \
	  exit 0; \
	fi; \
	if [ "$$rc" -ne 0 ] && [ "$$rc" -ne 1 ]; then \
	  echo "FAIL(sca): osv-scanner exited $$rc — infrastructure failure, not a clean scan."; \
	  exit 1; \
	fi; \
	test -s osv.json || { echo "FAIL(sca): osv-scanner produced no report (exit $$rc)"; exit 1; }; \
	fixable='true'; [ "$(SCA_FIXABLE_ONLY)" = "true" ] || fixable='false'; \
	hits=$$(jq --argjson min "$$min" --argjson fixonly "$$fixable" -r ' \
	  [ .results[]?.packages[]? \
	    | . as $$p \
	    | $$p.groups[]? \
	    | select((((.max_severity // "") | if . == "" then "0" else . end) | tonumber) >= $$min) \
	    | . as $$g \
	    | $$p.vulnerabilities[]? \
	    | select(.id as $$i | $$g.ids | index($$i)) \
	    | select(($$fixonly | not) or ([.affected[]?.ranges[]?.events[]? | select(has("fixed"))] | length > 0)) \
	    | "\($$p.package.ecosystem)/\($$p.package.name)@\($$p.package.version) \(.id) sev=\($$g.max_severity)" \
	  ] | unique | .[]' osv.json); \
	if [ -n "$$hits" ]; then \
	  echo "FAIL(sca): fixable vulnerabilities at/above $(SCA_SEVERITY) (CVSS >= $$min):"; \
	  echo "$$hits" | sed 's/^/  /'; \
	  echo "Full report: osv.json (uploaded as a workflow artifact)."; \
	  exit 1; \
	fi; \
	echo "OK(sca): no fixable vulnerabilities at/above $(SCA_SEVERITY) (osv-scanner exit $$rc)"

_ensure-osv:
	@command -v osv-scanner >/dev/null 2>&1 && exit 0; \
	  set -eu; ver="$(OSV_VERSION)"; \
	  os="$$(uname -s | tr '[:upper:]' '[:lower:]')"; arch="$$(uname -m)"; \
	  case "$$arch" in x86_64) arch=amd64;; aarch64) arch=arm64;; esac; \
	  bin="osv-scanner_$${os}_$${arch}"; \
	  base="https://github.com/google/osv-scanner/releases/download/v$${ver}"; \
	  tmp="$$(mktemp -d)"; \
	  curl -sSfL "$$base/$$bin" -o "$$tmp/osv-scanner"; \
	  curl -sSfL "$$base/osv-scanner_SHA256SUMS" -o "$$tmp/sums.txt"; \
	  if command -v sha256sum >/dev/null 2>&1; then sha="sha256sum"; else sha="shasum -a 256"; fi; \
	  ( cd "$$tmp" && grep " $$bin$$" sums.txt | sed "s/$$bin/osv-scanner/" | $$sha -c - ); \
	  install -m0755 "$$tmp/osv-scanner" /usr/local/bin/osv-scanner; \
	  rm -rf "$$tmp"

# ---------------------------------------------------------------------------
# SBOM — syft. ARTIFACT-ONLY, NON-GATING BY DESIGN.
# syft is a generator: it has no findings and no severity concept, so there is
# nothing it could threshold on. It fails only if generation itself fails.
# Do not add a fake threshold here. Gating on dependency vulns is `sca`/`trivy`.
# Emits BOTH CycloneDX and SPDX from one scan; both upload as artifacts and are
# what the deployment side consumes.
SYFT_VERSION ?= 1.50.0
sbom: bootstrap _ensure-syft
	@set -eu; \
	syft dir:. -o cyclonedx-json=sbom.cdx.json -o spdx-json=sbom.spdx.json; \
	test -s sbom.cdx.json || { echo "FAIL(sbom): empty CycloneDX output"; exit 1; }; \
	test -s sbom.spdx.json || { echo "FAIL(sbom): empty SPDX output"; exit 1; }; \
	echo "OK(sbom): sbom.cdx.json + sbom.spdx.json generated (artifact-only, non-gating)"

_ensure-syft:
	@command -v syft >/dev/null 2>&1 && exit 0; \
	  set -eu; \
	  curl -sSfL https://get.anchore.io/syft | sh -s -- -b /usr/local/bin "v$(SYFT_VERSION)"

# ---------------------------------------------------------------------------
# SAST — compose this from the language-specific targets below. Each tool ships
# its OWN rules under an OSI licence (bandit Apache-2.0, njsscan LGPLv3+), so
# there is no rule-licensing question for these two. See the CICD README for
# why the language-agnostic opengrep lane is NOT wired here yet.
#
# Compose for your stack, e.g.:
#     sast: njsscan bandit      # Node + Python
#     sast: bandit              # Python only
# Opting out with `@true` is allowed but must carry a written reason — an
# unscanned repo is a coverage gap, not a configuration choice.
SAST_SEVERITY ?= ERROR
sast: bootstrap
	@echo "define: sast — compose from njsscan / bandit (see comment above)"; false

# njsscan (Node/JS/TS). Exits 1 on ERROR findings natively; WARNING-level
# findings only fail when SAST_SEVERITY=WARNING (adds -w). Two-level tool:
# there is no numeric threshold to tune.
NJSSCAN_VERSION ?= 0.4.3
njsscan: bootstrap
	@set -eu; \
	command -v njsscan >/dev/null 2>&1 || pip install --quiet "njsscan==$(NJSSCAN_VERSION)"; \
	warn=""; [ "$(SAST_SEVERITY)" = "WARNING" ] && warn="-w" || true; \
	njsscan $$warn --json -o njsscan.json . ; \
	echo "OK(njsscan): no findings at/above $(SAST_SEVERITY)"

# bandit (Python). Native threshold: fails when issues exist at/above BOTH the
# severity and confidence levels. bandit's scale is low|medium|high, so
# SAST_SEVERITY=ERROR maps to `high` here; override per repo if you want tighter.
BANDIT_VERSION ?= 1.9.4
BANDIT_SEVERITY ?= high
BANDIT_CONFIDENCE ?= medium
bandit: bootstrap
	@set -eu; \
	command -v bandit >/dev/null 2>&1 || pip install --quiet "bandit[sarif]==$(BANDIT_VERSION)"; \
	bandit -r . -f json -o bandit.json \
	  --severity-level $(BANDIT_SEVERITY) --confidence-level $(BANDIT_CONFIDENCE); \
	echo "OK(bandit): no findings at/above severity=$(BANDIT_SEVERITY) confidence=$(BANDIT_CONFIDENCE)"

# ---------------------------------------------------------------------------
# DAST — OWASP ZAP baseline (PASSIVE only). Active scanning is too slow and too
# destructive for a PR gate; run it on a schedule instead (not wired here).
#
# BOOT PATH: dast-up/dast-down MUST reuse the same boot commands as `smoke` —
# one boot mechanism, not two. `smoke` boots-and-exits; `dast-up` boots detached
# and leaves the service running for ZAP, `dast-down` tears it back down.
#
# OPT-OUT IS EXPLICIT. A repo with no bootable HTTP service sets DAST_OPT_OUT=true
# with a reason. Leaving DAST_TARGET empty without that is a hard failure, so a
# missing DAST config can never read as a silent pass.
DAST_TARGET ?=
DAST_OPT_OUT ?= false
ZAP_IMAGE ?= ghcr.io/zaproxy/zaproxy:stable
# ZAP_FAIL_ON: FAIL = fail only on ZAP FAIL-level alerts (passes -I).
#              WARN = also fail on WARN-level alerts (omits -I). Noisy on first contact.
ZAP_FAIL_ON ?= FAIL

dast-target:
	@printf '%s' "$(DAST_TARGET)"

# Boot the service detached. Reuse your `smoke` boot commands here, e.g.:
#   docker run -d --name dast -p 8080:8080 $(IMAGE) && \
#   for i in $$(seq 1 30); do curl -fsS $(DAST_TARGET)/health && exit 0; sleep 2; done; exit 1
dast-up:
	@if [ "$(DAST_OPT_OUT)" = "true" ]; then exit 0; fi; \
	  echo "define: dast-up (boot detached, reusing your smoke boot) — or set DAST_OPT_OUT=true with a reason"; false

dast-down:
	@true
