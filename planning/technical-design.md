# Technical Design: Artemis Home

> **Schema model:** single-home per BE. Each `artemis_home_be` instance
> serves exactly one home; multi-home is a frontend concept (the FE
> fans out HTTP calls across N BEs based on the Auth0
> `app_metadata.homes` claim). The §Data Models section below reflects
> this. The pre-v0.1 multi-home schema (with `homes`, `home_memberships`,
> `home_id` foreign keys) is preserved in git history at the v0
> commit. See `planning/smart-blinds/plan.md` for the v0.1 milestone
> that introduces this schema.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Public Internet                                                │
│                                                                 │
│  Phone/iPad/Desktop ──► Cloudflare Tunnel ──┐                   │
│  MCP Client (OpenClaw) ─────────────────────┤                   │
│  Auth0 ◄──────────────────────────────────► │                   │
└─────────────────────────────────────────────┼───────────────────┘
                                              │
┌─────────────────────────────────────────────┼───────────────────┐
│  Synology NAS (Docker Compose)              │                   │
│                                             ▼                   │
│  ┌──────────────┐    HTTP     ┌──────────────────┐              │
│  │ artemis_fe   │ ──────────►│  artemis_be       │              │
│  │ (LiveView)   │◄────────── │  (Phoenix API)    │              │
│  │ Port 4001    │  Channels  │  Port 4000        │              │
│  └──────────────┘            └────────┬──────────┘              │
│                                       │                         │
│                              HTTP     │  Postgres               │
│                              (Req)    │  (Ecto)                 │
│                                       │                         │
│                    ┌──────────────┐   │   ┌──────────────┐      │
│                    │ Home         │◄──┘   │ PostgreSQL   │      │
│                    │ Assistant    │       │ Port 5432    │      │
│                    │ Port 8123   │       └──────────────┘      │
│                    └──────┬───────┘                              │
│                           │ WebSocket                           │
│                    ┌──────┴───────┐                              │
│                    │ Z-Wave JS UI │                              │
│                    │ Port 8091    │                              │
│                    └──────┬───────┘                              │
│                           │ USB                                 │
│                    ┌──────┴───────┐                              │
│                    │ Z-Wave Stick │                              │
│                    └──────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**artemis_home_be (Port 6565) — Umbrella App, one instance per home**

Each deployment of `artemis_home_be` serves exactly one home; the home
is identified by env var (`HOME_ID`) and connects to one Home
Assistant instance (`HA_BASE_URL`, `HA_TOKEN`). Multi-home is the
frontend's job — the React FE issues HTTP calls in parallel across
the BE instances listed in the Auth0 user's `app_metadata.homes`
claim.

Four child apps under `apps/`:

- **`:core`** — Business logic, Ecto schemas, contexts, validations. Owns all data models (users, devices, schedules, PATs, configurations). No web dependencies. All other apps depend on this.
- **`:dispatch`** — Oban job scheduling and execution. Schedule workers that load configs from `:core` and execute actions via `:core`'s HA client interface. Isolated so job processing concerns don't bleed into web or MCP.
- **`:mcp`** — MCP JSON-RPC protocol handler. Translates MCP `tools/list` and `tools/call` requests into `:core` context calls. Authenticated via PATs. Can run as a plug pipeline or a separate endpoint.
- **`:web`** — Phoenix JSON API. Controllers, channels, plugs, router. Thin layer that validates HTTP input, calls `:core` contexts, and returns JSON. Hosts Phoenix Channels for real-time state broadcasting.

**artemis_home_fe (Port 4001)**
- Phoenix LiveView app (standalone, not an umbrella)
- Consumes BE API via Req (HTTP) for all operations (mutations + state polling)
- No WebSocket/Channel connection to BE — purely HTTP
- LiveView polls BE for device states on pages where live state matters
- Renders all UI (HEEx + Tailwind)
- PWA manifest and service worker
- Auth0 redirect handling (login/callback pages)
- No database, no direct HA access

## Data Models

