#!/usr/bin/env bash
# Creates the GitHub Project (v2) board and sets its Status field options.
# Prints every id you need to paste into the workflow file placeholders
# (PROJECT_ID, STATUS_FIELD_ID, and each *_OPTION_ID).
#
# Usage: scripts/create-project-board.sh <OWNER> <TITLE>
#   scripts/create-project-board.sh CreonSolutions my-app

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <OWNER> <TITLE>" >&2
  exit 1
fi

OWNER="$1"
TITLE="$2"

echo "Creating project..."
CREATE_JSON=$(gh project create --owner "$OWNER" --title "$TITLE" --format json)
PROJECT_NUMBER=$(echo "$CREATE_JSON" | jq -r '.number')
PROJECT_ID=$(echo "$CREATE_JSON" | jq -r '.id')

echo "PROJECT_NUMBER=$PROJECT_NUMBER"
echo "PROJECT_ID=$PROJECT_ID"

echo "Reading Status field id..."
STATUS_FIELD_ID=$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
  | jq -r '.fields[] | select(.name == "Status") | .id')

echo "STATUS_FIELD_ID=$STATUS_FIELD_ID"

echo "Setting Status field options..."
RESULT_JSON=$(gh api graphql -f query='
mutation($fieldId: ID!) {
  updateProjectV2Field(input: {
    fieldId: $fieldId,
    name: "Status",
    singleSelectOptions: [
      {name: "Backlog", color: GRAY, description: ""},
      {name: "Needs Clarification", color: RED, description: ""},
      {name: "Ready for Dev", color: YELLOW, description: ""},
      {name: "In Progress", color: PURPLE, description: "Coder agent is actively implementing this"},
      {name: "In Review", color: BLUE, description: ""},
      {name: "Done", color: GREEN, description: ""}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id options { id name } }
    }
  }
}' -f fieldId="$STATUS_FIELD_ID")

echo "$RESULT_JSON" | jq -r '.data.updateProjectV2Field.projectV2Field.options[] | "\(.name)_OPTION_ID=\(.id)"'

echo ""
echo "Copy PROJECT_ID, STATUS_FIELD_ID, and the *_OPTION_ID values above into"
echo "the workflow prompts in .github/workflows/claude-clarifier.yml and"
echo "claude-coder.yml, replacing the <...> placeholders."
echo ""
echo "Reminder: the 'Workflows' automation panel (item-added / item-closed"
echo "rules, auto-add) still requires the web UI -- see SETUP-GUIDE.md step 5."
