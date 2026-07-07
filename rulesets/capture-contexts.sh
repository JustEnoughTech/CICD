#!/usr/bin/env bash
# H3 — verify ruleset required-check contexts against REAL check-run names.
#
# Reusable-workflow checks surface as "<caller-job> / <job>" (e.g. "ci / lint").
# If the ruleset requires a string GitHub never emits, every PR hangs on a check
# that never reports. Run this on a PILOT repo after the workflows have run once,
# BEFORE locking required_status_checks org-wide.
#
# Usage:
#   ./capture-contexts.sh <ORG> <REPO> [REF]
#     REF = a commit SHA or branch. Omitted -> latest PR head SHA.
#   Requires: gh auth login (repo read), jq.
#
set -euo pipefail

ORG="${1:?usage: capture-contexts.sh <ORG> <REPO> [REF]}"
REPO="${2:?usage: capture-contexts.sh <ORG> <REPO> [REF]}"
REF="${3:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$REF" ]; then
  REF="$(gh api "/repos/$ORG/$REPO/pulls?state=all&sort=updated&direction=desc&per_page=1" \
        --jq '.[0].head.sha // empty')"
  [ -n "$REF" ] || { echo "no PRs found — pass a REF (sha/branch) explicitly"; exit 1; }
  echo "using latest PR head sha: $REF"
fi

# actual check-run names GitHub reported on that ref
ACTUAL="$(gh api "/repos/$ORG/$REPO/commits/$REF/check-runs" --paginate \
          --jq '.check_runs[].name' | sort -u)"
echo "=== actual check-run names on $REF ==="
[ -n "$ACTUAL" ] && sed 's/^/  /' <<<"$ACTUAL" || echo "  (none — did the workflows run on this ref?)"

# every context the branch rulesets require (lint, format, test, e2e, build, secrets, trivy, ...)
REQUIRED="$(jq -r '.rules[]?|select(.type=="required_status_checks")
                   |.parameters.required_status_checks[].context' \
            "$DIR"/01-branch-default.json "$DIR"/02-branch-release.json 2>/dev/null | sort -u)"
echo "=== contexts required by rulesets ==="
sed 's/^/  /' <<<"$REQUIRED"

echo "=== verdict ==="
miss=0
while IFS= read -r ctx; do
  [ -z "$ctx" ] && continue
  if grep -qxF "$ctx" <<<"$ACTUAL"; then
    echo "  OK      $ctx"
  else
    echo "  MISSING $ctx   <-- no check reported this exact name"
    miss=1
  fi
done <<<"$REQUIRED"

if [ "$miss" = 0 ]; then
  echo "All required contexts present. Safe to lock enforcement + widen to ~ALL."
else
  echo "FIX before locking: rename the ruleset context to match a real name above,"
  echo "     or fix the workflow job name so it emits the expected context."
  exit 1
fi
