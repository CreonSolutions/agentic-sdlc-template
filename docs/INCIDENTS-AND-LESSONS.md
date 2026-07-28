# Incidents and Lessons

Real failures hit while bootstrapping this pattern twice, and the fixes —
already baked into every workflow file in this template. Read this before
you loosen any trigger condition, permission block, or safety cap; each one
here exists because something concrete broke without it.

## Incident: the self-triggering loop

On the very first real run of this pipeline, the clarifier workflow's
`issues: opened` trigger had no exclusion for issues **created by the
pipeline itself**. Child task issues are created with `ready-for-dev` (and
sometimes a `spec:NNN`) labels set atomically at creation — and GitHub fires
a discrete `issues.labeled` event for each label applied that way, *in
addition to* the one `issues.opened` event. Since the trigger only checked
`action == 'opened'` with no label exclusion, each child issue's own
`opened` event re-invoked the clarifier **on itself**, which (not
recognizing it was already a fully-scoped, TDD-sized task) could create
further child issues.

Compounding this: a human reply-comment on an issue still labeled
`needs-clarification` also re-triggers the clarifier via the
`issue_comment: created` path — and closing an issue with `gh issue close
--comment "..."` posts a comment too, so an operator's own housekeeping
comment can trigger a real agent run if the gating condition isn't precise
about which comments count.

**Net effect:** ~20 clarifier runs and several coder runs fired within about
90 seconds, producing ~28-33 duplicate/orphaned child issues before it was
caught and everything in flight was cancelled. No PRs or code commits
resulted (the coder runs failed before reaching that point), but real
Claude API spend was burned on the runaway runs, and — separately — a real
credential posted as a clarifying answer ended up copied in plaintext into
over a dozen duplicate issue bodies simply because so many redundant
breakdowns ran off the same (correct) answer.

**The fix**, now baked into `claude-clarifier.yml` in this template from the
start:

```yaml
if: >
  (github.event_name == 'issues' && github.event.action == 'opened' &&
   !contains(github.event.issue.labels.*.name, 'ready-for-dev') &&
   !contains(github.event.issue.labels.*.name, 'awaiting-review')) ||
  (github.event_name == 'issue_comment' && ...)
```

## Incident: two first-run snags with `claude-code-action` itself

1. **Bot actor blocked by default.** `claude-code-action` refuses to run
   when the triggering actor is a bot (`Workflow initiated by non-human
   actor: claude (type: Bot)`) — a real anti-loop safeguard on Anthropic's
   side. The reviewer workflow reacts to a PR the coder bot itself opens
   and labels, so it needs an explicit, narrowly-scoped allow-list:
   ```yaml
   with:
     allowed_bots: "claude"   # NOT "*" -- only your own bot identity
   ```
2. **Reviewer can't self-approve.** The coder and reviewer both
   authenticate as the same GitHub App installation (the same bot
   account), so `gh pr review --approve` fails with `Can not approve your
   own pull request`. The reviewer prompt tells the agent to fall back to
   a plain comment with its verdict when this happens (rather than
   treating it as an error) — this still works given the constitution
   already requires a human to be the one who actually clicks merge; a
   formal GitHub "Approved" review state is only worth chasing (via a
   second bot identity/PAT) if branch-protection rules need to count it.
3. **`pull_request`-triggered workflow-file validation.** GitHub requires a
   PR-triggered workflow's file content to match the default branch's
   version before running it (a separate safeguard from the two above) —
   if you fix a workflow file *after* a PR's branch already exists, that
   PR's existing runs will silently self-skip with "workflow validation
   failed" until the PR branch is updated (merge/rebase main into it) or a
   fresh PR is opened. Re-running or re-labeling alone does not help; the
   PR branch itself needs the fix.

## Incident: the reviewer had the identical multi-label self-trigger bug

