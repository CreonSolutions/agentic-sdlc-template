<!--
WORKED EXAMPLE — this is a real, ratified constitution from a source
project (a Flutter/Android market-data app), kept here verbatim so you can
see the level of specificity, article numbering, and amendment-log style
this pipeline expects. Do NOT copy this file's actual principles into your
own project — its scope (single shared API credential, no user accounts,
specific performance budgets) is particular to that app. Copy its
STRUCTURE: an explicit "Automation & the Build Loop" article (trigger
hygiene, human-review gates for governance/contract changes, agent conduct
rules), an explicit "Simplicity / YAGNI" article naming what's permanently
out of scope, and a Sync Impact Report + amendment log on every version
bump. Start your own from .specify/templates/constitution-template.md via
`/speckit-constitution` instead.
-->

<!--
Sync Impact Report
- Version change: 1.0.0 → 1.1.0
- Modified principles: Article I.2 (cache budget 20 MB → 4 MB, with rationale)
- Added sections: n/a
- Removed sections: n/a
- Templates requiring updates:
  - specs/001-market-summary/plan.md: ✅ updated (20 MB → 4 MB, ×2 references)
  - specs/001-market-summary/tasks.md: ✅ updated (T005 description)
  - specs/002-candlestick-technicals/plan.md: ✅ updated (shared cache reference)
  - .specify/templates/plan-template.md: ⚠ pending (not yet reviewed against this constitution)
  - .specify/templates/spec-template.md: ⚠ pending (not yet reviewed against this constitution)
  - .specify/templates/tasks-template.md: ⚠ pending (not yet reviewed against this constitution)
- Follow-up TODOs: TODO(RATIFICATION_DATE) — owner has not yet formally signed off;
  today's date stands as LAST_AMENDED_DATE.