All schemas live in the `:core` app. Each BE serves exactly one home,
so there is no `homes` table, no `home_memberships`, and no `home_id`
foreign key on any device or schedule table. The home's identity is
the BE itself.

### v0.1 minimum schema

v0.1 ships only the following tables.

#### roles
```
id              BIGSERIAL PRIMARY KEY
name            VARCHAR UNIQUE NOT NULL   -- 'admin', 'resident', 'guest'
description     VARCHAR
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Seeded on app startup with at least: `admin`, `resident`, `guest`.

#### users
```
id              BIGSERIAL PRIMARY KEY
auth0_sub       VARCHAR UNIQUE NOT NULL    -- e.g. "google-oauth2|117394610565503842179"
email           VARCHAR NOT NULL
name            VARCHAR NOT NULL
picture         VARCHAR
role_id         BIGINT REFERENCES roles(id) NOT NULL
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Every row in `users` is implicitly a member of this BE's home. Role
is carried directly on the user — there is no `home_memberships`
table. First-user-becomes-admin is handled by a `SEED_ADMIN_AUTH0_SUB`
env var read at boot.

#### blinds
```
id              BIGSERIAL PRIMARY KEY
name            VARCHAR NOT NULL           -- "Left Window Blind"
ha_entity_id    VARCHAR UNIQUE NOT NULL    -- "cover.living_room_tv_right_outbound_bottom"
manufacturer    VARCHAR                    -- "SmartWings"
protocol        VARCHAR                    -- "zwave"
sort_order      INTEGER NOT NULL DEFAULT 0
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Future device tables follow the same shape (no `home_id`, optional
`room_id` once rooms land):
- `locks` — name, ha_entity_id, supports_codes, max_codes, ...
- `lights` — name, ha_entity_id, supports_brightness, supports_rgb, ...
- `thermostats` — name, ha_entity_id, supports_heat, supports_cool, min_temp, max_temp, ...
- `garage_doors` — name, ha_entity_id, auto_close_timeout_minutes, ...

No generic `devices` table. Each type is a first-class schema.

### Connection config (not in DB)

The Home Assistant base URL and long-lived access token live in env
vars (`HA_BASE_URL`, `HA_TOKEN`) rather than a `homes` row. They are
read once at boot and injected into the HA REST client. Plaintext at
rest in v0.1; encryption deferred (HA is local-network only).

### Tables deferred to later milestones

- `rooms` (with outline JSONB) — v0.2+, when the FE has an outline
  view. v0.1 renders blinds as a flat list.
- `invitations` — when the FE has a "manage members" page. Until
  then, admins create users via a direct admin endpoint or by
  setting `SEED_ADMIN_AUTH0_SUB`.
- `blind_schedules`, `blind_schedule_runs` — when scheduling lands
  (Oban worker + GenServer evaluator).
- `saved_configurations` — named multi-blind presets.
- `activity_log` — added cross-cutting after multiple device types
  exist.
- `personal_access_tokens` — when MCP server lands.

### Shape of future tables (no `home_id` anywhere)

When the deferred tables land, none of them carry a `home_id` — each
row exists in the BE that owns that home. Column lists below are
illustrative; the precise schema lands with each milestone.

- `activity_log(id, user_id, device_type, device_id, action, details JSONB, source, inserted_at)`
- `saved_configurations(id, name, actions JSONB, user_id, inserted_at, updated_at)`
- `blind_schedules(id, name, blind_ids JSONB, action, position, cron_expression, timezone, active, user_id, ...)`
- `blind_schedule_runs(id, blind_schedule_id, status, started_at, completed_at, error_details, results JSONB)`
- `guest_keys(id, token, label, allowed_scopes JSONB, expires_at, revoked_at, created_by_id, ...)`
- `personal_access_tokens(id, token_hash, label, scopes JSONB, user_id, expires_at, revoked_at, last_used_at, ...)`
- `user_preferences(id, user_id UNIQUE, theme, inserted_at, updated_at)` — no `default_home_id`; the FE picks the active home and stores that preference itself.

Future device types follow the same single-home-per-BE pattern: their
type-specific schedule table is `light_schedules`, `thermostat_schedules`,
etc., still no `home_id`.

## Auth Flow

### User Login (Auth0 OIDC)

```
Browser                 artemis_fe              Auth0               artemis_be
   │                        │                     │                      │
   │  Click "Login"         │                     │                      │
   │───────────────────────►│                     │                      │
   │                        │  Redirect to Auth0  │                      │
   │◄───────────────────────│  /authorize?...     │                      │
   │                        │                     │                      │
   │  Auth0 login page      │                     │                      │
   │───────────────────────────────────────────►  │                      │
   │  User authenticates    │                     │                      │
   │◄───────────────────────────────────────────  │                      │
   │                        │                     │                      │
   │  Redirect to FE /callback?code=X&state=Y    │                      │
   │───────────────────────►│                     │                      │
   │                        │  POST /api/auth/callback {code, state}     │
   │                        │─────────────────────────────────────────► │
   │                        │                     │  Exchange code       │
   │                        │                     │◄─────────────────── │
   │                        │                     │  Return tokens       │
   │                        │                     │───────────────────► │
   │                        │                     │                      │
   │                        │                     │  Verify ID token     │
   │                        │                     │  (JWKS)              │
   │                        │                     │  Upsert user         │
   │                        │                     │  Create session      │
   │                        │  Return session cookie                     │
   │                        │◄───────────────────────────────────────── │
   │  Set cookie, redirect  │                     │                      │
   │◄───────────────────────│                     │                      │
   │  Dashboard             │                     │                      │
