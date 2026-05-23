# Technical Design: Artemis Home

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

**artemis_home_be (Port 4000) — Umbrella App**

Four child apps under `apps/`:

- **`:core`** — Business logic, Ecto schemas, contexts, validations. Owns all data models (users, rooms, devices, schedules, guest keys, PATs, configurations). No web dependencies. All other apps depend on this.
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

All schemas live in the `:core` app.

### homes
```
id              BIGSERIAL PRIMARY KEY
name            VARCHAR NOT NULL          -- "Main House", "Lake House"
ha_base_url     VARCHAR NOT NULL          -- "http://homeassistant:8123"
ha_token_enc    VARCHAR NOT NULL          -- encrypted HA long-lived access token
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

### users
```
id              BIGSERIAL PRIMARY KEY
auth0_sub       VARCHAR UNIQUE NOT NULL
email           VARCHAR NOT NULL
name            VARCHAR NOT NULL
picture         VARCHAR
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Note: no `role` column on users. Roles are per-home via `home_memberships`.

### roles
```
id              BIGSERIAL PRIMARY KEY
name            VARCHAR UNIQUE NOT NULL   -- 'admin', 'resident', 'guest'
description     VARCHAR
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Seeded on app startup with at least: `admin`, `resident`, `guest`.

### home_memberships
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
user_id         BIGINT REFERENCES users(id) NOT NULL
role_id         BIGINT REFERENCES roles(id) NOT NULL
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL

UNIQUE (home_id, user_id)
```

### invitations
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
email           VARCHAR NOT NULL
role_id         BIGINT REFERENCES roles(id) NOT NULL
token           VARCHAR UNIQUE NOT NULL   -- URL-safe invite token
invited_by_id   BIGINT REFERENCES users(id) NOT NULL
accepted_at     TIMESTAMP
expires_at      TIMESTAMP NOT NULL
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

### rooms
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
name            VARCHAR NOT NULL          -- "Main Bedroom", "Living Room"
outline         JSONB                     -- room outline for graphical view (see below)
sort_order      INTEGER NOT NULL DEFAULT 0
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Outline format (JSONB): list of line segments for rendering an SVG room shape.
```json
{
  "width": 400,
  "height": 300,
  "paths": [
    {"type": "rect", "x": 0, "y": 0, "w": 400, "h": 300},
    {"type": "line", "x1": 100, "y1": 0, "x2": 100, "y2": 50, "label": "window"}
  ]
}
```
Exact format TBD — needs UI prototyping. Could also be raw SVG path data.

### blinds
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
room_id         BIGINT REFERENCES rooms(id)  -- nullable (may not be assigned to a room yet)
name            VARCHAR NOT NULL          -- "Left Window Blind"
ha_entity_id    VARCHAR NOT NULL UNIQUE   -- "cover.living_room_left"
position_x      FLOAT                     -- x position on room outline (0.0-1.0 normalized)
position_y      FLOAT                     -- y position on room outline (0.0-1.0 normalized)
manufacturer    VARCHAR                   -- "SmartWings"
protocol        VARCHAR                   -- "zwave"
sort_order      INTEGER NOT NULL DEFAULT 0
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Future device tables follow the same pattern with type-specific columns:
- `locks` — home_id, name, ha_entity_id, supports_codes, max_codes, ...
- `lights` — home_id, name, ha_entity_id, supports_brightness, supports_rgb, ...
- `thermostats` — home_id, name, ha_entity_id, supports_heat, supports_cool, min_temp, max_temp, ...
- `garage_doors` — home_id, name, ha_entity_id, auto_close_timeout_minutes, ...

No generic `devices` table. Each type is a first-class schema. Cross-type references
(saved_configurations, schedules) use `{"type": "blind", "id": 1}` in their JSONB actions.

### user_preferences
```
id              BIGSERIAL PRIMARY KEY
user_id         BIGINT REFERENCES users(id) NOT NULL UNIQUE
default_home_id BIGINT REFERENCES homes(id)
theme           VARCHAR NOT NULL DEFAULT 'light'  -- 'light', 'dark'
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

### activity_log
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
user_id         BIGINT REFERENCES users(id)  -- nullable for system/schedule actions
device_type     VARCHAR NOT NULL          -- 'blind', 'lock', etc.
device_id       BIGINT NOT NULL           -- FK to the type-specific table
action          VARCHAR NOT NULL          -- 'open', 'close', 'unlock', 'set_position'
details         JSONB                     -- action-specific details (e.g., {"position": 50})
source          VARCHAR NOT NULL          -- 'user', 'schedule', 'mcp', 'guest'
inserted_at     TIMESTAMP NOT NULL
```

### saved_configurations
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
name            VARCHAR NOT NULL          -- "Movie Mode", "Morning Open"
actions         JSONB NOT NULL            -- list of device actions
user_id         BIGINT REFERENCES users(id) NOT NULL
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