- Rationale: T005's implementation (lib/core/cache_store.dart) surfaced that
  shared_preferences (T002's sanctioned storage choice) parses its entire
  backing file on every read, so a genuinely full 20 MB cache risks Article
  III.1's <2.0s cold-start budget. The owner chose to right-size the ceiling
  to 4 MB (matching shared_preferences' real cold-start-safe capacity) rather
  than reopen T002's storage-backend choice for a basic/demo edition.
-->

# CeylonCharts Mobile (Basic) — Engineering Constitution

Every spec, plan, task, pull request, and agent session in this project MUST comply
with the principles below. If a principle conflicts with a shortcut, the principle wins.
If two principles conflict, the earlier-numbered one wins.

> **Purpose note:** this repo is a deliberately minimal companion to
> `ceyloncharts-mobile` (the full app). It exists to (a) ship a genuinely useful
> two-screen app against real CSE market data, and (b) validate the clarifier →
> coder → reviewer agentic SDLC pipeline on a domain with far fewer moving parts
> — no user accounts, no server-side app backend, no portfolio, no alerts. Any
> lesson learned about the pipeline itself belongs in
> `docs/agentic-sdlc-setup.md`, not just in this constitution.

---

## Article I — Offline-First, Cache Everything

1.1. Every screen MUST remain usable with zero connectivity, showing the last
     cached response with a visible "stale data — as of \<timestamp\>" indicator.
1.2. Responses are cached locally keyed by endpoint + params, with a freshness
     timestamp. Cache eviction is LRU, bounded at **4 MB** (this app has no
     portfolio/watchlist data to store, so the budget is API-response cache
     only). Sized to `shared_preferences` (T002's sanctioned storage choice),
     which parses its entire backing file on every read — a genuinely full
     20 MB cache would risk Article III.1's cold-start budget. Raising this
     ceiling back up is possible but requires switching storage backends
     first (out of scope unless that migration is explicitly undertaken).
1.3. No screen may block its first render on a network call. Skeleton/placeholder
     states are mandatory on first-ever launch only; every subsequent launch
     renders cache instantly, then refreshes in the background.

## Article II — Single Shared API Credential (No User Accounts)

2.1. This app has NO login, NO user accounts, and NO per-user backend. It ships
     with one embedded `X-User-Id` / `X-Api-Key` pair (a real CeylonCharts
     developer key, see [authentication.md](../ceyloncharts-mcp-docs/docs/authentication.md))
     used identically by every install.
2.2. The credential value itself MUST NEVER be committed to git in plaintext —
     not in source, not in spec/issue text, not in commit messages. It is
     injected at build time from a gitignored local config
     (`android/local.properties`-style) and from a CI secret in test/build
     workflows. Specs and issues reference it as `<MCP_USER_ID>`/`<MCP_API_KEY>`
     placeholders only.
2.3. **Accepted risk, stated explicitly (mirrors Article VI.3 of the full app's
     "cert pinning is a V2 candidate" pattern):** a key embedded in a compiled
     APK is extractable by a motivated party, and CeylonCharts' rate limits are
     enforced per-account, not per-install (see
     [rate-limits.md](../ceyloncharts-mcp-docs/docs/rate-limits.md)) — every
     install of this app shares ONE hourly quota. This is a deliberate
     simplification for a basic/demo edition, not a production posture. If this
     app's user base grows past what the shared key's plan tier allows, the fix
     is a plan upgrade or a proxy layer — not a change to this article without
     an amendment.
2.4. Aggressive client-side caching (Article I) is the primary mitigation for
     2.3 — repeated screen visits and pull-to-refreshes within the API's own
     5-minute server-side cache window MUST hit the local cache, not the network.

## Article III — Performance Budgets

3.1. Cold start to first interactive frame: **< 2.0 s** on a mid-range Android.
3.2. Chart pan/zoom interaction latency: **< 100 ms**; sustained **≥ 60 fps**.
3.3. App size budget: ≤ 30 MB download (Android AAB) — no bundled portfolio/auth
     infra to justify a larger budget than the full app.

## Article IV — Test-First, Always

4.1. No implementation without a failing test written first (TDD).
4.2. Domain logic coverage ≥ **80%** (indicator math — RSI in particular, since
     it is computed on-device, not returned by the API; see spec 002).
4.3. Every API response is validated against `api/openapi.yaml` in tests.
4.4. The app degrades gracefully on contract violations or unexpected fields:
     log, fall back to cache, never crash (tolerant reader).

## Article V — Contract-First API

5.1. `api/openapi.yaml` is the single source of truth for every call this app
     makes to `mcp.ceyloncharts.com`. It is a deliberately small subset of the
     full API (see [rest-api.md](../ceyloncharts-mcp-docs/docs/rest-api.md)) —
     only the endpoints spec 001/002 actually use.
5.2. Any endpoint usage beyond what's already in `api/openapi.yaml` requires an
     OpenAPI change FIRST, reviewed as its own commit (Article VI.2 below).
5.3. This app is READ-ONLY against a third-party API it doesn't control. There
     is no "our backend" to keep in sync — contract drift means the real
     `mcp.ceyloncharts.com` API changed, which is out of this repo's control to
     fix, only to detect and degrade gracefully against (Article IV.4).

## Article VI — Automation & the Build Loop

6.1. CI gates: analyze → contract tests → unit (coverage gate) → build. No merge
     on red. No force-push to main.
6.2. Coding agents implement GitHub Issues in TDD loops; a *different* model
     reviews each PR against the spec before merge.
6.3. Agents MUST NOT guess when a spec is ambiguous — they open a clarifying
     comment/`question` issue and stop. Silent assumption is the
     highest-severity process violation.
6.4. Constitution and API-contract (`api/openapi.yaml`) amendments always route
     to a human — never auto-merged by an agent.
6.5. **Trigger hygiene:** any workflow reacting to `issues`/`pull_request`
     events MUST exclude events caused by the pipeline's own prior actions
     (e.g. a clarifier must not re-fire on the child issues it just created).
     This is a hard lesson from `ceyloncharts-mobile`'s first live run, which
     self-triggered into 20+ redundant runs before this guard existed — see
     `docs/agentic-sdlc-setup.md`.
6.6. Nightly E2E failures auto-file issues; these re-enter the agent queue.

## Article VII — Simplicity (YAGNI)

7.1. No feature, endpoint, or abstraction without a spec line that demands it.
7.2. Explicitly OUT of scope for this repo, permanently, not just "V1": user
     accounts/login, portfolio, alerts, push notifications, watchlists, any
     server-side component owned by this project. If a future idea needs any
     of those, it belongs in `ceyloncharts-mobile` (the full app), not here.
7.3. No hard-coded colors/spacing rule (Article VII of the full app's
     constitution) is NOT imported here — this app uses stock Material 3 dark
     theme with no bespoke design-token file, since there is no approved mockup
     for this edition. Keep UI plain and functional.

## Governance

This constitution supersedes any other stated practice or convention in this
repo. Every PR and every agent session (clarifier/coder/reviewer) MUST verify
compliance against it before proceeding.

Amendments require an explicit version bump (semantic versioning: MAJOR for
incompatible principle removal/redefinition, MINOR for a new principle or
materially expanded guidance, PATCH for wording/clarification only) and, per
Article VI.4, human review — never an agent auto-merge. Constitution and
`api/openapi.yaml` amendments are the one process area (besides Play Store
submission, once this app ships) reserved for the owner.

*Amendment log:*
- 1.0.0 — initial draft for owner ratification
- 1.1.0 — Article I.2 cache budget 20 MB → 4 MB (owner decision, see Sync Impact
  Report; T005/PR #12 surfaced that shared_preferences' whole-file-parse cost
  makes a literal 20 MB budget risk the cold-start budget)

**Version**: 1.1.0 | **Ratified**: TODO(RATIFICATION_DATE) — pending owner sign-off | **Last Amended**: 2026-07-27