The clarifier's `issues: opened` guard was fixed to exclude events where
labels applied at creation would cause redundant re-firing — but the
**reviewer's own `pull_request: labeled` trigger had the identical bug**,
just never exercised until a PR happened to get 2+ labels at creation. A PR
opened with `awaiting-review` + `spec:NNN` together fired the reviewer 3
times on the *same, unchanged* diff within about a minute (GitHub fires a
separate `labeled` event per label even when applied atomically, and the
job's `if` only checked "is `awaiting-review` currently present" — true for
every one of those events), plus a 4th time when the auto-revise safety
cap's own `blocked` label landed. The cap correctly stopped after 3 review
verdicts and flagged for a human — the safety net worked — but it tripped
on redundant duplicate reviews, not genuine repeated revision failures,
which is misleading in the PR history.

**Fix** (same shape as the clarifier's): for a `labeled` action
specifically, only proceed if *that event's own label* was the trigger
label, not merely "is it present":
```yaml
if: >
  contains(github.event.pull_request.labels.*.name, 'awaiting-review') &&
  (github.event.action != 'labeled' || github.event.label.name == 'awaiting-review')
```

**Lesson for any future pipeline setup:** the "could a successful run of
this workflow cause this trigger to fire again" question needs to be asked
separately for **every** label-gated trigger in the pipeline, not just the
one where it was first discovered — the issue-side and PR-side triggers
are separate code paths with the same footgun, and fixing one does not fix
the other.

A second, related bug lived in the auto-revise cap itself: it originally
counted **all-time** request-changes reviews on a PR, not reviews since the
last push. A PR that crossed the cap once (even from the duplicate-review
bug above, since fixed) stayed permanently capped/blocked forever after,
even for a genuinely fresh single review of already-fixed code. Fixed by
counting only reviews submitted after the current HEAD commit's date:
```bash
HEAD_DATE=$(gh api repos/OWNER/REPO/pulls/N/commits --jq 'sort_by(.commit.committer.date) | last | .commit.committer.date')
# then filter reviews to `.submittedAt >= $HEAD_DATE` before counting
```
**Lesson:** any "N strikes and stop" safety cap on a mutable, revisable
artifact (a PR, not a one-shot issue) needs to measure "strikes against the
*current* state," not lifetime strikes — otherwise the cap can never reset
even after the actual problem is fixed.

## Incident: reviewer approved a PR with failing CI

The reviewer's prompt asked it to review the diff for correctness, but
never explicitly told it to check the PR's actual CI status — it sometimes
re-ran the linter/formatter itself as part of "ordinary correctness," and
sometimes didn't. This produced an `APPROVE` verdict on a commit whose own
CI run had already failed on an unformatted-file check — the review and
the CI failure were both real, just inconsistent with each other.

**Fix:** made checking real CI status step 0 — a hard gate before any other
review step — rather than leaving it to the model's discretion whether to
re-derive the same signal manually. Any failing or pending check is now an
automatic blocker regardless of diff quality.

**Lesson:** don't ask an LLM reviewer to *re-verify* a signal that a
deterministic CI system already computed for the exact same commit — query
the real result directly and treat it as authoritative.

**Follow-on:** even with a CI-gate instruction in the prompt, a file failed
the exact same format check on *two separate* revise attempts before it
actually went green — each attempt's own local verification reported
clean. The coder's sandbox toolchain version is not guaranteed to match the
CI runner's pinned version (a `channel: stable`-style setup action resolves
to whatever's current *that day*), so "I ran the formatter locally, it's
clean" is not reliable evidence — CI's result is the only one that counts.

**Second follow-on — the real root cause of a much longer stuck loop:** the
CI-gate fix (step 0, "check `gh pr checks`") looked right but didn't
actually work: the reviewer workflow's `permissions:` block had no
`checks`/`statuses` scope, so `gh pr checks`/the commit-status API/
`check-runs` all 403'd inside the reviewer's own run — *even after CI had
genuinely gone green*. The reviewer correctly treated "I can't verify CI"
as itself a blocker (a sound defensive default) and kept requesting changes
on that basis alone, for several rounds, regardless of how clean the actual
diff was. **Lesson:** a workflow step that reads GitHub state beyond
issues/PRs/contents (check runs, commit statuses, deployments, etc.) needs
its own explicit permission scope — the job silently degrades to "I can't
tell, so I'll assume the worst" rather than erroring loudly, which reads as
plausible reviewer caution rather than a permissions bug unless you dig
into why every round cites the identical unverifiable-CI complaint.

**Third follow-on — adding the permission scope didn't actually fix it.**
`checks: read`/`statuses: read` in the workflow file's own `permissions:`
block can only *restrict* what the underlying GitHub App installation
already has — it cannot *grant* a permission the App was never authorized
for at the installation level. If the Claude GitHub App installation you're
using has no Checks API access at all, `gh pr checks`, `.../check-runs`,
`.../check-suites`, `.../status`, and the GraphQL `checkSuites` field all
still 403 even with the scope declared in your workflow file.

The reviewer itself found the actual working signal:
`gh pr view <N> --json mergeable,mergeStateStatus` — `mergeStateStatus:
"CLEAN"` means every check passed; anything else (`UNSTABLE`, `BLOCKED`,
`DIRTY`, ...) means at least one check is failing or still pending. This
field comes from standard PR-read permission, not Checks, so it works with
no further permission changes.

**Lesson:** when a permission-scoped API is unavailable because of the
*App installation's* fixed grant (not the workflow file), stop trying to
fix it in the workflow YAML — look for a different field on an API surface
the integration already has access to that carries an equivalent signal.

## Incident: the CI-status gate was structurally unsatisfiable (15 stuck rounds)

`mergeStateStatus` turned out to be the wrong fix too, for a subtler reason
than a permissions gap: **the reviewer workflow that reads
`mergeStateStatus` is itself triggered by `pull_request:`, so its own run
is a pending check on the exact commit it's evaluating, for its entire
duration.** `mergeStateStatus` aggregates ALL checks on a commit —
including the one currently asking the question. It is structurally
impossible for it to read `CLEAN` from inside a `pull_request`-triggered
workflow, regardless of whether every *other* check (the real CI job) has
actually passed. This produced the exact observed pattern for 15 review
verdicts straight: coder pushes → real CI goes green → reviewer wakes up,
reads `UNSTABLE` (its own in-flight run) → blocks → auto-revise pushes a
cosmetic/no-op change → repeat.

**Fix:** stop reading any check/merge-state aggregate at all. Have the
actual CI workflow (`ci.yml`) label the PR directly with its own outcome
(`ci-green`/`ci-red`) as its last step (`if: always()`, using the default
`GITHUB_TOKEN` with `pull-requests: write` — no Checks permission needed,
since labeling a PR is plain PR-write access). The reviewer then reads that
label with ordinary `gh pr view --json labels`, fully sidestepping the
Checks API and the self-referential `mergeStateStatus` trap. A workflow's
own run can label a PR without that label-write ever appearing as a
"check" on the commit, so there's no recursion.

**Lesson, generalized:** any time an automation needs to know "did some
other process finish and what did it conclude," prefer a signal that
process writes *itself* (a label, a comment, a status file committed to a
known path) over a shared aggregate/rollup that the asking process's own
execution might contribute to. Aggregates that include "am I done yet" as
an input to "is everything done" are a trap for exactly this reason —
obvious in hindsight, easy to miss when the aggregate reads like a clean,
official API for the question you're actually asking.

## Incident: coder/revise both ran out of turns on toolchain-heavy tasks

A task requiring a full toolchain bootstrap (installing the SDK from
scratch, then running the real test suite for verification) used 54 of the
coder's original 60 max-turns budget and ended "successfully" without ever
pushing a branch or opening a PR — most of its budget went to environment
setup before it could run tests/lint for real verification. Simpler
config-only tasks in the same batch only used 41-50 of 60. The auto-revise
workflow hit the identical wall shortly after.

**Fix:** raised both the coder and revise workflows' `--max-turns` to 90 (the
defaults shipped in this template).

