# v0.1 — Smart Blinds (plan)

The next milestone after v0. Extends the BE so the React FE can list,
read state from, and control real SmartWings Z-Wave blinds via the
local Home Assistant instance.

This file is the high-level plan. The atomic commit sequence lives in
`smart-blinds-implementation.md` (created after the open decisions
below are resolved).

## Goal

By the end of v0.1, an authenticated user can:

1. Visit the FE dashboard and see a list of blinds for their home.
2. See live state for each blind (open/closed/opening/closing/unavailable
   + current_position 0–100).
3. Issue `open`, `close`, `stop`, or `set_position` commands and observe
   the blind physically respond.

Everything else from the broader v1 design (schedules, saved
configurations, activity log, multi-home admin UI, MCP tool calls,
device pairing UI, push notifications, cameras / locks / lights /
thermostats / garage doors) is **out of scope** for this milestone.

## Why now

v0 proved the auth chain. The FE can authenticate and reach the BE.
The BE has no domain endpoints behind that auth yet. v0.1 adds the
smallest end-to-end vertical slice that produces value: real device
control of the user's primary device type. Every device type after
this can follow the same shape.

## What's already documented

This plan **does not** restate decisions or research that already live
in the repo. It only references and extends them. If you want
background, read these in order:

- `planning/v0_docs/implementation-plan.md` — what v0 shipped; success
  criteria; architecture decisions locked in.
- `planning/v0_docs/step-by-step-commit-strat-be.md` — the commit
  pattern this milestone copies (atomic, inside-out, validation
  gate per commit).
- `planning/technical-design.md` — the full v1 architecture. Sections
  this milestone implements partially:
  - §Data Models: `homes`, `blinds`, `activity_log` (subset)
  - §Backend Module Structure: `apps/core/lib/core/home/ha_client.ex`,
    `apps/core/lib/core/blinds/`, `apps/core/lib/core/cache/`
  - §FE ↔ BE Communication: synchronous HTTP + polling (no Channels in
    v0.1)
- `planning/technical-notes.md` — resolved decisions (60+ Q&A items)
  and the verified HA REST API reference (§HA REST API Reference,
  lines ~168–235). The §HA WebSocket API reference (lines ~135–166)
  is **not** used by v0.1; it's for device pairing in a later
  milestone.
- `planning/function_docs/blinds/README.md` — wire-level contract for
  blinds: cover entity state shape, `supported_features` bitmask
  meaning, FE-facing poll response shape, behavior when device is
  unavailable.
- `planning/research/ha_websocket/README.md` — Fresh library recommended
  for the eventual pairing flow. Informational only for v0.1 (REST
  client is sufficient).
- `planning/research/oban_scheduling/README.md` — schedule executor
  pattern. **Not** in v0.1 scope but referenced so v0.2 inherits the
  Oban dep cleanly.

## Scope (in v0.1)

1. **Postgres + Ecto** — first time persistent storage lands in the
   BE. Adds `:ecto_sql`, `:postgrex`, sets up `Core.Repo`, ships dev /
   test / prod database configuration.