```

### Guest Access

```
Browser                 artemis_fe              artemis_be
   │                        │                      │
   │  Visit /?guest_key=abc │                      │
   │───────────────────────►│                      │
   │                        │  POST /api/auth/guest {key: "abc"}
   │                        │─────────────────────►│
   │                        │                      │ Validate key
   │                        │                      │ Check expiry
   │                        │  Return guest session + allowed scopes
   │                        │◄─────────────────────│
   │  Render limited UI     │                      │
   │◄───────────────────────│                      │
```

### PAT Authentication (MCP / API)

```
MCP Client              artemis_be
   │                        │
   │  GET /api/devices      │
   │  Authorization: Bearer <PAT>
   │───────────────────────►│
   │                        │ Hash PAT
   │                        │ Lookup token_hash in personal_access_tokens
   │                        │ Check expiry, revoked_at
   │                        │ Check scopes
   │                        │ Update last_used_at
   │  200 OK + devices      │
   │◄───────────────────────│
```

## Backend Module Structure (Umbrella)

```
artemis_home_be/
├── apps/
│   ├── core/
│   │   └── lib/core/
│   │       ├── application.ex
│   │       ├── repo.ex
│   │       │
│   │       ├── accounts/
│   │       │   ├── accounts.ex          # Context: upsert_user, get_user
│   │       │   └── user.ex             # Ecto schema
│   │       │
│   │       ├── auth/
│   │       │   ├── auth.ex              # Context: verify_token, create_session
│   │       │   ├── auth0_client.ex      # Auth0 code exchange, JWKS verification
│   │       │   ├── guest_key.ex         # Ecto schema
│   │       │   ├── guest_keys.ex        # Context: create, validate, revoke
│   │       │   ├── pat.ex              # Ecto schema
│   │       │   └── pats.ex             # Context: create, validate, revoke
│   │       │
│   │       ├── ha/
│   │       │   ├── rest_client.ex      # Behaviour for HA REST API calls
│   │       │   └── rest_client/
│   │       │       └── http_fetcher.ex # Default impl (Req-based)
│   │       │
│   │       ├── blinds/
│   │       │   ├── blinds.ex           # Context: CRUD + open/close/set_position/stop
│   │       │   ├── blind.ex            # Ecto schema
│   │       │   └── state_cache.ex      # GenServer + ETS, polls HA, adaptive cadence
│   │       │
│   │       ├── activity/
│   │       │   ├── activity.ex          # Context: log actions, query history
│   │       │   └── activity_log.ex     # Ecto schema
│   │       │
│   │       ├── import/
│   │       │   ├── importer.ex          # JSON ingestion: rooms, devices, configs
│   │       │   └── schemas.ex          # JSON schema validation per type
│   │       │
│   │       └── cache/
│   │           └── device_cache.ex     # ETS-based cache with TTL for HA state
│   │
│   ├── dispatch/
│   │   └── lib/dispatch/
│   │       ├── application.ex          # Oban supervisor
│   │       └── workers/
│   │           └── schedule_worker.ex  # Oban worker: execute scheduled actions
│   │
│   ├── mcp/
│   │   └── lib/mcp/
│   │       ├── application.ex
│   │       ├── server.ex               # MCP JSON-RPC protocol handler
│   │       ├── tools.ex                # Tool definitions (list_devices, control, etc.)
│   │       └── router.ex              # Routes MCP tool calls to Core contexts
│   │
│   └── web/
│       └── lib/web/
│           ├── application.ex
│           ├── endpoint.ex
│           ├── router.ex
│           ├── controllers/
│           │   ├── auth_controller.ex
│           │   ├── blind_controller.ex    # Blinds CRUD + control
│           │   ├── room_controller.ex
│           │   ├── config_controller.ex  # Saved configurations
│           │   ├── schedule_controller.ex
│           │   ├── import_controller.ex  # JSON import endpoint
│           │   ├── guest_key_controller.ex
│           │   ├── pat_controller.ex
│           │   └── health_controller.ex
│           │
│           ├── plugs/
│           │   ├── authenticate.ex     # Verify session or PAT
│           │   ├── authorize.ex        # Check role/scopes
│           │   └── guest_auth.ex       # Validate guest key
│           │
│           └── views/
│               ├── device_json.ex
│               ├── room_json.ex
│               ├── schedule_json.ex
│               └── error_json.ex
```

## Frontend Module Structure

```
artemis_home_fe/
├── lib/
│   ├── artemis_home_fe/
│   │   ├── application.ex
│   │   └── api_client.ex               # Req-based client for calling artemis_be API
│   │
│   └── artemis_home_fe_web/
│       ├── endpoint.ex
│       ├── router.ex
│       ├── components/
│       │   ├── layouts.ex
│       │   ├── layouts/root.html.heex
│       │   └── core_components.ex
│       │
│       ├── live/
│       │   ├── dashboard_live.ex       # Room grid + "All" button
│       │   ├── room_live.ex            # Room detail — switches between views
│       │   ├── room_outline_live.ex    # Outline view: SVG room map with blind controls
│       │   ├── room_list_live.ex       # List view: blinds table with state
│       │   ├── blind_control_live.ex   # Single blind detail modal (open/close/position)
│       │   ├── configs_live.ex         # Saved configurations list + execute
│       │   ├── config_form_live.ex     # Create/edit saved configuration
│       │   ├── schedules_live.ex       # Schedule list and management
│       │   ├── schedule_form_live.ex   # Create/edit schedule
│       │   ├── settings/
│       │   │   ├── rooms_live.ex       # Add/edit/delete rooms (form + JSON import)
│       │   │   ├── devices_live.ex     # Add/edit/delete devices (form + JSON import)
│       │   │   ├── import_live.ex      # Bulk JSON import page
│       │   │   ├── homes_live.ex       # List of homes user is admin of
│       │   │   ├── home_manage_live.ex # Home management: members, invites, HA config
│       │   │   ├── home_setup_live.ex  # Create new home wizard
│       │   │   └── pats_live.ex        # PATs for MCP (scoped to selected home)
│       │   ├── auth/
│       │   │   ├── login_live.ex
│       │   │   └── callback_live.ex
│       │   └── profile_live.ex
│       │
│       └── controllers/
│           └── auth_controller.ex      # Handles Auth0 redirect (non-LiveView)
│
├── assets/
│   ├── js/
│   │   ├── app.js
│   │   └── hooks/
│   │       ├── position_slider.js      # Drag-based blind position control
│   │       ├── room_outline.js         # SVG room rendering + interactive blind positions
│   │       └── clipboard.js            # Copy-to-clipboard for guest keys/PATs
│   ├── css/
│   │   └── app.css                     # Tailwind imports + custom transitions
│   └── static/
│       ├── manifest.json               # PWA manifest
│       ├── sw.js                       # Service worker
│       └── icons/                      # PWA icons (various sizes)
```

## Frontend Navigation Flow

### Global Header
```
┌─────────────────────────────────────────────────────────┐
│  Artemis    [Home Dropdown: "Main House" ▼]   [Profile] │
└─────────────────────────────────────────────────────────┘
```
- Home dropdown in header to switch between homes (only shown if user belongs to >1 home)
- No dropdown if user has only one home
- All dashboard content is scoped to the currently selected home

### Main Dashboard (scoped to current home)
```
Dashboard
├── [Room Button: "Main Bedroom"] ──► Room Detail
│                                      ├── Outline View (SVG map with blind positions)
│                                      └── List View (table: name | state | controls)
├── [Room Button: "Living Room"] ──► Room Detail
├── [Room Button: "Office"] ──► Room Detail
├── ["All" Button] ──► All devices flat list + batch controls
│
├── Saved Configs tab ──► List saved configs for this home + "Run" button each
│                         └── Create/Edit config form
│
└── Schedules tab ──► Schedule list for this home + toggle active/inactive
                      └── Create/Edit schedule form