**Lesson:** any task requiring a real toolchain bootstrap + verification
cycle needs meaningfully more turn budget than a comment-only or
config-only task — tune for the heaviest realistic task in your repo, not
the average one, especially once real code (not just scaffolding) starts
landing.

## General lessons for any future pipeline setup

1. Any workflow reacting to `issues`/`pull_request` events must positively
   exclude events the pipeline's own prior actions would generate. Ask,
   for every trigger: *"could a successful run of this workflow itself
   cause this trigger to fire again?"*
2. Prefer **explicit, synchronous board-wiring** (`gh project item-add`
   returns the new item's id directly) over polling/retrying for GitHub's
   built-in "Auto-add to project" automation to catch up — a retry-loop
   pattern (`sleep 10`, several attempts) is itself a contributing cause of
   turn-budget exhaustion, since retries burn agent turns.
3. `--max-turns` should have headroom for the full task including any
   retries/board-wiring, not just the "happy path" turn count — the
   clarifier's real first task (read constitution + all specs + contract,
   then create several child issues with individual `gh` calls each)
   needed more turns than a small initial budget gave it.
4. Never let an agent (or an operator) write a real credential value into
   issue/PR text, even as a "temporary, obviously-going-to-be-replaced"
   answer to a clarifying question — issue comments are permanent in a
   repo's history the moment they're posted, and get echoed into whatever
   the agent creates next. Use placeholder tokens in all spec/issue text
   (`<API_KEY>`, etc.) and supply real values only via gitignored local
   config or CI secrets, never in git-adjacent text.

