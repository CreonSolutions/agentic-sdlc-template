# Setup Guide: Bootstrapping This Pipeline On A New Project

This is the checklist for standing up the clarifier → coder → reviewer →
revise pipeline on a **new** repo, written from two real bootstraps —
including one that went wrong (see
[docs/INCIDENTS-AND-LESSONS.md](docs/INCIDENTS-AND-LESSONS.md)) so the
mistake isn't repeated a third time.

Before starting, confirm you have everything in
[REQUIREMENTS.md](REQUIREMENTS.md).

## 1. Create the repo

```
gh repo create <OWNER>/<REPO> --private --description "..."
```

Copy (or clone) this template's contents into it: `.claude/`, `.specify/`,
`.github/workflows/`, `docs/`, `scripts/`.

## 2. Write your project's real Spec-Kit content

- **`.specify/memory/constitution.md`** — run `/speckit-constitution` in an
  interactive Claude Code session, or write it by hand from
  `.specify/templates/constitution-template.md`. Write one specific to
  THIS project's actual scope — do not copy another project's constitution
  wholesale. See [docs/example-constitution.md](docs/example-constitution.md)
  for a worked example, including its "Automation & the Build Loop" article
  (trigger hygiene, human-review gates, agent conduct rules) — keep an
  equivalent article in your own constitution; it's cheap to include and
  expensive to relearn.
- **Your contract file** (`api/openapi.yaml` or equivalent) — describe ONLY
  the real, confirmed endpoints/capabilities this project actually uses. If
  you're integrating with an existing API, read its real docs and copy
  exact shapes; do not let an agent (or yourself) guess/invent shapes "that
  seem reasonable" — this was the single biggest source of rework across
  both source bootstraps.
- **`specs/NNN-<slug>/spec.md`** per feature (`/speckit-specify`, then
  `/speckit-clarify`) — functional requirements, acceptance scenarios
  (Gherkin), edge cases, explicit "Out of Scope" section.
- **`specs/NNN-<slug>/plan.md`** (`/speckit-plan`) and **`tasks.md`**
  (`/speckit-tasks`) — dependency-ordered, per-user-story task breakdown.

## 3. Create the GitHub Project (v2) board

```
gh project create --owner <OWNER> --title "<REPO>" --format json
```

Note the returned project `id` and `number` — you'll need both for step 6.

Set the Status field's options via GraphQL (the built-in "Workflows"
automation panel in step 5 genuinely needs the web UI, but the field
options themselves do not):

```
gh api graphql -f query='
mutation {
  updateProjectV2Field(input: {
    fieldId: "<STATUS_FIELD_ID from `gh project field-list <NUMBER> --owner <OWNER>`>",
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
}'
```

Save every id from the response (`PROJECT_ID`, `STATUS_FIELD_ID`, each
option id) — they get hardcoded into the workflow prompts in step 6.
`scripts/create-project-board.sh` automates steps 3 and this GraphQL call.

## 4. Labels

Run `scripts/setup-labels.sh <OWNER>/<REPO>`, or manually:

```
gh label create "needs-clarification" --color d73a4a --description "Clarifier is blocked, needs owner input"
gh label create "ready-for-dev"       --color 0e8a16 --description "Clarifier finished, coder should implement"
gh label create "awaiting-review"     --color fbca04 --description "Coder finished, reviewer should review"
gh label create "blocked"             --color b60205 --description "Coder found a real blocker"
gh label create "ci-green"            --color 0e8a16 --description "Latest CI run on this PR passed"
gh label create "ci-red"              --color b60205 --description "Latest CI run on this PR failed"
gh label create "e2e-failure"         --color 5319e7 --description "Nightly E2E failed"
gh label create "spec:NNN" --color c5def5 --description "..."   # one per spec, repeat as needed
```

## 5. Manual, web-UI-only steps

These genuinely cannot be scripted as of this writing — GitHub Projects'
"Workflows" automation panel has no REST/GraphQL/CLI surface at all:

1. Open the project → **Workflows** (⋯ menu, or the automation icon).
2. **"Item added to project" → set Status to Backlog** — turn this on.
   (Cosmetic only, since the agent workflows set status explicitly anyway,
   but keeps manually-added items from sitting with no status.)