```

### Settings (separate from dashboard, accessible via nav/profile menu)
```
Settings
├── Home Management (admin only per home)
│   ├── List of homes user is admin of
│   ├── [Home: "Main House"] ──►
│   │     ├── Members list (name, email, role)
│   │     ├── Invite user (email + role picker)
│   │     ├── Remove member
│   │     ├── Promote/demote user roles
│   │     ├── Home settings (name, HA connection)
│   │     └── PATs (MCP server tokens, scoped to this home)
│   └── [+ Create New Home] ──► Setup wizard (name, HA URL, HA token)
│
├── Device Management (admin, scoped to current home)
│   ├── Rooms (add/edit/delete + JSON import)
│   ├── Devices (add/edit/delete + JSON import + device pairing)
│   └── Bulk JSON import
│
└── Profile
    ├── Name, email, avatar
    ├── Homes I belong to (with roles)
    └── Logout
```

## FE ↔ BE Communication

Two patterns, no WebSocket/Channel between FE and BE:

### Synchronous HTTP (all mutations and CRUD)
```
User action → LiveView handle_event → ApiClient.post() via Req → BE API
  → BE processes (calls HA, writes DB, etc.) → returns JSON response
  → LiveView updates assigns → UI re-renders
```
Used for: device commands, CRUD (rooms, blinds, schedules, users, homes), device pairing, settings, auth.

### Polling (live device state)
```
LiveView mount → Process.send_after(:poll_states, 5_000)
  → handle_info(:poll_states) → ApiClient.get("/api/homes/:id/blinds/states")
  → BE returns cached state from ETS → LiveView updates assigns → UI re-renders
  → Process.send_after(:poll_states, 5_000) (loop)
