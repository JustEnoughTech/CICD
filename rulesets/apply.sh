#!/usr/bin/env bash
# Apply org rulesets via GitHub API. DOES NOT RUN AUTOMATICALLY.
# Requires: gh auth login  (token scope: admin:org)
#
# Usage:
#   ORG=my-org ./apply.sh                    # create rulesets (skips Enterprise-only unless plan=enterprise)
#   ORG=my-org DRY_RUN=1 ./apply.sh          # print payloads only, no calls
#   ORG=my-org FORCE_ENTERPRISE=1 ./apply.sh # attempt 04/05 even off Enterprise
#
set -euo pipefail

: "${ORG:?Set ORG=<your-github-org>}"
DRY_RUN="${DRY_RUN:-0}"
FORCE_ENTERPRISE="${FORCE_ENTERPRISE:-0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- C1: plan detection ------------------------------------------------------
# Free org rulesets enforce on PUBLIC repos only; private repos need Team+.
# Enterprise-only rulesets (push/metadata) are auto-skipped off Enterprise.
PLAN="$(gh api "/orgs/$ORG" --jq '.plan.name' 2>/dev/null || echo unknown)"
echo "org '$ORG' plan: $PLAN"
case "$PLAN" in
  free)
    echo "WARN: Free plan — rulesets gate PUBLIC repos only. PRIVATE repos stay UNENFORCED."
    echo "      Upgrade to Team (\$4/user/mo) for private-repo enforcement." ;;
  team|enterprise) : ;;
  *) echo "WARN: plan unreadable (token scope 'admin:org'? org name?). Proceeding blind." ;;
esac

# Files that require Enterprise Cloud (push rulesets, org-scope metadata).
ENTERPRISE_ONLY=" 04-push-hardening.json 05-branch-metadata.json "

# Break-glass team: set BREAK_GLASS_TEAM=<team-slug> to resolve its id and
# inject it as the bypass actor (pull_request mode) into every ruleset.
# Unset -> falls back to the OrganizationAdmin bypass baked in each JSON.
TEAM_ID=""
if [ -n "${BREAK_GLASS_TEAM:-}" ]; then
  TEAM_ID="$(gh api "/orgs/$ORG/teams/$BREAK_GLASS_TEAM" --jq .id)"
  echo "break-glass team '$BREAK_GLASS_TEAM' -> id $TEAM_ID"
fi

# Only push these on Enterprise Cloud. Comment out on Free/Team.
FILES=(
  "01-branch-default.json"
  "02-branch-release.json"
  "03-tag-release.json"
  "04-push-hardening.json"   # ENTERPRISE ONLY — will 422 otherwise
  "05-branch-metadata.json"  # edit @YOURDOMAIN.com first
)

# --- C2: existing rulesets, for idempotent upsert (match by name) ------------
EXISTING="$(gh api "/orgs/$ORG/rulesets" --paginate 2>/dev/null || echo '[]')"

for f in "${FILES[@]}"; do
  path="$DIR/$f"
  [ -f "$path" ] || { echo "skip missing $f"; continue; }
  # auto-skip Enterprise-only files unless plan supports them (or forced)
  if [[ "$ENTERPRISE_ONLY" == *" $f "* ]] && [ "$PLAN" != "enterprise" ] && [ "$FORCE_ENTERPRISE" != "1" ]; then
    echo "skip $f (Enterprise-only; plan=$PLAN) — set FORCE_ENTERPRISE=1 to attempt"
    continue
  fi
  # strip _comment keys the API rejects
  payload="$(jq 'del(._comment)' "$path")"
  # override bypass with the break-glass team when provided
  if [ -n "$TEAM_ID" ]; then
    payload="$(jq --argjson tid "$TEAM_ID" \
      '.bypass_actors = [{"actor_id": $tid, "actor_type": "Team", "bypass_mode": "pull_request"}]' \
      <<<"$payload")"
  fi
  name="$(jq -r '.name' <<<"$payload")"

  # idempotent: update in place if a ruleset with this name exists, else create
  id="$(jq -r --arg n "$name" 'map(select(.name==$n))|.[0].id // empty' <<<"$EXISTING")"
  if [ -n "$id" ]; then
    method=PUT;  api="/orgs/$ORG/rulesets/$id"; verb="update (#$id)"
  else
    method=POST; api="/orgs/$ORG/rulesets";     verb="create"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "=== would $method [$verb] $name ==="
    jq . <<<"$payload"
    continue
  fi

  echo "$verb ruleset: $name"
  jq . <<<"$payload" | gh api \
    --method "$method" \
    -H "Accept: application/vnd.github+json" \
    "$api" \
    --input - \
    && echo "  ok: $name" \
    || echo "  FAILED: $name (tier gate? scope? check output)"
done

echo "done. verify: gh api /orgs/$ORG/rulesets | jq '.[].name'"
