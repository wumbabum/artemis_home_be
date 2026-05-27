# v0.1 Smart Blinds — step-by-step commit strategy

Execution sequencing for the v0.1 smart-blinds milestone. The
high-level decisions live in `plan.md`; the data model in
`../technical-design.md` §Data Models; the HA wire contract in
`../home-assistant-api/`.

Numbering: `SB<n>`. Pause points are interspersed and explicit.

## Principles

- **Atomic**: each commit is a self-contained, buildable unit.
  Reverting one commit doesn't break earlier ones.
- **Inside-out**: schemas before contexts; contexts before HA boundary;
  HA boundary before state cache; cache before controllers; controllers
  before mix tasks and docs.
- **Quality gate per commit**: every commit must pass `mix all_tests`
  from the umbrella root before the next commit begins. A failing gate
  must be fixed in the same commit (amend) before moving on.
- **Layer-boundary mocking**: when a commit introduces a module that
  depends on another module, the test mocks that dependency via Mox.
  The mock interface (a behaviour) is defined alongside the dependency.
- **Variety of test types**: ExUnit for examples, StreamData for
  property-based exercises of any function with variable-shape input,
  Mox for boundary mocking, conn-based ExUnit for controllers.
- **One conceptual change per commit**: deps go in their own commit;
  schemas separate from contexts; each module is its own commit.
- **Per-commit smoke check**: at the end of each commit's "What"
  list, the agent must consider whether the change has runtime
  behavior that should be verified beyond `mix all_tests`. If yes,
  describe the manual smoke step in the commit body and either run it
  or note it as deferred to the next pause point.
- **Commit message format**: `<scope>: <short description>` with a
  `Co-Authored-By: Oz <oz-agent@warp.dev>` trailer. Scopes used here:
  `infra`, `core`, `web`, `docs`.

## Quality gate

Same `mix all_tests` alias from v0. Enforces compile clean
(`--warnings-as-errors`), credo strict, formatter check, ExCoveralls
100% per-app, dialyzer clean. Per-app `coveralls.json` files gain
skip entries for new HTTP-boundary modules (HA REST client default
impl) and Ecto-generated boilerplate (`Core.Repo`).

## New dependencies (added across the sequence)

| Dep                | Where        | When | Why                                       |
|--------------------|--------------|------|-------------------------------------------|
| `ecto_sql ~> 3.13` | apps/core    | SB1  | Database access layer                     |
| `postgrex ~> 0.20` | apps/core    | SB1  | Postgres driver                           |
| `phoenix_ecto ~> 4.5` | apps/web  | SB1  | (optional in v0.1) Plug integration       |

No new umbrella deps for HA (the existing `:req ~> 0.5` in apps/core is
reused for the HA REST client).

## Pre-work checklist

- Postgres 16 reachable locally on `localhost:5432` (or wherever
  `DATABASE_URL` points). For dev: `brew services start postgresql@16`
  or run a `postgres:16-alpine` Docker container.
- HA reachable at `HOME_ASSISTANT_URL` (env var loaded via direnv;
  Z-Wave radio online before SB-α).
- The `.envrc` file populated with `HOME_ASSISTANT_URL`,
  `HOME_ASSISTANT_API_KEY`, plus the v0 auth0 vars, plus the new
  database `DATABASE_URL` and `SEED_ADMIN_AUTH0_SUB`. Update
  `.envrc.example` in SB12 once the env-var surface is final.

## Commit sequence

### SB1 — `infra: add ecto_sql + postgrex + Core.Repo scaffold`

What:

- Add `{:ecto_sql, "~> 3.13"}` and `{:postgrex, "~> 0.20"}` to
  `apps/core/mix.exs` runtime deps.
- Create `apps/core/lib/core/repo.ex` defining `Core.Repo` (adapter
  `Ecto.Adapters.Postgres`).
- Add `Core.Repo` to the supervision tree in
  `apps/core/lib/core/application.ex`, ahead of the existing
  `JwksCache` GenServer.
- Add `apps/core/coveralls.json` skip entry for `lib/core/repo.ex`
  (Ecto-generated boilerplate).
- `mix deps.get`, `mix deps.unlock --unused`.

Validation: `mix all_tests` passes. The Repo starts but has nothing
to do yet — no migrations exist.

Smoke check: none — no behaviour change at the HTTP surface yet.

