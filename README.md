# artemis_home_be

Elixir/Phoenix umbrella backend for Artemis, a multi-home automation
system. Each home runs its own isolated BE instance; users authenticate
once against Auth0 and the frontend fans out to every home in their
Auth0 `app_metadata.homes` registry.

v0 was the **proof of concept** validating the Auth0-as-identity-hub
architecture end-to-end without home-automation features. v0.1 builds
on v0 with Postgres-backed schemas (`roles`, `users`, `blinds`), a
Home Assistant REST client, an ETS-backed state cache, and the first
real device-control endpoints: motorized window blinds.

The full architectural rationale lives in
`planning/v0_docs/implementation-plan.md` (v0) and
`planning/smart-blinds/plan.md` plus
`planning/smart-blinds/smart-blinds-implementation.md` (v0.1).

The React FE that drives this BE lives in a sibling repo,
`artemis_home_fe`.

## Status

- **v0.1 Smart Blinds** is feature-complete and smoke-verified
  end-to-end against live Home Assistant + Z-Wave + SmartWings
  blinds. See `## v0.1 — Smart Blinds` below.
- v0 web layer still exposes `POST /api/sessions`, `GET /api/me/ping`,
  and `POST /api/admin/register-home`.
- v0.1 adds `GET /api/blinds`, `GET /api/blinds/states`, and
  `POST /api/blinds/:id/{position,open,close,stop}`.
- v0.1 changes the single-home model: each BE instance now serves
  exactly one home (no `homes` table, no `home_id` FKs). Multi-home
  remains a frontend concern — the FE fans out across one BE
  instance per entry in the user's Auth0
  `app_metadata.homes` registry.

## Repository layout

```
artemis_home_be/                    # umbrella root
├── apps/
│   ├── core/                       # auth context, Auth0 wrappers, session keys (v0)
│   ├── dispatch/                   # skeleton; Oban scheduling lives here in v1
│   ├── mcp/                        # skeleton; MCP protocol handler lives here in v1
│   └── web/                        # Phoenix JSON API (no Ecto, no HTML)
├── config/                         # umbrella-wide configuration
├── planning/                       # v0 and v1 planning docs (tracked)
│   └── v0_docs/
│       ├── implementation-plan.md
│       └── step-by-step-commit-strat-be.md
├── docker-compose.yml              # Synology / Compose deployment template
├── .env.example                    # documented runtime env vars
└── README.md                       # this file
```

## Prerequisites

- Elixir 1.19 / Erlang OTP 28 (pinned via `.tool-versions`).
- Phoenix 1.8.x (resolved automatically by `mix deps.get`).
- Auth0 tenant with:
  - A **Single Page Application** for browser/Bruno login
    (Authorization Code + PKCE, no client secret).
  - An **API** resource whose Identifier matches `AUTH0_AUDIENCE`.
  - A **Machine to Machine Application** authorized for the Auth0
    Management API with scopes `read:users` and `update:users_app_metadata`.
  - A **Post-Login Action** that copies `event.user.app_metadata.homes`
    onto the `https://artemis.app/homes` custom claim of both the
    access token and the ID token. Full snippet in
    `planning/v0_docs/implementation-plan.md` §Auth0 Configuration.
- Docker (Compose v2) only if you intend to run via the deployment
  template instead of `mix phx.server`.

## Environment variables

Copy `.env.example` to `.env` and fill in real values. `.env` is
gitignored. Variables fall into three groups:

- **Required at boot (`:prod`):** `HOME_ID`, `PHX_HOST`,
  `SECRET_KEY_BASE`, `AUTH0_DOMAIN`, `AUTH0_M2M_CLIENT_ID`,
  `AUTH0_M2M_CLIENT_SECRET`, `CORS_ALLOWED_ORIGINS`. Missing values
  fail container startup loud and fast.
- **Defaulted:** `AUTH0_AUDIENCE` (defaults to
  `https://artemis.app/api`), `PORT` (defaults to `6565`),
  `HOST_PORT` (host-side port mapping in Compose, defaults to `6565`),
  `KEYS_PATH` (host path mounted for RSA session signing keys),
  `TZ` (container timezone).
- **Test:** test config in `config/test.exs` supplies all values
  itself; `runtime.exs` is a no-op in `:test`.

Full table with descriptions is in
`planning/v0_docs/implementation-plan.md` §Runtime configuration (BE).

## Running locally (two-home dev setup)

The v0 PoC demonstrates multi-home fan-out, so the standard local
setup runs **two BE instances simultaneously** with different
`HOME_ID` and `PORT`. Each terminal:

