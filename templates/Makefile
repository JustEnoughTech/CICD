# CI contract. The reusable CI workflow calls these targets by name.
# Every repo MUST define all of them. No lane for your repo? Make it a no-op
# (`@true`) — an explicit, visible opt-out beats a silently skipped check.
#
# Put toolchain/dependency install in `bootstrap`; lanes depend on it, so CI
# never needs stack-specific setup steps.
.PHONY: bootstrap lint format-check format test e2e build smoke trivy secrets hooks \
        _ensure-trivy _ensure-gitleaks

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
