# Get Context: Artemis Home

## What This Is

Artemis is a home automation web application (Phoenix backend + Phoenix LiveView frontend) that controls smart home devices through Home Assistant. Planning docs live in this directory. No code has been written yet.

## How to Get Started

### 1. Read the planning docs in this order

All files are relative to `artemis_home_be/planning/`.

1. `technical-notes.md` — Start here. Every design decision and its rationale. Also contains HA REST and WebSocket API references.
2. `technical-design.md` — Architecture diagram, data models (all 15 tables), module structures for BE and FE, auth flows, navigation flow, docker-compose.
3. `requirements-be.md` — What the backend must do.
4. `requirements-fe.md` — What the frontend must do.
5. `estimate.md` — Milestones and sequencing.
6. `development-pipeline.md` — Commit strategy, quality gates, validation steps.

### 2. Read device-specific docs as needed

`function_docs/` has a folder per device type. Each contains HA API details, planned features, and device config schemas.

- `function_docs/blinds/` — v1, primary device type
- `function_docs/doors/` — future, includes guest key access model
- `function_docs/lights/` — future
- `function_docs/thermostat/` — future
- `function_docs/garage/` — future
- `function_docs/cameras/` — future, deferred

### 3. Read the Go app context (prior art)

The original design work was done for a Go version of this app. Some context is still useful.

`home_assist_ex/temp/go_app_context/` contains:
- `context.md` — original project context and smart home setup
- `requirements.md` — original functional requirements
- `technical_notes.md` — Synology Docker notes, Z-Wave USB device mapping

### 4. Read project rules

The project has an `AGENTS.md` at `artemis_home_be/../home_assist_ex/AGENTS.md` with Phoenix 1.8, LiveView, Ecto, and HEEx conventions. These apply to both BE and FE development.

## Repository Locations

- Backend: `/Users/joseph.toney/Work/sandbox/artemis_home_be` (umbrella, not yet scaffolded)
- Frontend: `/Users/joseph.toney/Work/sandbox/artemis_home_fe` (standalone, not yet scaffolded)
- Prior Elixir app (Auth0 demo): `/Users/joseph.toney/Work/sandbox/home_assist_ex`

## External References

### Home Assistant API
- REST API docs: https://www.home-assistant.io/developers/rest_api/
- WebSocket API docs: https://www.home-assistant.io/developers/websocket_api/
- Cover integration (blinds): https://www.home-assistant.io/integrations/cover/
- Z-Wave JS integration: https://www.home-assistant.io/integrations/zwave_js/
- Z-Wave device pairing: https://www.home-assistant.io/integrations/zwave_js/#adding-a-new-device-to-the-z-wave-network
- Local HA instance: running on Synology NAS at port 8123

### Home Assistant GitHub
- Use the `github` MCP server to browse https://github.com/home-assistant repos if needed

### Auth0
- Auth0 docs: https://auth0.com/docs
- Used for identity only (Google OAuth + email/password). All authorization is app-managed.

## MCP Servers Available

- `github` — browse GitHub repos (home-assistant/core, etc.)
- `browsermcp` — navigate and read web pages (HA docs, etc.)
- `atlassian` — Jira/Confluence (not relevant to this project)
- `rag-mcp-aws-payments` — not relevant to this project
- `coralogix-oauth-server` — not relevant to this project

Always ask the user before making MCP requests.

## Key Decisions to Be Aware Of

- BE is a Phoenix umbrella with 4 apps: `:core`, `:dispatch`, `:mcp`, `:web`
- FE is a standalone Phoenix LiveView app (no database, calls BE API)
- No generic `devices` table — each device type gets its own table (`blinds`, `locks`, etc.)
- Multi-tenant via `homes` table — all data scoped by `home_id`
- Auth0 is identity-only — roles and permissions managed in DB via `home_memberships`
- PATs are exclusively for MCP server auth
- Guest keys belong to the Doors feature, not home management
- Tailscale Funnel for public access (upgradeable to Cloudflare Tunnel later)
- HA device pairing requires WebSocket API, not REST
- FE↔BE communication is purely HTTP (Req) — no WebSocket/Channel between them
- Device state freshness via polling (FE polls BE, BE polls HA), not push
- Synchronous HTTP for all mutations and CRUD