```bash
# Terminal 1 — "alpha"
HOME_ID=alpha PORT=6565 \
AUTH0_DOMAIN=your-tenant.us.auth0.com \
AUTH0_AUDIENCE=https://artemis-home.fly.dev \
AUTH0_M2M_CLIENT_ID=... \
AUTH0_M2M_CLIENT_SECRET=... \
  mix phx.server

# Terminal 2 — "beta"
HOME_ID=beta PORT=6566 \
  (same Auth0 vars) \
  mix phx.server
```

The two instances share the BE codebase but are independent at
runtime: separate `priv/keys/session_signing.pem` keypairs, separate
in-memory JWKS caches, and they each reject tokens whose homes claim
doesn't list their own `HOME_ID`.

## Seeding homes for a test user

Before the FE can fan out, a user's `app_metadata.homes` must contain
the `{home_id, url}` entries. Use the `seed.homes` mix task with M2M
credentials exported in your shell:

```bash
export AUTH0_DOMAIN=your-tenant.us.auth0.com
export AUTH0_M2M_CLIENT_ID=...
export AUTH0_M2M_CLIENT_SECRET=...

mix seed.homes \
  --user-sub "google-oauth2|..." \
  --home alpha:http://localhost:6565 \
  --home beta:http://localhost:6566
```

The task is read-modify-write so repeated invocations accumulate.
Full doc: `mix help seed.homes`.

## v0.1 — Smart Blinds

v0.1 ships motorized-blind control end-to-end. The BE caches HA
cover-entity state in ETS, polls HA every 5 s (with a 1 s adaptive
refresh after a write), and exposes a small JSON API the FE drives.

### Additional prerequisites

- **Postgres 16** reachable locally on `localhost:5432`. On macOS:
  `brew services start postgresql@16`. The default dev config uses
  the `postgres` superuser with no password; override via
  `DATABASE_URL` if your setup differs.
- **Home Assistant** reachable at `HA_BASE_URL`. The URL must
  include the `/api` suffix (e.g.
  `http://homeassistant.local:8123/api`). Generate a long-lived
  access token in HA Profile → Security and export it as `HA_TOKEN`.
- For Z-Wave covers specifically: the Z-Wave JS UI integration and
  USB stick must be online. Affected cover entities will report
  `state: "unavailable"` until the radio recovers; the cache marks
  them `available: false` automatically.

### New env vars

  | Var                    | Where required        | Notes                                              |
  |------------------------|-----------------------|----------------------------------------------------|
  | `HA_BASE_URL`          | dev + prod            | Full URL incl. `/api`. Legacy `HOME_ASSISTANT_URL` accepted in dev as a fallback. |
  | `HA_TOKEN`             | dev + prod            | HA long-lived access token. `HOME_ASSISTANT_API_KEY` accepted in dev. |
  | `DATABASE_URL`         | required in prod      | Optional in dev (defaults to local Postgres).      |
  | `SEED_ADMIN_AUTH0_SUB` | optional everywhere   | When the `users` table is empty AND a login's Auth0 sub matches this value, the first user is created with role `admin`. |

Full templates: `.env.example` (Compose) and `.envrc.example`
(direnv / local mix workflows).

### One-time setup

```bash
mix ecto.setup          # creates DB, runs migrations, seeds roles
mix seed.blinds \
  --blind cover.living_room_tv_right_outbound_bottom:Right \
  --blind cover.living_room_tv_left_outbound_bottom:Left
```

`mix seed.blinds` is idempotent: re-running with the same
`ha_entity_id` updates the existing row's `name` (and
`manufacturer` / `protocol` if supplied). `sort_order` is preserved
across re-seeds.

### Endpoints

  | Method | Path                          | Role(s)              | Body                              |
  |--------|-------------------------------|----------------------|-----------------------------------|
  | GET    | `/api/blinds`                 | admin/resident/guest | —                                 |
  | GET    | `/api/blinds/states`          | admin/resident/guest | —                                 |
  | POST   | `/api/blinds/:id/position`    | admin/resident       | `{"position": 0..100}` (integer)  |
  | POST   | `/api/blinds/:id/open`        | admin/resident       | —                                 |
  | POST   | `/api/blinds/:id/close`       | admin/resident       | —                                 |
  | POST   | `/api/blinds/:id/stop`        | admin/resident       | —                                 |

Reads return JSON arrays. Write endpoints return `204 No Content`
on success. Error codes:

  | Status | `error` value      | Cause                                          |
  |--------|--------------------|------------------------------------------------|
  | 400    | `invalid_position` | position missing, non-integer, or out of range |
  | 401    | `unauthorized`     | missing/invalid session JWT                    |
  | 403    | `forbidden`        | role not in the allow-list (guests on writes)  |
  | 404    | `bad_id` / `not_found` | unparseable id / no matching blind row     |
  | 503    | `ha_unreachable`   | HA transport failure                           |
  | 503    | `ha_status`        | HA returned a non-2xx status                   |