### SB2 — `infra: add database config + migration scaffolding`

What:

- `config/config.exs`: `config :core, ecto_repos: [Core.Repo]`.
- `config/dev.exs` (new): `Core.Repo` username, password, hostname,
  database `artemis_home_be_dev`.
- `config/test.exs`: same shape, database `artemis_home_be_test`,
  pool `Ecto.Adapters.SQL.Sandbox`.
- `config/runtime.exs`: read `DATABASE_URL` for `:prod`, parse and
  apply to `Core.Repo`. For `:dev`, allow `DATABASE_URL` override
  with a sensible default (`postgres://postgres:postgres@localhost/artemis_home_be_dev`).
- Add `priv/repo/migrations/.gitkeep` so the directory exists.
- Root `mix.exs` `aliases`: add `ecto.setup`, `ecto.reset`, `ecto.create.test`,
  `ecto.migrate.test` modeled on a standard Phoenix umbrella.
- Update `mix all_tests` alias to prepend
  `"ecto.create.test --quiet"` and `"ecto.migrate.test --quiet"` so
  the test database always exists and is current.

Validation: `mix ecto.setup` succeeds against a local Postgres. `mix
all_tests` passes (no schemas defined yet; coverage unchanged).

Smoke check: confirm `psql artemis_home_be_dev -c '\dt'` returns
"no relations found" (or `schema_migrations` only). Document this in
the commit body if it differs.

### SB3 — `core: add Role schema + Roles context + migration`

What:

- Migration `priv/repo/migrations/<ts>_create_roles.exs`: `roles`
  table with `name` UNIQUE NOT NULL, `description` nullable,
  timestamps. Insert seed rows (`admin`, `resident`, `guest`) in the
  same migration via `execute/2` so the seeds exist after every
  `mix ecto.setup`.
- `apps/core/lib/core/accounts/role.ex`: Ecto schema for `Role` with
  `@type t() :: %__MODULE__{...}` and a `@spec changeset/2`.
- `apps/core/lib/core/accounts/roles.ex`: context with `list_roles/0`,
  `get_role!/1`, `get_role_by_name/1`.
- Test files: `apps/core/test/core/accounts/roles_test.exs` using
  Ecto.Adapters.SQL.Sandbox.
- Update `apps/core/test/test_helper.exs` to add `Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)`.

Validation: `mix all_tests` passes with 100% coverage on the new
files.

Smoke check: `mix run -e 'Core.Accounts.Roles.list_roles() |> IO.inspect()'`
returns the three seeded roles.

### SB4 — `core: add User schema + Accounts context + migration`

What:

- Migration `priv/repo/migrations/<ts>_create_users.exs`: `users`
  table with `auth0_sub` UNIQUE NOT NULL, `email` NOT NULL, `name`
  NOT NULL, `picture` nullable, `role_id` FK to roles NOT NULL,
  timestamps.
- `apps/core/lib/core/accounts/user.ex`: Ecto schema + changeset.
- Extend `apps/core/lib/core/accounts/accounts.ex` (rename from
  `roles.ex` to be the umbrella Accounts context, with Roles as a
  submodule) — or keep as `Roles` and add a new `Users` module.
  Recommend: one `Core.Accounts` context module that delegates to
  `Roles`/`Users` schemas internally.
- Public API additions:
  - `upsert_from_auth0(%{auth0_sub, email, name, picture})` —
    creates or updates a user. Role is assigned by:
    1. If `users` table is empty AND env `SEED_ADMIN_AUTH0_SUB`
       matches the incoming `auth0_sub` → role `admin`.
    2. Else if user exists → keep existing role.
    3. Else → default role `guest`.
  - `get_user_by_auth0_sub/1`.
- Tests: idempotency of upsert; admin seeding; role preservation.

Validation: `mix all_tests` passes. 100% coverage.

Smoke check: in iex, call
`Core.Accounts.upsert_from_auth0(%{auth0_sub: "google-oauth2|117394610565503842179", email: "wumbabum@gmail.com", name: "Joseph Toney", picture: nil})`
and verify the row appears in `users` with role `admin`
(assuming `SEED_ADMIN_AUTH0_SUB` env var is set).

### SB5 — `core: upsert user on Auth0 token exchange; carry role in session JWT`

What:

- Modify `Core.Auth.exchange_auth0_token/2`:
  - After verifying the Auth0 token, call
    `Core.Accounts.upsert_from_auth0/1` with the relevant claims
    (`sub`, `email`, `name`, `picture`).
  - Build the session JWT claims as `%{"sub" => sub, "home_id" =>
    home_id, "role" => role, "iat" => now}` where `role` is the user's
    role name (`"admin"` | `"resident"` | `"guest"`).
  - Reject with `{:error, :no_email}` if the verified claims do not
    carry an email (real Auth0 tokens always do, but document the
    error path).
- Update `Web.Plugs.RequireSession.build_user/1` to also assign `role`
  on `:current_user`.
- Tests:
  - `Core.AuthTest`: existing happy-path test updated to assert
    upsert called and role included in claims.
  - `RequireSessionTest`: assert `current_user.role` is exposed.
- No new endpoints; v0's existing `POST /api/sessions` continues to
  return `{user_sub, home_id, session_jwt}` plus the JWT now embeds
  role.

Validation: `mix all_tests` passes. 100% coverage. Existing v0 tests
continue to pass (regression check).

Smoke check: from iex, call
`Core.Auth.exchange_auth0_token(System.get_env("AUTH0_ACCESS_TOKEN"), "alpha")`,
decode the resulting JWT at jwt.io, verify it carries a `role` claim
matching the user's row in the database.

### SB6 — `core: add Blind schema + Core.Blinds CRUD + migration`

What:

- Migration `priv/repo/migrations/<ts>_create_blinds.exs`: `blinds`
  table per `technical-design.md` (no `home_id`, no `room_id` —
  v0.1 minimum shape). `ha_entity_id` UNIQUE, `sort_order` default 0.
- `apps/core/lib/core/blinds/blind.ex`: Ecto schema + changeset.
- `apps/core/lib/core/blinds/blinds.ex`: Context with `list_blinds/0`,
  `get_blind!/1`, `get_blind_by_ha_entity_id/1`, `create_blind/1`,
  `update_blind/2`, `delete_blind/1`. Public API only — no control
  functions yet (those land in SB9).
- Tests covering all branches.

Validation: `mix all_tests` passes. 100% coverage.

Smoke check: in iex, create two blinds matching the real HA entity
IDs and call `Core.Blinds.list_blinds() |> IO.inspect()`.

### SB7 — `core: add HA REST client behaviour + HTTP fetcher`

What:

- `apps/core/lib/core/ha/rest_client.ex`: behaviour with:
  - `@callback list_states() :: {:ok, [map()]} | {:error, term()}`
  - `@callback get_state(entity_id :: String.t()) :: {:ok, map()} | {:error, term()}`
  - `@callback call_service(domain :: String.t(), service :: String.t(), body :: map()) :: {:ok, [map()] | map()} | {:error, term()}`
- `apps/core/lib/core/ha/rest_client/http_fetcher.ex`: default impl
  using `Req`. Reads `HA_BASE_URL` and `HA_TOKEN` from
  `Application.fetch_env!(:core, :ha_base_url)` /
  `Application.fetch_env!(:core, :ha_token)`. Returns
  `{:ok, body}` on 2xx, `{:error, :ha_unreachable}` on transport
  failure, `{:error, {:ha_status, status, body}}` on non-2xx (parses
  `404`-text-body specially).
- Register mock: add
  `Mox.defmock(Core.HA.RestClientMock, for: Core.HA.RestClient)` to
  `apps/core/test/support/mocks.ex` (and the mirror file in
  `apps/web/test/support/mocks.ex` from v0 B9).
- `config/test.exs`: `config :core, :ha_rest_client, Core.HA.RestClientMock`.
- Default impl resolved via
  `Application.get_env(:core, :ha_rest_client, Core.HA.RestClient.HttpFetcher)`.
- Tests covering happy path, 404 entity, 5xx HA, transport error.
  Mox-stub `Req` at the boundary (introduce a thin
  `Core.HA.RestClient.HttpClient` behaviour if Req doesn't compose
  cleanly with Mox; pattern matches the JwksCache.HttpFetcher
  approach in v0 B3).
- Add HA-related env reads to `config/runtime.exs`:
  - `:dev` — defaults to `HOME_ASSISTANT_URL` / `HOME_ASSISTANT_API_KEY`
    (matches the existing direnv naming) with no fallback.
  - `:prod` — `System.fetch_env!/1` on both.