## Environment note: cloud-synced folders + native build toolchains don't mix

If your project has a native build step (Gradle/Kotlin, native compiled
dependencies, etc.) and your local checkout lives inside a cloud-sync
folder (OneDrive, Dropbox, Google Drive Desktop), expect intermittent,
hard-to-diagnose build failures — access-denied errors, "not a regular
file," cloud-operation timeouts — because the sync client's
placeholder/on-demand-download layer can't keep up with the build tool's
incremental cache churning through thousands of small files.

Also watch for a second, separate problem if you move the project to fix
the first one: some incremental compilers (observed with Kotlin) compute a
relative path between the project and a cached dependency source file for
build-cache keys, and that computation can fail outright across Windows
drive letters (`this and base files have different roots`) if your package
cache and project end up on different drives.

**Fix that works:** keep native-toolchain projects on the *same drive* as
your package/dependency cache, *outside* any cloud-synced tree (e.g.
`C:\dev\<repo>` rather than `C:\Users\<user>\OneDrive\...\<repo>`). Push/pull
to keep this local build copy in sync with a cloud-hosted "working" copy if
you edit in both places.

## Incident: directly-seeded task/bug issues silently never reach the Projects board

Several task/bug issues were created directly via `gh issue create --label
"ready-for-dev,..."` (the normal way to file a bug found through manual
testing, or to seed a task without going through `speckit-taskstoissues`)
and never appeared on the GitHub Projects board at all, even after their
PRs merged. No error, no comment anywhere — the issues just silently never
got a board card.

**Root cause:** `claude-clarifier.yml` has explicit "if this issue isn't on
the board yet, add it yourself" logic — but that workflow deliberately
never runs for issues created with `ready-for-dev` already set (the
trigger-hygiene guard from the very first incident in this doc). Nothing
else in the pipeline does an unconditional `item-add`: `claude-coder.yml`'s
own board-wiring step only lists existing items and edits the one that
matches, assuming the item is already present. For a directly-seeded
issue, that assumption is false, so the coder's `item-edit` silently has
nothing to match, and the issue stays off the board forever with no
failure signal anywhere.

**Fix:** `claude-coder.yml` in this template already has the same "not
found → add it yourself" fallback the clarifier has (see the workflow
file) — don't remove it if you're trimming the prompts down, and apply the
same pattern to any future workflow that edits a board item by looking it
up first.