```
Used for: blind positions/state, and any future device type that has live state (locks, lights, thermostat temps).

### BE → HA State Caching
```
GenServer poll loop (every 5-10s) → GET /api/states from HA
  → Diff against ETS cache → Update changed entries
  → FE polls pick up changes on next cycle
```

The FE never connects directly to the BE via WebSocket or Channel. All communication is HTTP.
Future enhancement: add Channels or distributed Erlang for sub-second state push if polling latency becomes a problem.

## Deployment: docker-compose.yml

```yaml
services:
  artemis_be:
    build: ./artemis_home_be
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=ecto://postgres:postgres@db:5432/artemis_home
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - HA_BASE_URL=http://homeassistant:8123
      - HA_TOKEN=${HA_TOKEN}
      - AUTH0_DOMAIN=${AUTH0_DOMAIN}
      - AUTH0_CLIENT_ID=${AUTH0_CLIENT_ID}
      - AUTH0_CLIENT_SECRET=${AUTH0_CLIENT_SECRET}
      - PHX_HOST=${PHX_HOST}
    depends_on:
      - db
      - homeassistant

  artemis_fe:
    build: ./artemis_home_fe
    ports:
      - "4001:4001"
    environment:
      - ARTEMIS_API_URL=http://artemis_be:4000
      - SECRET_KEY_BASE=${SECRET_KEY_BASE_FE}
      - PHX_HOST=${PHX_HOST}
    depends_on:
      - artemis_be

  db:
    image: postgres:16-alpine
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=artemis_home

  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    volumes:
      - /volume1/docker/homeassistant/config:/config
    network_mode: host  # or bridge with port mapping
    restart: unless-stopped

  zwavejs:
    image: zwavejs/zwave-js-ui:latest
    volumes:
      - /volume1/docker/zwavejs:/usr/src/app/store
    ports:
      - "8091:8091"
      - "3000:3000"
    # devices:
    #   - "/dev/serial/by-id/<ZWAVE_STICK_ID>:/dev/zwave"
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale:latest
    hostname: artemis
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_EXTRA_ARGS=--advertise-tags=tag:server
      - TS_SERVE_CONFIG=/config/serve.json  # Funnel config: route HTTPS to artemis_fe:4001
    volumes:
      - tailscale-state:/var/lib/tailscale
      - ./tailscale:/config
    cap_add:
      - net_admin
      - sys_module
    restart: unless-stopped