- Coverage skip: add `lib/core/ha/rest_client/http_fetcher.ex` to
  `apps/core/coveralls.json` (HTTP-boundary, exercised in smoke
  tests).

Validation: `mix all_tests` passes. 100% on owned code (with
http_fetcher excluded).

Smoke check: deferred to pause SB-α below.

### Pause SB-α — raw HA REST smoke test

Before writing the state cache, halt and confirm the HA client
actually works against the real HA instance.

1. Confirm Z-Wave radio is online (the captured-references-pending
   blocker from `planning/home-assistant-api/smart-blinds/known-blockers.md`
   must be resolved). If still offline, the unavailable shape can
   still be exercised — confirm the client returns the
   `unavailable`-shaped maps.
2. From the BE umbrella root, with env vars loaded:
   ```bash
   HOME_ID=alpha mix run -e '
     {:ok, states} = Core.HA.RestClient.HttpFetcher.list_states()
     states
     |> Enum.filter(fn s -> String.starts_with?(s["entity_id"], "cover.") end)
     |> IO.inspect(limit: :infinity)
   '
   ```
3. Confirm output is the three cover entities (or however many exist
   when Z-Wave is online).
4. Try `Core.HA.RestClient.HttpFetcher.get_state("cover.living_room_tv_right_outbound_bottom")`
   and confirm one entity returns.
5. If Z-Wave is online, attempt a service call to the right blind:
   ```elixir
   Core.HA.RestClient.HttpFetcher.call_service(
     "cover",
     "set_cover_position",
     %{
       "entity_id" => "cover.living_room_tv_right_outbound_bottom",
       "position" => 30
     }
   )
   ```
   The blind should physically move. Capture the response body into
   `planning/home-assistant-api/smart-blinds/05-set-position-response.md`
   per the still-pending capture list.

Do not advance to SB8 until both reads and (if Z-Wave is up) the
write succeed.

### SB8 — `core: add Core.Blinds.StateCache GenServer + ETS poll loop`

What:

- `apps/core/lib/core/blinds/state_cache.ex`: GenServer that owns a
  named ETS table (`:cover_state`, set, public, named_table) keyed
  by `ha_entity_id`. State map per entity: `%{ha_entity_id, state,
  position, available, last_polled_at}`.
- Public API:
  - `start_link/1` (added to `Core.Application` supervision tree).
  - `get_state(ha_entity_id) :: {:ok, map()} | {:error, :not_cached}`
  - `get_all() :: %{String.t() => map()}`
  - `refresh_now/0 :: :ok` (forces an immediate poll without waiting
    for the timer).
