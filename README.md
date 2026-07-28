# Agentic SDLC Template

A reusable starting point for running **spec-driven development (SDD) through
a fully agentic GitHub pipeline** — clarifier → coder → reviewer →
auto-revise — with a GitHub Projects (v2) board as the single source of
truth for status, and a minimum of human intervention.

This was extracted from a real, working bootstrap (`ceyloncharts-mobile` /
`ceyloncharts-mobile-basic`) after two live pipeline stand-ups, several
self-inflicted incidents, and their fixes. Every workflow file here already
has those fixes baked in — read
[docs/INCIDENTS-AND-LESSONS.md](docs/INCIDENTS-AND-LESSONS.md) before you
change the trigger conditions, or you will very likely reintroduce a bug
that's already been paid for once.

## What this actually is

Two layers, working together:

1. **[Spec-Kit](https://github.com/github/spec-kit)** (`.specify/`,
   `.claude/skills/speckit-*`) — the *local*, interactive half. You run
   `/speckit-constitution`, `/speckit-specify`, `/speckit-clarify`,
   `/speckit-plan`, `/speckit-tasks`, and `/speckit-taskstoissues` yourself,
   in an interactive Claude Code session, to turn a rough idea into a
   ratified constitution, a spec, a plan, and a dependency-ordered
   `tasks.md` — and finally into real GitHub issues, each pre-labeled
   `ready-for-dev`.
2. **GitHub Actions** (`.github/workflows/`) — the *autonomous* half. Once a
   task issue exists with `ready-for-dev`, four workflows take it the rest
   of the way to a merged PR with no further human action required, except
   the actual merge click:

   ```
   ready-for-dev  ──►  claude-coder.yml       (implements, opens PR, labels awaiting-review)
                              │
                              ▼
   awaiting-review ──►  claude-reviewer.yml   (different model, approves or requests changes)
                              │
                    request changes ──►  claude-coder-revise.yml   (fixes, re-triggers reviewer)
                              │
                          approve ──►  [human merges]
   ```

   A fifth workflow, `nightly-e2e.yml`, runs your E2E suite on a schedule
   and auto-files an issue (re-entering the queue at the clarifier) on
   failure. A sixth, `ci.yml`, is ordinary CI plus one load-bearing extra
   step: it labels every PR `ci-green`/`ci-red` directly, which is the
   *only* reliable way the reviewer agent can know whether CI passed (see
   the incidents doc for why the obvious alternatives — `gh pr checks`,
   `mergeStateStatus` — both fail for structural reasons, not just
   permissions).

   A seventh, `claude-clarifier.yml`, exists for the case where someone
   types a raw idea straight into an issue instead of going through the
   local Spec-Kit steps first — its only job is deciding whether the idea
   is concrete enough to hand back to the local pipeline, or asking
   clarifying questions and stopping. It never invents task issues itself.

## Quick start

1. Read [REQUIREMENTS.md](REQUIREMENTS.md) — confirm you have the accounts,
   tools, and access this needs before you start.
2. Follow [SETUP-GUIDE.md](SETUP-GUIDE.md) step by step. Budget 30-60
   minutes for the manual parts (GitHub Project board creation, App
   installation, secrets) plus however long your first constitution +
   spec take to write well.
3. Write your project's real
   [.specify/memory/constitution.md](.specify/memory/constitution.md)
   (`/speckit-constitution`) — do not skip this or leave it generic. See
   [docs/example-constitution.md](docs/example-constitution.md) for a
   worked, ratified example (from `ceyloncharts-mobile-basic`) showing the
   level of specificity and the "Automation & the Build Loop" article this
   pipeline depends on.
4. Run `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`,
   `/speckit-tasks` for your first feature, then `speckit-taskstoissues` to
   seed real GitHub issues.
5. Open the first issue, watch it flow through the pipeline end to end
   **before** trusting it unattended — see SETUP-GUIDE.md step 8.

## Repo layout

```
.claude/skills/speckit-*/     Spec-Kit slash-command skills (specify/clarify/plan/tasks/taskstoissues/...)
.specify/                     Spec-Kit templates + memory (constitution) + workflow registry
.github/workflows/            The 6 agentic pipeline workflows (see above)
docs/
  INCIDENTS-AND-LESSONS.md    Hard-won lessons from two real bootstraps — read before touching triggers
  example-constitution.md     A real, ratified constitution as a worked example
scripts/
  setup-labels.sh             Creates every label the pipeline depends on
  create-project-board.sh     Creates the GitHub Project (v2) board + Status field options
SETUP-GUIDE.md                 Step-by-step bootstrap checklist
REQUIREMENTS.md                Accounts/tools/access checklist
```

## Design principles this template encodes

- **Minimum intervention, not zero intervention.** Governance documents
  (constitution amendments, API/contract changes) and the first several
  reviewer-approved PRs per feature are deliberately kept human-reviewed.
  Full unattended auto-merge is a calibration you earn after watching the
  loop work correctly a few times, not a default.
- **Contract-first.** If your project talks to an external API, write down
  its real, confirmed shape before any agent touches it. An agent
  inventing a plausible-looking endpoint shape was the single biggest
  source of rework across both source bootstraps.
- **Trigger hygiene.** Every workflow that reacts to `issues`/`pull_request`
  events explicitly excludes events its own prior actions would generate.
  This is not optional decoration — the very first live run of this
  pattern, without this guard, produced ~20 redundant runs and ~28
  duplicate issues in about 90 seconds.
- **Measure real state, don't re-derive it.** The CI-status gate is a label
  a deterministic job sets, not something the reviewer agent tries to
  infer from a shared aggregate. Any "N strikes and stop" safety cap
  measures strikes against the *current* state of a mutable artifact (a
  PR), not lifetime strikes.