3. **"Item closed" → set Status to Done** — turn this on. Safe to rely on:
   it only fires on a genuine terminal close/merge event, so unlike the
   create/label-driven transitions, it cannot cascade into a loop.
4. **"Auto-add to project"** — optional. The workflow design deliberately
   does NOT depend on this (child issues and PRs add themselves
   explicitly), so only turn it on if you also want issues created
   manually by a human to land on the board without you adding them by
   hand. If you do, the filter field only understands GitHub search-qualifier
   syntax (`is:issue`, `label:x`, `state:open`) — NOT project field names
   like `status:`.
5. Install the **Claude Code GitHub App** on this repo (or the whole org):
   confirm its repository access includes this new repo (org/account App
   settings → Configure → repository access). If it was installed with
   "All repositories," nothing to do; if "Selected repositories," add this
   one explicitly.

## 6. Copy and adapt the six workflow files

The six files under `.github/workflows/` in this template are already
adapted for the pattern's known failure modes (see
docs/INCIDENTS-AND-LESSONS.md). You still need to:

- Replace every `<OWNER>`, `<PROJECT_NUMBER>`, `<PROJECT_ID>`,
  `<STATUS_FIELD_ID>`, and `<..._OPTION_ID>` placeholder with the real
  values from step 3.
- Fill in the `<YOUR_DEPENDENCY_MANIFEST>`, `<YOUR_E2E_TEST_DIR>`,
  `<YOUR_E2E_TEST_COMMAND>` placeholders in `ci.yml`/`nightly-e2e.yml` with
  your real stack's toolchain-setup action, install command, formatter,
  linter, and test runner.
- Update the prompt text's references to constitution article numbers if
  you renumbered anything relative to the example.
- Tune `--max-turns` to your task's real complexity — start from this
  template's defaults (30 for clarifier/reviewer, 90 for coder/revise) and
  raise them if you see `error_max_turns` on real tasks. Toolchain-heavy
  tasks (installing an SDK from scratch before verification is even
  possible) need meaningfully more headroom than config-only tasks.

## 7. Secrets

```
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <OWNER>/<REPO>   # from `claude setup-token`, run in YOUR OWN terminal
gh secret set PROJECT_TOKEN --repo <OWNER>/<REPO>             # a classic PAT scoped to ONLY the `project` permission
```

**Do not** reuse a broad personal `gh auth token` as `PROJECT_TOKEN` even
though it may have the right scope — it also carries `repo`/`workflow`/etc.,
handing the Actions runner (and the LLM agent running inside it) far more
privilege than the board-wiring calls need. Create/reuse a PAT scoped to
`project` only.

GitHub secrets are write-only — there is no way to copy an existing
secret's value from one repo to another via API. If you don't have the raw
values handy, regenerate: `claude setup-token` again, or a fresh
`project`-scoped PAT from Settings → Developer settings.

## 8. Seed the first issue and watch it closely

```
speckit-taskstoissues   # run this skill locally against your real tasks.md
```

or manually:

```
gh issue create --repo <OWNER>/<REPO> --title "..." --label "ready-for-dev,spec:NNN" --body "..."
```

Then, for the FIRST real run only, watch it like a hawk rather than firing
and forgetting:

```
gh run list --repo <OWNER>/<REPO> --limit 5
gh run view <id> --repo <OWNER>/<REPO> --json status,conclusion
```

If you see the run count climbing every few seconds instead of settling at
one run per event, **stop** — cancel everything queued/in-progress
immediately (`gh run cancel <id>` per run) before diagnosing. This exact
failure mode is documented in detail in
docs/INCIDENTS-AND-LESSONS.md — read it if it happens to you.

## Ongoing: calibration period

Recommend a human skim of the first several reviewer-approved PRs per
feature before trusting full auto-merge — this is a calibration period on
a new project, not a permanent gate. Periodically audit merged diffs for
cost (turn usage) and for scope drift (YAGNI). Constitution and
contract-file changes should always route to a human, indefinitely — that
is not part of the calibration period, it's permanent policy.