- Poll loop: on each timer tick, call
  `Core.HA.RestClient.list_states/0` (via the configured behaviour),
  filter to `cover.*`, upsert each into ETS. Default cadence: 5s.
  Stale entries (where the entity disappears from HA's response)
  retain their last value but mark `available: false` if
  `last_polled_at` is more than 30s ago.
- Tests via Mox of `Core.HA.RestClient`: verify poll happens on
  start, on refresh_now/0, and on schedule. Verify ETS state matches
  expected after a poll with unavailable + available entities.

Validation: `mix all_tests` passes. 100% coverage.

Smoke check: in iex, `Core.Blinds.StateCache.get_all() |> IO.inspect()`
returns the two SmartWings entries (initially unavailable). Wait 6s,
call again, confirm fresh `last_polled_at`.

### SB9 — `core: add Core.Blinds control functions + adaptive polling`

What:

- Extend `Core.Blinds` with:
  - `open(blind_id) :: :ok | {:error, term()}`
  - `close(blind_id)`
  - `stop(blind_id)`
  - `set_position(blind_id, position)` — `position` validated 0..100.
- Each function: load blind from DB, call corresponding HA service
  via `Core.HA.RestClient.call_service/3`, then call
  `Core.Blinds.StateCache.schedule_refresh_after(1_000)` so the cache
  picks up the new state quickly.
- Add the adaptive cadence to `StateCache`:
  - `schedule_refresh_after(ms)` cancels the current scheduled poll
    and schedules a new one `ms` from now. Returns to 5s steady-state
    after the next poll fires.
- Tests:
  - Each control function maps to the right HA service call (Mox
    assert).
  - Position validation rejects negative / >100 / non-integer values.
  - StateCache adaptive cadence: schedule, fire, return to 5s.

Validation: `mix all_tests` passes. 100% coverage.

Smoke check: deferred to pause SB-β.

### SB10 — `web: add BlindsController + routes`

What:

- `apps/web/lib/web/controllers/blinds_controller.ex` with:
  - `index/2` — returns `[{id, name, ha_entity_id, manufacturer, protocol}]`.
  - `states/2` — returns
    `[{id, ha_entity_id, state, position, available}]` from the
    cache, joined with DB blinds (so blinds without a cache entry
    yet show `available: false, state: nil`).
  - `set_position/2` — body `{"position": 0..100}`, calls
    `Core.Blinds.set_position/2`.
  - `open/2`, `close/2`, `stop/2` — no body.
- Router: new scope `/api/blinds` under the existing `:authenticated`
  pipeline (no `:home_id` prefix per Open Decision #7).
  - `GET /api/blinds` → `index`
  - `GET /api/blinds/states` → `states`
  - `POST /api/blinds/:id/position` → `set_position`
  - `POST /api/blinds/:id/open|close|stop` → respective controllers
- Authorization: any authenticated user (admin / resident / guest) can
  read; write actions require role in `~w(admin resident)`. Implement
  via a tiny `Web.Plugs.RequireRole` plug or inline pattern-match in
  the controller. Recommend a small plug for symmetry with v0's
  `RequireSession`.
- Tests: controller conn tests covering the happy path for each
  action plus 403 for guest-role attempting a write.

Validation: `mix all_tests` passes. 100% coverage.

Smoke check: deferred to pause SB-β.

### Pause SB-β — HTTP smoke test via curl

Before writing the seed task and deployment config, halt and verify
end-to-end through the HTTP layer.

1. Start the BE: `mix phx.server` (one terminal). Confirm Postgres is
   reachable and the StateCache GenServer logs successful polls.
2. From Bruno, acquire a fresh Auth0 access token. Exchange it for a
   session JWT via `POST /api/sessions`.
3. Call `GET /api/blinds` with `Authorization: Bearer <session_jwt>`.
   Confirm the two seeded blinds are returned.
4. Call `GET /api/blinds/states`. Confirm both blinds appear with
   `available: false` if Z-Wave is offline, or with their actual
   state if online.
5. If Z-Wave is online, call
   `POST /api/blinds/<id>/position` with body `{"position": 30}`.
   Confirm the blind moves and the next call to `GET /api/blinds/states`
   reflects the new position (within ~1 second thanks to the
   adaptive cadence).
6. Confirm the 403 path: log in as a user whose role is `guest` (or
   temporarily set yourself to guest via direct DB update) and confirm
   `POST` requests are rejected.

Do not advance until reads return real data and writes physically move
a blind (or, if Z-Wave is offline, until reads return all cover
entities with the unavailable shape).

### SB11 — `infra: add mix seed.blinds task`

What:

- `apps/core/lib/mix/tasks/seed_blinds.ex` — `Mix.Tasks.SeedBlinds`.
- Accepts `--blind <ha_entity_id>:<name>` (repeatable),
  `--manufacturer <string>` (default `SmartWings`),
  `--protocol <string>` (default `zwave`).
- Calls `Core.Blinds.create_blind/1` per `--blind`. Idempotent — if a
  blind with the same `ha_entity_id` already exists, update its
  `name` and continue rather than raising.
- Root `mix.exs` aliases: add `"seed.blinds": "seed_blinds"`.
- Coverage: add `lib/mix/tasks/seed_blinds.ex` to the
  `apps/core/coveralls.json` `skip_files` (thin wrapper, verified
  manually at SB-γ).

Validation: `mix all_tests` passes. `mix help seed.blinds` resolves.

Smoke check: `mix seed.blinds --blind cover.living_room_tv_right_outbound_bottom:Right --blind cover.living_room_tv_left_outbound_bottom:Left`
produces two rows in `blinds`.

### SB12 — `infra: env vars + docker-compose updates for HA + DB`

What:

- `.env.example`: add `HA_BASE_URL`, `HA_TOKEN`, `DATABASE_URL`,
  `SEED_ADMIN_AUTH0_SUB`. Mark required-in-prod with the existing
  comment convention.
- `.envrc.example`: matching exports with sensible local defaults
  (`HA_BASE_URL=$HOME_ASSISTANT_URL`,
  `HA_TOKEN=$HOME_ASSISTANT_API_KEY`,
  `DATABASE_URL=postgres://postgres:postgres@localhost/artemis_home_be_dev`).
- `docker-compose.yml`: add a `db: image: postgres:16-alpine` service
  with `pgdata` named volume, `POSTGRES_*` env, and `depends_on: [db]`
  on the BE service. Add `HA_BASE_URL`, `HA_TOKEN`, `DATABASE_URL`,
  `SEED_ADMIN_AUTH0_SUB` to the BE env block using the same
  `${VAR:?message}` strict-fail pattern.

Validation: `mix all_tests` passes (no code change). `docker compose
config` validates the compose file against a populated `.env`.

Smoke check: not strictly needed in v0.1 (Synology deploy is later);
note in the commit body that this is forward-compat scaffolding.

### Pause SB-γ — end-to-end with real blinds

Before opening a PR, halt and confirm the full chain works:

1. `mix ecto.reset` from the umbrella root (drops + recreates dev DB,
   seeds roles).
2. `mix seed.blinds --blind cover.living_room_tv_right_outbound_bottom:Right --blind cover.living_room_tv_left_outbound_bottom:Left`.
3. Start the BE: `mix phx.server`.
4. From Bruno, log in (creates the admin user row via SB5).
5. Hit `GET /api/blinds`, `GET /api/blinds/states`, then
   `POST /api/blinds/<id>/position` with `{position: 30}`.
6. Confirm the blind physically moves.
7. Repeat against the second blind.
8. Stop the BE; restart it; confirm the cache repopulates after the
   first poll cycle (no stale `unavailable` state for entities that
   are actually available in HA).

Capture any new request/response shapes discovered into
`planning/home-assistant-api/smart-blinds/` (specifically the pending
`04-get-state-available.md`, `05-set-position-response.md`,
`06-state-during-transition.md`).

### SB13 — `docs: update README with v0.1 runbook`

What:

- README: add a `## v0.1 — Smart Blinds` section covering:
  - Postgres prerequisite + how to set it up locally.
  - HA prerequisite (URL + long-lived token).
  - New env vars (`HA_BASE_URL`, `HA_TOKEN`, `DATABASE_URL`,
    `SEED_ADMIN_AUTH0_SUB`).
  - `mix ecto.setup` step.
  - `mix seed.blinds` usage.
  - The new endpoints (`GET /api/blinds`, `GET /api/blinds/states`,
    write actions).
  - Quick curl recipe for moving a blind end-to-end.
- Link to `planning/smart-blinds/plan.md` and
  `planning/smart-blinds/smart-blinds-implementation.md`.
- Link to `planning/home-assistant-api/` for HA wire details.

Validation: `mix all_tests` passes (docs only).

Smoke check: clone the repo into a fresh checkout (or another dir),
follow the README from scratch, verify each step works.

## Pause Points Summary

- **SB-α** (after SB7): raw HA REST client smoke test against the
  live instance.
- **SB-β** (after SB10): full HTTP smoke test via curl.
- **SB-γ** (after SB12): end-to-end with real blinds, fresh DB, full
  reset.

At each pause point I stop and explicitly confirm before continuing.
If a pause point reveals a problem, fixes are made in subsequent
commits with appropriate scope, not by rewriting prior commits.

## What could cause an unscheduled pause

I will also pause out of cycle if:

- Z-Wave is offline at SB-α and we can't proceed past read-only
  verification.
- HA's actual response shape differs from what
  `planning/home-assistant-api/smart-blinds/` captured (especially
  during the pending `state: open|closed|opening|closing` captures
  once Z-Wave is back).
- A library API has changed (e.g. Ecto 3.x → 4.x while we're working).
- The blinds context needs cross-table queries that justify a new
  schema not in v0.1's scope.
- `mix all_tests` fails for a reason not covered by the in-progress
  commit (a transitive dep upgrade, a Dialyzer false positive that
  needs adding to `.dialyzer_ignore.exs`).

In all such cases, I will surface the conflict, propose options, and
wait for direction.

## After v0.1

When this milestone merges:

- The FE agent's blinds-management work in
  `artemis_home_fe/planning/` becomes unblocked end-to-end against
  the new endpoints.
- v0.2 candidates: rooms (with outline JSONB), `mix seed.users` /
  admin endpoint for adding members, schedule support, HA WebSocket
  for push-based state.