**Lesson:** "assume a prior step already did X" is exactly the kind of
implicit dependency that fails silently the moment the prior step is
skipped for a legitimate reason (here, the clarifier being skipped on
purpose for directly-seeded issues) — every consumer of shared state
should be able to establish that state itself, not just react to it.

## Design gap: no "In Progress" status — a card only ever showed queued or finished work

Related to the incident above, but a separate, smaller gap: even once every
issue reliably reached the board, the coder only ever touched it **once, at
the very end** — opening the PR and moving straight to "In Review." There
was no status for "an agent is actively coding this right now." From
outside, an in-flight task was indistinguishable from one that hadn't
started yet (both sat in "Ready for Dev"), which is not the usual Kanban
practice of Backlog → In Progress → In Review → Done.

**Fix:** added a genuine "In Progress" option to the Status field (see
`scripts/create-project-board.sh` and `SETUP-GUIDE.md` step 3), and gave
the coder a new *first* instruction — before writing any test or code — to
claim the board card (adding it if missing, same fallback as the incident
above) and set it to "In Progress." The existing "move to In Review" step
at the end is unchanged.

If you're adding this option to an **existing** board (not a fresh one),
use `updateProjectV2Field`'s `singleSelectOptions` input with the existing
options' real `id` values included alongside the new one without an `id` —
this input type accepts an optional `id` per option specifically so you can
add one new option without disturbing the identity (and therefore every
existing item's current value) of the ones already there. Omitting an
existing option's `id`, or leaving an existing option out of the list
entirely, risks GitHub creating a new option (and orphaning items still
set to the old one) instead of preserving it — always pass the complete
set, with real ids for anything that already exists.

**Lesson:** a status model with only "not started" and "finished" buckets
hides exactly the information a human glancing at a board wants most —
what's actually in flight right now.

## Incident: PROJECT_TOKEN silently failed on every board call for its entire history

Even after both fixes above, issues kept failing to appear on the board —
not intermittently, **every single time**, across every coder run
checked. The coder's own board-wiring commands never surfaced an error
anywhere visible (PR descriptions, issue comments, run summaries all
looked normal), because `claude-code-action` hides an agent's full Bash
output by design (`Running Claude Code via SDK (full output hidden for
security)`), and the coder's prompt has no instruction to verify a
`gh project` call's exit code or stop on failure — a failed board update
and a successful one look identical from the outside.

**Diagnosis:** GitHub Actions logs for an in-progress agent run don't
stream partial tool output, and a completed agent run's own logs only
ever echo the *prompt text*, never command results — there is no way to
observe the actual failure through the normal pipeline. The fix was to
stop trying to diagnose it *through* the agent entirely: a disposable
`workflow_dispatch`-triggered debug workflow (no LLM involved, just a
plain `run:` step using the same `${{ secrets.PROJECT_TOKEN }}`)
reproduced the exact `gh project item-list ... --owner <name>` call the
coder makes, and it failed immediately with `unknown owner type` — a
concrete, googleable error, not a vague timeout or permission wall.

**Root cause:** `PROJECT_TOKEN` was a classic PAT scoped to `project`
only — this template's own (at-the-time) guidance. That is not
sufficient: the `gh` CLI needs `read:org` to resolve what kind of GitHub
account `--owner <name>` even refers to, before it can do anything else —
without it, every `gh project` subcommand taking `--owner` fails this way,
**even when the owner turns out to be a plain User account, not an org**
(confirmed separately via `curl .../orgs/<owner>` → 404, `type: "User"` on
`/user` — `read:org` is required for the CLI's own type-check, not
because the target is actually an org). A follow-up check inside the same
disposable workflow (`curl -sI -H "Authorization: token $TOK"
https://api.github.com/user | grep x-oauth-scopes`) confirmed the token's
real granted scopes directly from the response header — this is the only
way to verify what scopes a secret actually carries, since GitHub secrets
are write-only and cannot be read back once set.

**Fix:** added `read:org` to the PAT's scopes (editable in place on
GitHub's classic-PAT edit page — this does not change the token's value,
so no secret rotation was needed) and re-verified with the same disposable
diagnostic workflow before deleting it.