### Quick curl recipe (move a blind end-to-end)

Assumes `mix phx.server` is running on `:6565` and you have a session
JWT (acquired via `POST /api/sessions` with a fresh Auth0 access
token — see the v0 smoke section below).

```bash
SESSION_JWT=...
BE=http://localhost:6565

curl -sS -H "Authorization: Bearer $SESSION_JWT" $BE/api/blinds | jq
curl -sS -H "Authorization: Bearer $SESSION_JWT" $BE/api/blinds/states | jq

curl -sS -X POST \
  -H "Authorization: Bearer $SESSION_JWT" \
  -H "Content-Type: application/json" \
  -d '{"position": 30}' \
  $BE/api/blinds/1/position

# Wait ~10s for the Z-Wave round-trip, then re-poll states.
sleep 10
curl -sS -H "Authorization: Bearer $SESSION_JWT" $BE/api/blinds/states | jq
```

Z-Wave latency from "service accepted" to "HA reflects the new
position" is ~6–10 s on a typical home LAN; the FE should display a
pending indicator until the cached `current_position` reflects the
requested move. The position-vs-state behaviour during transitions
is documented in
`planning/home-assistant-api/smart-blinds/06-state-during-transition.md`.

## Smoke-testing the HTTP surface

With both BE instances running and homes seeded:

1. Acquire a real Auth0 access token via Bruno (see
   `../artemis_home_fe/temp/bruno.md`) or by capturing one from a
   browser DevTools network panel after login.
2. Hit each instance to verify the full session-exchange + ping loop:

   ```bash
   # Exchange Auth0 token → session JWT (against alpha)
   curl -sS -X POST http://localhost:6565/api/sessions \
     -H "Authorization: Bearer $AUTH0_ACCESS_TOKEN" | jq

   # Ping with the returned session JWT
   curl -sS http://localhost:6565/api/me/ping \
     -H "Authorization: Bearer $SESSION_JWT" | jq
   ```

3. Repeat against `:6566` (beta). Both should return their respective
   `home_id` and the same `user_sub`.

## Tests and quality gates

Run the full umbrella suite plus lint, format, coverage, and static
analysis:

```bash
mix all_tests
```

This runs `compile --warnings-as-errors`, `credo --strict`,
`format --check-formatted`, `coveralls --umbrella --raise` (enforced
100% on owned code via per-app `coveralls.json`), and
`dialyzer --list-unused-filters`.

A lighter pre-commit alias is available:

```bash
mix precommit       # compile, format check, test only
```

## Deploying as a container

The repo ships a `docker-compose.yml` template for Synology Container
Manager, Docker Desktop, or any Compose-aware host. Required env vars
use the `${VAR:?message}` pattern so Compose itself errors at
evaluation time if any are unset.

```bash
cp .env.example .env
$EDITOR .env                # fill in real values
docker compose up -d
```

A single host path (default `./keys`) is bind-mounted into the
container at `/app/apps/core/priv/keys` so the BE's RSA session
signing key survives container restarts. Per-instance container
deploys must use different `KEYS_PATH` values so alpha and beta
keep independent keypairs.

The multi-stage release `Dockerfile` is deferred to a later v0
commit or to v1. v0 itself runs locally via `mix phx.server`; the
deployment artifacts are forward-compatibility templates.

## Where to look next

- `planning/smart-blinds/plan.md` — v0.1 milestone plan.
- `planning/smart-blinds/smart-blinds-implementation.md` — commit
  sequence (SB1–SB13 + three smoke pauses) for v0.1.
- `planning/home-assistant-api/` — captured HA REST wire shapes
  (cover entity states, service responses, transition shapes).
- `planning/technical-design.md` — current data-model and module
  layout, updated for v0.1's single-home model.
- `planning/v0_docs/implementation-plan.md` — cross-repo architecture
  and decisions for the v0 PoC.
- `planning/v0_docs/step-by-step-commit-strat-be.md` — commit-by-commit
  build history of v0.
- `../artemis_home_fe/planning/v0_docs/implementation-plan.md` —
  React SPA companion.
- `../artemis_home_fe/planning/issues.md` — known v0 issues being
  accepted (multi-home token exposure, per-home CORS config).
- `../artemis_home_fe/planning/v1-concerns.md` — items deferred to
  v1+ (register-home UI, logout UX, mobile clients, etc.).

