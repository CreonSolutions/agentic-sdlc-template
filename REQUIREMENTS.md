# Requirements

Everything below is needed before you start [SETUP-GUIDE.md](SETUP-GUIDE.md).

## Accounts / access

- [ ] A GitHub account or organization to own the repo. A personal **User**
      account works fine — org-only features like org-level secrets are
      NOT required, everything here works at the single-repo level.
- [ ] A **Claude Pro or Max subscription** (for `CLAUDE_CODE_OAUTH_TOKEN` via
      `claude setup-token` — no separate Console/API billing needed), OR an
      **Anthropic Console API key** if you'd rather pay per-token.
- [ ] Repository access for the **Claude Code GitHub App** — installed at
      either the org level ("All repositories") or explicitly added to this
      repo ("Selected repositories"). Install from
      https://github.com/apps/claude if not already installed anywhere you
      use.

## Local tools

- [ ] `gh` (GitHub CLI), authenticated: `gh auth status`. Needs `repo`,
      `project`, and `workflow` scopes — `gh auth refresh -s project` if
      `project` is missing (this is an interactive device-code flow, budget
      a couple of minutes for it the first time).
- [ ] `git`.
- [ ] `jq` (used by `claude-coder-revise.yml`'s strike-counting logic, and
      handy locally too).
- [ ] Claude Code CLI itself, for the interactive Spec-Kit steps
      (`/speckit-constitution`, `/speckit-specify`, etc.) and for
      `claude setup-token`.
- [ ] Your project's own toolchain (whatever `ci.yml`/`nightly-e2e.yml` need
      to build/lint/test — e.g. a language runtime, package manager,
      mobile SDK). Not needed to stand up the pipeline itself, but needed
      before the coder agent can verify anything it writes.

## Knowledge / decisions to have made before you start

- [ ] **What is explicitly OUT of scope**, permanently — not just "V1."
      Constitutions in this pattern work best when they name what will
      never be built, not only what will.
- [ ] **Every external API/service this project will call**, with real,
      confirmed request/response shapes — not assumed ones. If you don't
      have this yet, budget time to get it (read real docs, hit real
      endpoints) before writing the contract file; an agent inventing a
      plausible shape is the single biggest source of rework this pattern
      has produced so far.
- [ ] **Who is the human reviewer of first resort** — governance changes
      (constitution amendments, contract-file changes) and the first batch
      of PRs per feature are meant to route to a specific person, not just
      "whoever's watching."

## Explicitly NOT required

- Org-level GitHub plan, or org-owned secrets (repo-level secrets work
  fine).
- A public repo — everything here works identically on a private repo.
- Any paid GitHub Projects tier — Projects (v2) boards are free.
