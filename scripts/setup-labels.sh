#!/usr/bin/env bash
# Creates every label the pipeline depends on.
#
# Usage: scripts/setup-labels.sh <OWNER>/<REPO> [spec-id ...]
#   scripts/setup-labels.sh CreonSolutions/my-app 001 002 003

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <OWNER>/<REPO> [spec-id ...]" >&2
  exit 1
fi

REPO="$1"
shift

gh label create "needs-clarification" --repo "$REPO" --color d73a4a --description "Clarifier is blocked, needs owner input" --force
gh label create "ready-for-dev"       --repo "$REPO" --color 0e8a16 --description "Clarifier finished, coder should implement" --force
gh label create "awaiting-review"     --repo "$REPO" --color fbca04 --description "Coder finished, reviewer should review" --force
gh label create "blocked"             --repo "$REPO" --color b60205 --description "Coder found a real blocker" --force
gh label create "ci-green"            --repo "$REPO" --color 0e8a16 --description "Latest CI run on this PR passed" --force
gh label create "ci-red"              --repo "$REPO" --color b60205 --description "Latest CI run on this PR failed" --force
gh label create "e2e-failure"         --repo "$REPO" --color 5319e7 --description "Nightly E2E failed" --force

for spec_id in "$@"; do
  gh label create "spec:${spec_id}" --repo "$REPO" --color c5def5 --description "Tasks belonging to spec ${spec_id}" --force
done

echo "Labels created on $REPO."