2. **Two schemas, one context** —
   - `homes` table (the v0 single-home model migrated into DB). One
     row seeded at boot from existing env vars. Stores
     `ha_base_url` and `ha_token` (plaintext for v0.1; encryption is
     deferred — see Open Decision #4).
   - `blinds` table per `technical-design.md` §blinds. Seeded manually
     for v0.1; UI / mix task for managing them lands in a later
     milestone.
   - `Core.Blinds` context with `list/1`, `get/2`, `set_position/3`,
     `open/2`, `close/2`, `stop/2`.
3. **HA REST client** — `Core.HA.RestClient` (or
   `Core.Home.HaClient` per existing planned module path; final
   placement to confirm). Req-based. Behaviour + default impl + Mox
   in test, identical pattern to `Core.Auth.JwksCache.HttpFetcher`.
4. **State cache** — `Core.Blinds.StateCache` GenServer + ETS table.
   Polls HA every 5–10s for the configured home's `cover.*` entities.
   FE polls the BE for cached state; BE never proxies a live HA call
   on the read path.
5. **Web routes** —
   - `GET /api/homes/:home_id/blinds` — list (name, room, ha_entity_id)
   - `GET /api/homes/:home_id/blinds/states` — current state per blind
     from cache
   - `POST /api/homes/:home_id/blinds/:id/position` — set position
     (body: `{position: 0..100}`)
   - `POST /api/homes/:home_id/blinds/:id/open|close|stop` — convenience
     verbs
   All routes go through the existing `:authenticated` pipeline
   (`Web.Plugs.RequireSession`).
6. **Home-scope plug** — a small plug that extracts `:home_id` from
   the URL and asserts it matches the BE's configured `HOME_ID`. For
   v0.1 this is a one-row check; v0.2 swaps it for membership lookup
   (see Open Decision #1).
7. **Test posture** — same as v0: 100% coverage on owned code via
   ExCoveralls; Mox at the HA boundary; one happy-path + one or two
   error-shape tests per module; conn-based ExUnit for controllers;
   smoke test against real HA at a documented pause point.

## Out of scope

Each of these belongs to a follow-on milestone and is intentionally
deferred:

- Schedules (`blind_schedules`, Oban worker, GenServer scheduler).
- Saved configurations (named multi-blind presets).
- Activity log (will be added cross-cutting after multiple device
  types exist).
- HA WebSocket integration / device pairing UI.
- Multi-home admin UI; FE-driven home management. v0.1 stays
  single-home like v0.
- HA token encryption (Cloak).
- Rooms with outline geometry. v0.1 ignores rooms entirely; blinds
  render as a flat list. Room model lands later when the FE has an
  outline view.
- Other device types (locks, lights, thermostats, garage doors,
  cameras).
- Tailscale Funnel / public reachability.
- MCP tool calls.

## High-level architecture

```
React FE (artemis-home.fly.dev or localhost:6587)
  │
  │  poll loop ~5s
  │   GET /api/homes/:home_id/blinds/states  (Bearer session_jwt)
  │  user action
  │   POST /api/homes/:home_id/blinds/:id/position  (Bearer session_jwt)
  ▼
artemis_home_be (Phoenix endpoint)
  ├── RequireSession plug                 (existing, B9)
  ├── HomeScope plug                      (new — asserts URL home_id matches config)
  │
  ├── BlindsController.index              ── Core.Blinds.list/1            ── Ecto: SELECT * FROM blinds
  ├── BlindsController.states             ── Core.Blinds.poll_states/1     ── ETS lookup via StateCache
  └── BlindsController.set_position       ── Core.Blinds.set_position/3
                                              │
                                              ├── HA.RestClient.set_cover_position/4
                                              │   ── POST <home.ha_base_url>/api/services/cover/set_cover_position
                                              │      Authorization: Bearer <home.ha_token>
                                              │      {entity_id, position}
                                              │
                                              └── StateCache.invalidate(home_id, entity_id)
                                                  (optional — next poll picks up the new state)

Background:
StateCache GenServer (one per BE instance)
  ├── every 5–10s: HA.RestClient.list_states/1  ── GET <home.ha_base_url>/api/states
  └── upserts cover.* entries into :ets table keyed by {home_id, ha_entity_id}
```

## Reference examples

Captured under `planning/home-assistant-api/smart-blinds/` (HA-wide
notes one level up in `planning/home-assistant-api/`). Index:

- `01-list-cover-states.md` — captured. Bulk `GET /states` filtered to
  `cover.*`. All three covers currently `unavailable`; usable for the
  unavailable-handling code path only.
- `02-get-state-unavailable.md` — captured. Single-entity
  `GET /states/<entity>` plus 404 behavior.
- `03-cover-services-schema.md` — captured. Full `cover` services
  schema from `GET /services`, with v0.1-relevant subset.
- `known-blockers.md` — captured. Documents the Z-Wave radio offline
  state preventing live `state: open|closed|opening|closing` captures.
- `04-get-state-available.md` — **pending Z-Wave recovery.**
- `05-set-position-response.md` — **pending Z-Wave recovery.**
- `06-state-during-transition.md` — **pending Z-Wave recovery.**

The implementation plan is unblocked on what's already captured. The
pending captures only block writing test fixtures for the
`open`/`closed`/`opening`/`closing` state shapes and the B-α / B-β
smoke pauses — see Open Decision #10 for placement.

## Open decisions (need user input before implementation plan)

These all have a default I can pick if no opinion, but each has a
real trade-off worth surfacing.

1. **Multi-home now or later?**
   - **Default:** Stay single-home. One `homes` row seeded from env
     vars (`HOME_ID`, `HA_BASE_URL`, `HA_TOKEN`). The `:home_id` URL
     param is asserted against the env value. v0.2 introduces
     `home_memberships` + per-user home selection.
   - **Alternative:** Land multi-home in v0.1. Adds `users`,
     `home_memberships`, `roles` schemas; reworks session JWT issuance
     to carry membership info; adds a `homes` list endpoint. Bigger
     scope (~+5 commits).

2. **Rooms in v0.1 or skip entirely?**
   - **Default:** Skip rooms. Blinds render as a flat list. `room_id`
     column omitted from the schema for now (added in a later
     migration when rooms land). Avoids designing the outline format
     prematurely.
   - **Alternative:** Add the `rooms` schema and `room_id` foreign key
     but defer the outline JSONB (leave nullable). Lets the FE
     prototype room navigation without the outline view.

3. **Initial blinds seeding mechanism?**
   - **Default:** A mix task `mix seed.blinds --home <id>
     --blind ha_entity_id:name` written alongside the rest of v0.1,
     mirroring `mix seed.homes`. Manual operation only. No admin
     endpoint in v0.1.
   - **Alternative:** Add a `POST /api/admin/blinds` endpoint
     immediately. Adds one more commit; lets the FE manage blinds
     without operator shell access.

4. **HA token at rest — plaintext or Cloak now?**
   - **Default:** Plaintext column in `homes.ha_token`. Cloak migration
     deferred. Documented as a known v0.1 issue alongside the existing
     `artemis_home_fe/planning/issues.md` items.
   - **Alternative:** Add `cloak_ecto` in v0.1. Adds ~2 commits for
     vault setup + encrypted-type migration. Earns the encryption
     story earlier but slows the milestone.

5. **State cache backend — ETS or `:persistent_term`?**
   - **Default:** ETS table owned by `Core.Blinds.StateCache`
     GenServer. Standard pattern. Easy to inspect during dev with
     `:ets.tab2list/1`.
   - **Alternative:** `:persistent_term` map. Faster reads, but
     replacement is slower; copies on every update. Probably worse for
     a polled-every-5s workload.

6. **Poll cadence and missed-poll behavior?**
   - **Default:** 5-second poll. On HA error: log + retain previous
     state, mark `last_polled_at` as stale. Cache entries older than 30
     seconds report `available: false` to the FE regardless of cached
     state.
   - **Alternative:** Slower (10s) to halve HA load. Adaptive (1s
     immediately after a write, then back to 5s) so user-perceived
     latency improves. Adaptive is the right v1+ answer; v0.1 default
     is simplest.

7. **Route prefix — keep `/api/homes/:home_id/...` or use `/api/me/blinds`?**
   - **Default:** `/api/homes/:home_id/blinds/...` per
     `technical-design.md`. Forward-compatible with multi-home.
     Explicit `home_id` in URL.
   - **Alternative:** `/api/me/blinds/...` while single-home, refactor
     to home-scoped paths in v0.2. Simpler URLs now but a breaking
     route change later.

8. **HA service-call response handling?**
   - HA's `POST /api/services/cover/...` typically returns an empty
     array `[]` on success and a status-shaped object on bad input.
     The exact behavior with two connected blinds needs verification
     — included in the references-to-capture list above.
   - **Default:** Treat any 200/201 as success regardless of body;
     surface 4xx as `{:error, :ha_rejected, body}`.

9. **Where does HA URL + token come from at boot?**
   - **Default:** New env vars `HA_BASE_URL` and `HA_TOKEN`, written
     into the seeded `homes` row at boot if the row doesn't already
     exist. Matches the rest of the v0 runtime config posture.
     Documented in `.env.example`, `.envrc.example`, and
     `docker-compose.yml`.

10. **Smoke-test placement?**
    - **Default:** Two smoke pauses — Pause B-α (after the HA client
      lands, before the context) verifies a raw `HA.RestClient.list_states`
      call works against the live HA. Pause B-β (after the controller
      lands) verifies the full FE-shaped JSON response. Matches v0's
      multi-pause pattern.

## What "done" looks like for v0.1

Concrete acceptance criteria, mirroring the v0 success criteria:

- BE boots with Postgres up, runs migrations, seeds the home row
  from env vars.
- `mix seed.blinds` registers the two live blinds in the database.
- The BE polls HA every 5s and caches each blind's state in ETS.
- Curl against `GET /api/homes/<id>/blinds/states` returns both
  blinds' current state, available flag, and position.
- Curl against `POST /api/homes/<id>/blinds/<id>/position` with a
  position body physically moves the blind. State catches up on the
  next poll cycle.
- All quality gates pass: `mix all_tests`, 100% coverage on owned
  code, credo, dialyzer, formatter clean.
- The FE (handled by a separate agent) can list and control blinds
  end-to-end against this BE.

## Risks specific to this milestone

- **HA REST quirks not yet seen with available devices.** The existing
  research is based on all-covers-unavailable state. Fresh captures
  are needed before the implementation plan finalizes the StateCache
  diff logic. Mitigation: capture all six examples listed above
  before writing the implementation plan.
- **Database migration introduces the first stateful component.**
  All v0 state (RSA keys) was filesystem-local. Postgres adds a
  separate concern (backups, schema migrations on upgrade).
  Mitigation: keep schemas minimal for v0.1; only `homes` and `blinds`.
  Add coordinated migrations for v0.2+.
- **HA polling rate-limits the dev tenant.** Five-second polling
  produces ~17k requests/day. HA REST is unmetered locally, but if
  the BE ever reaches HA via Tailscale Funnel or similar, that
  changes. Not a v0.1 concern (everything is on-LAN).
- **Single-home assertion conflicts with the planned multi-home FE.**
  The FE's dashboard fan-out from v0 assumes each home has its own
  BE. v0.1 keeps that — one BE per home — but the home-scope plug
  must reject mismatched `:home_id` URL params with a clear error,
  not pass the wrong data through. Mitigation: explicit test for
  mismatched-home-id.

## Stop point

Before I draft `smart-blinds-implementation.md`, please weigh in on:

- The ten open decisions above. "Take the default on everything"
  is a valid answer.
- Anything else missing from this scope.
- Whether the goal as stated (list + state + control for two blinds)
  matches what you want this milestone to ship.
- HA URL and token so the fresh examples in
  `planning/smart-blinds/references/` can be captured.

Once those are answered, I'll write the commit-by-commit
implementation plan modeled on
`planning/v0_docs/step-by-step-commit-strat-be.md`, with the same
quality gate per commit and explicit smoke-test pauses.