volumes:
  pgdata:
  tailscale-state:
```

## Key Dependencies

### Backend (artemis_home_be)
- phoenix ~> 1.8
- phoenix_ecto ~> 4.5
- ecto_sql ~> 3.13
- postgrex
- jason
- req ~> 0.5 (HTTP client for HA API and Auth0)
- jose ~> 1.11 (JWT verification)
- oban ~> 2.18 (job scheduling)
- bandit ~> 1.5 (HTTP server)

### Frontend (artemis_home_fe)
- phoenix ~> 1.8
- phoenix_live_view ~> 1.1
- phoenix_html ~> 4.1
- req ~> 0.5 (HTTP client for calling BE API)
- jason
- bandit ~> 1.5
- esbuild, tailwind (asset pipeline)

## Open Design Questions

1. **HA polling vs WebSocket for BE→HA**: v0.1 polls HA states via
   REST. HA also has a WebSocket API that pushes `state_changed`
   events. WebSocket is better for latency but adds complexity. Defer
   to v0.3+.

2. **Per-device sort ordering source of truth**: The DB has
   `sort_order` but the FE will likely want drag-to-reorder. Decide
   whether the FE writes back the new sort order or the BE assigns
   it on insert and lets the FE re-render.

3. **Multi-instance BE deployment story on Synology.** Two BEs (alpha
   + beta) on one Synology box need separate Postgres databases and
   separate `KEYS_PATH` mounts. The current docker-compose template
   assumes a single instance; multi-instance Compose layout is
   deferred until we actually deploy two homes simultaneously.

### Resolved (previously open)

- **FE-to-BE auth token flow** — Resolved in v0. BE issues an RS256
  session JWT after verifying the Auth0 access token; FE stores it
  in memory and forwards it as `Authorization: Bearer <jwt>` on
  every API call. See `planning/v0_docs/implementation-plan.md`.
- **Auth0 token handling in FE** — Resolved in v0. FE keeps the
  Auth0 access token in memory (`@auth0/auth0-react` SDK), uses it
  only for `POST /api/sessions` to exchange for the BE session JWT,
  then forgets it. See `artemis_home_fe/planning/v0_docs/implementation-plan.md`.
