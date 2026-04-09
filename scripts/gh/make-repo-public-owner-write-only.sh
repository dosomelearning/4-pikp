#!/usr/bin/env bash
set -euo pipefail

# Make current repo public, keep write access to owner only,
# and reduce outside interaction to "read/clone only" as much as GitHub allows.

# 0) Ensure GH CLI is authenticated in this environment before doing anything.
if ! AUTH_STATUS="$(gh auth status 2>&1)"; then
  echo "ERROR: GitHub CLI is not authenticated in this environment."
  echo "Run 'gh auth login -h github.com' and retry."
  echo
  echo "gh auth status output:"
  echo "${AUTH_STATUS}"
  exit 1
fi

# Resolve repo (owner/name) from current git remote context.
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

echo "Target repository preflight"
echo "repo: ${REPO}"
echo
echo "Authentication status"
echo "${AUTH_STATUS}"
echo

VISIBILITY="$(gh repo view "${REPO}" --json visibility -q .visibility)"
IS_PRIVATE="$(gh repo view "${REPO}" --json isPrivate -q .isPrivate)"
HAS_ISSUES="$(gh repo view "${REPO}" --json hasIssuesEnabled -q .hasIssuesEnabled)"
HAS_PROJECTS="$(gh repo view "${REPO}" --json hasProjectsEnabled -q .hasProjectsEnabled)"
HAS_WIKI="$(gh repo view "${REPO}" --json hasWikiEnabled -q .hasWikiEnabled)"
HAS_DISCUSSIONS="$(gh repo view "${REPO}" --json hasDiscussionsEnabled -q .hasDiscussionsEnabled)"

echo "owner: ${OWNER}"
echo "name: ${NAME}"
echo "visibility: ${VISIBILITY} (isPrivate=${IS_PRIVATE})"
echo "features: issues=${HAS_ISSUES}, projects=${HAS_PROJECTS}, wiki=${HAS_WIKI}, discussions=${HAS_DISCUSSIONS}"

echo
echo "Planned changes"
echo "- Set visibility to public."
echo "- Disable issues, projects, wiki, and discussions."
echo "- Attempt to disable forking (may not be supported by account/repo policy)."
echo "- Remove direct collaborators except repository owner."
echo "- If org-owned, remove team access bindings."
echo "- Attempt to set interaction limits to collaborators_only for 6 months."
echo
echo "Important limitations"
echo "- Public repository content remains cloneable/readable by anyone."
echo "- GitHub cannot fully prevent opening PRs/forks/comments in every scenario via one switch."
echo "- This script applies the strictest practical restrictions available through gh CLI/API."
echo

read -r -p "Type 'yes' to proceed with making ${REPO} public under these constraints: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted by user. No changes applied."
  exit 0
fi

# 1) Make repo public.
gh repo edit "${REPO}" --visibility public --accept-visibility-change-consequences

# 2) Disable interactive features (read-only feel for outsiders).
gh repo edit "${REPO}" \
  --enable-issues=false \
  --enable-projects=false \
  --enable-wiki=false \
  --enable-discussions=false

# 3) Try to disable forking (if supported for this repo/account type).
if gh api -X PATCH "repos/${REPO}" -f allow_forking=false >/dev/null 2>&1; then
  echo "Forking disabled."
else
  echo "Could not disable forking (GitHub/account policy may not allow it)."
fi

# 4) Remove direct collaborators except owner.
mapfile -t COLLABS < <(
  gh api "repos/${REPO}/collaborators?affiliation=direct&per_page=100" --paginate -q '.[].login'
)

for user in "${COLLABS[@]:-}"; do
  if [[ "$user" != "$OWNER" ]]; then
    echo "Removing collaborator: $user"
    gh api -X DELETE "repos/${REPO}/collaborators/${user}" >/dev/null
  fi
done

# 5) If org-owned, remove team access bindings.
if gh api "repos/${REPO}/teams?per_page=100" >/dev/null 2>&1; then
  mapfile -t TEAMS < <(gh api "repos/${REPO}/teams?per_page=100" --paginate -q '.[].slug')
  for slug in "${TEAMS[@]:-}"; do
    echo "Removing team access: ${slug}"
    gh api -X DELETE "orgs/${OWNER}/teams/${slug}/repos/${OWNER}/${NAME}" >/dev/null || true
  done
fi

# 6) Optional: restrict issue/PR/discussion interactions to collaborators.
# Note: interaction limits are time-bounded by GitHub.
if gh api -X PUT "repos/${REPO}/interaction-limits" -f limit=collaborators_only -f expiry=six_months >/dev/null 2>&1; then
  echo "Interaction limit set to collaborators_only (6 months)."
else
  echo "Could not set interaction limit (endpoint/policy may differ)."
fi

echo
echo "Done. Final visibility/features:"
gh repo view "${REPO}" --json visibility,hasIssuesEnabled,hasProjectsEnabled,hasWikiEnabled,isPrivate \
  -q '{visibility, isPrivate, hasIssuesEnabled, hasProjectsEnabled, hasWikiEnabled}'