`actions` format:
```json
[
  {"type": "blind", "id": 1, "action": "set_position", "position": 20},
  {"type": "blind", "id": 2, "action": "close"},
  {"type": "blind", "id": 5, "action": "set_position", "position": 40}
]
```

### guest_keys
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
token           VARCHAR UNIQUE NOT NULL
label           VARCHAR NOT NULL
allowed_scopes  JSONB NOT NULL           -- e.g. ["door:control"]
expires_at      TIMESTAMP
revoked_at      TIMESTAMP
created_by_id   BIGINT REFERENCES users(id)
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

### personal_access_tokens
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
token_hash      VARCHAR UNIQUE NOT NULL  -- SHA-256 hash of the token
label           VARCHAR NOT NULL
scopes          JSONB NOT NULL           -- e.g. ["devices:read", "devices:control"]
user_id         BIGINT REFERENCES users(id) NOT NULL
expires_at      TIMESTAMP
revoked_at      TIMESTAMP
last_used_at    TIMESTAMP
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

### blind_schedules
```
id              BIGSERIAL PRIMARY KEY
home_id         BIGINT REFERENCES homes(id) NOT NULL
name            VARCHAR NOT NULL
blind_ids       JSONB NOT NULL           -- [1, 2, 5] (references blinds.id)
action          VARCHAR NOT NULL          -- "open", "close", "set_position"
position        INTEGER                   -- 0-100, only for set_position
cron_expression VARCHAR NOT NULL          -- "0 7 * * *" or similar
timezone        VARCHAR NOT NULL          -- "America/Chicago"
active          BOOLEAN NOT NULL DEFAULT true
user_id         BIGINT REFERENCES users(id) NOT NULL
inserted_at     TIMESTAMP NOT NULL
updated_at      TIMESTAMP NOT NULL
```

Future device types get their own schedule tables: `light_schedules`, `thermostat_schedules`, etc.

### blind_schedule_runs
```
id              BIGSERIAL PRIMARY KEY
blind_schedule_id BIGINT REFERENCES blind_schedules(id) NOT NULL
status          VARCHAR NOT NULL          -- "success", "failure", "partial"
started_at      TIMESTAMP NOT NULL
completed_at    TIMESTAMP
error_details   TEXT
results         JSONB                     -- per-blind results
```

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
│   │       ├── tenancy/
│   │       │   ├── tenancy.ex           # Context: homes CRUD, membership, invitations
│   │       │   ├── home.ex             # Ecto schema
│   │       │   ├── home_membership.ex   # Ecto schema
│   │       │   └── invitation.ex       # Ecto schema
│   │       │
│   │       ├── auth/
│   │       │   ├── auth.ex              # Context: verify_token, create_session
│   │       │   ├── auth0_client.ex      # Auth0 code exchange, JWKS verification
│   │       │   ├── guest_key.ex         # Ecto schema
│   │       │   ├── guest_keys.ex        # Context: create, validate, revoke
│   │       │   ├── pat.ex              # Ecto schema
│   │       │   └── pats.ex             # Context: create, validate, revoke
│   │       │
│   │       ├── home/
│   │       │   ├── home_context.ex      # Context: rooms CRUD, saved configs
│   │       │   ├── room.ex             # Ecto schema
│   │       │   ├── saved_config.ex     # Ecto schema (named configurations)
│   │       │   └── ha_client.ex        # Req-based HA REST API client (generic)
│   │       │
│   │       ├── blinds/
│   │       │   ├── blinds.ex           # Context: blinds CRUD, control
│   │       │   ├── blind.ex            # Ecto schema
│   │       │   ├── blind_schedules.ex  # Context: schedule CRUD, toggle, history
│   │       │   ├── blind_schedule.ex   # Ecto schema
│   │       │   └── blind_schedule_run.ex # Ecto schema
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
│           │   ├── home_controller.ex     # Homes CRUD, membership, invitations
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

1. **FE-to-BE auth token flow**: The FE calls the BE via Req. How does the FE authenticate? Must resolve before starting. Options: BE issues a signed token after Auth0 verification, FE stores it in session, passes as Bearer header in Req calls. Or distributed Erlang eliminates this.

2. **Auth0 token handling in FE**: The FE could store the Auth0 access token and pass it to the BE on every request (stateless), or the BE could issue its own session token after verifying Auth0 (stateful). Stateful sessions (BE-issued) are simpler for LiveView since LiveView doesn't naturally carry Bearer tokens — it uses cookies.

3. **HA polling vs WebSocket for BE→HA**: v1 polls HA states via REST. HA also has a WebSocket API that pushes state_changed events. WebSocket is better for latency but adds complexity. Defer to v2.