**Lesson, twice over:**
1. When an automated agent's tool calls are opaque by design (hidden for
   security, or just not logged), don't try to debug the failure through
   the agent — reproduce the exact same call in a minimal, non-agent
   context (a bare script, a `workflow_dispatch` job, a local terminal)
   where you can actually see the raw result.
2. Any external credential a pipeline depends on should have its actual,
   effective permissions verified empirically at setup time — "the docs
   say this scope is enough" is a claim to test, not a fact to trust,
   especially for a CLI (`gh project`) whose real scope requirements
   aren't fully obvious from the permission name alone.

## Follow-on incident: read:org fixed reads, but writes still silently failed

After the `read:org` fix above, board reads worked (`gh project
item-list` returned real data) — but newly-seeded issues still never
appeared on the board. A coder agent's own PR description eventually
stated it had tried and failed: `PROJECT_TOKEN` only carries
`project`/`read:org` (no `repo`), so `gh project item-add`/`item-edit`
can't resolve the issue. That claim was verified the same way as before —
a disposable diagnostic ran `item-list` (still worked) immediately
followed by `item-add --url <issue-url>` with the identical token.
`item-list` succeeded; `item-add` failed immediately with `resource not
found, please check the URL` — a distinct error, confirming a genuinely
separate gap, not a recurrence.

**Root cause:** listing/editing items already on a board is one
permission surface; resolving a *repo-hosted issue URL* into a new
project item is another — the latter needs the token to read that issue
via the repo API first, which requires `repo` scope on a **private**
repository specifically (`read:org` doesn't cover it).

**Fix:** added `repo` to the same PAT (again editable in place, no value
change).

**Lesson:** verifying one operation of a multi-operation tool (`gh
project`'s *read* subcommands) does not verify the others (`item-add`, a
*write*-adjacent, cross-resource operation). When empirically testing a
credential's effective permissions, test every distinct operation your
pipeline actually calls, not just the first one that happens to fail
loudly — read and write access to the same nominal resource can require
different scopes entirely.

## Incident: CI never actually ran the test suite, for a project's entire history

On the reference project, an early `ci.yml` ran exactly two checks —
format and static analysis — and labeled the PR `ci-green`/`ci-red` from
those two alone. There was no test-execution step at all. Every merged
PR's test-pass claim ("139/139 passing", "154 tests passed", ...) was
self-reported in the PR body by the same coder agent that wrote the
tests, and never independently verified by the one mechanism (`ci-green`)
the reviewer is required to treat as a hard gate — directly contradicting
a constitution requiring "analyze → contract tests → unit (coverage
gate) → build. No merge on red."

This was not caught by design, by CI failing, or by a human audit — it
was caught by the *reviewer agent itself*, incidentally, while reviewing
an unrelated PR, as a non-blocking observation: it noted `ci-green`
couldn't actually substantiate the PR's test claim, flagged it as a
separate concern for the owner, and correctly did not hold that PR's
merge over a pipeline gap it didn't introduce.

**Fix:** this template's own `ci.yml` already has a "Tests" step (see the
comment on it) — the lesson is to never delete or skip it when adapting
this file for a real stack, since "format + lint only" looks like a
complete CI job right up until a real regression ships behind a green
checkmark.

**Lesson:** a CI gate is only as trustworthy as the checks actually wired
into it. "The constitution requires X" and "the CI step is named
`analyze-and-format`" (or similar) are both statements about *intent*,
not evidence that X is actually happening — the same class of gap as the
`PROJECT_TOKEN` scope incidents above. Read the actual file, don't trust
the name or the prior belief about what it covers.
