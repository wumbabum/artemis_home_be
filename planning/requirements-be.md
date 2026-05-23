# Requirements: artemis_home_be

## Context

Phoenix umbrella app with four child apps:
- `:core` — business logic, Ecto schemas, contexts, HA client, JSON import
- `:dispatch` — Oban job scheduling and execution
- `:mcp` — MCP JSON-RPC protocol handler
- `:web` — Phoenix JSON API controllers, channels, plugs

Owns all business logic, device control, scheduling, auth verification, and data persistence. The frontend and future native clients consume the `:web` API. The MCP server uses `:mcp` which calls `:core` directly.

## Authentication & Authorization

### Auth0 Integration
- Verify Auth0-issued JWT/OIDC tokens on incoming requests from the frontend
- Extract user identity (sub, email, name, picture) from verified tokens
- Create or update a local user record on first login (upsert by Auth0 subject ID)
- Support Google OAuth and email/password as Auth0 connection types

### User Roles
- Three roles: `admin`, `family`, `guest`
- Admin: full access — manage devices, schedules, users, guest keys, PATs
- Family: device control, view/run schedules, view own profile
- Guest: access only the features scoped by their guest key (e.g., door only)
- Role is stored on the user record and checked on each API request

### Guest Keys
- Admin can create a guest key with: label, allowed features (list of feature scopes), expiration datetime
- Guest key is a unique opaque token (e.g., URL-safe random string)
- Guest accesses the app via URL with `?guest_key=<token>` query param
- Backend validates the key, checks expiration, and restricts access to allowed feature scopes
- Admin can list, revoke, and view usage of guest keys

### Personal Access Tokens (PATs)
- Admin can create PATs for MCP server or other API consumers
- PAT has: label, scoped permissions, created_at, last_used_at, optional expiration
- PAT is a unique opaque token, shown once on creation
- API requests with `Authorization: Bearer <PAT>` are authenticated against the PATs table
- Admin can list, revoke, and view usage of PATs

## Rooms & Devices

### Rooms
- App-managed rooms stored in Postgres (not auto-discovered from HA)
- CRUD operations for rooms
- Each room has: name, outline schematic (JSONB for SVG rendering), sort order
- Rooms are added via form or JSON import

### Devices
- App-managed devices stored in Postgres, each mapped to an HA entity_id
- CRUD operations for devices
- Each device has: name, device_type, ha_entity_id, room_id, position on room outline (x/y), device_config (JSONB)
- device_config is type-specific (e.g., blind config includes manufacturer, protocol, position range)
- Devices are added via form or JSON import
- Future device types beyond blinds will have their own device_config schemas

### Saved Configurations
- Named configurations that bundle multiple device actions (e.g., "Movie Mode")
- Each config has a list of actions: device_id + action + parameters
- CRUD operations for configurations
- Execute a configuration: run all actions against HA in sequence or parallel
- Return per-device results on execution

## Home Assistant Client

### REST Connection
- Connect to HA REST API at a configurable base URL (env var `HA_BASE_URL`)
- Authenticate with a long-lived access token (env var `HA_TOKEN`)
- Use Req (HTTP client) for all requests
- Handle HA being unreachable gracefully (return typed errors, don't crash)

### WebSocket Connection
- Connect to HA WebSocket API at `ws://<HA_BASE_URL>/api/websocket`
- Authenticate with the same long-lived access token
- Maintain a persistent WebSocket connection (GenServer in `:core`)
- Used for: device pairing (inclusion/exclusion), SmartStart provisioning, QR code parsing
- Forward streaming pairing events to the FE via Phoenix Channels

### Device Pairing
- Start Z-Wave inclusion mode via `zwave_js/add_node` WebSocket command
- Stop inclusion via `zwave_js/stop_inclusion`
- Start exclusion (remove device) via `zwave_js/remove_node`
- Stop exclusion via `zwave_js/stop_exclusion`
- SmartStart: parse QR code string via `zwave_js/parse_qr_code_string`, then provision via `zwave_js/provision_smart_start_node`
- Stream pairing events (inclusion started, node added, device registered) back to the FE in real-time
- When a device is successfully paired in HA, auto-create a corresponding device record in Artemis (or prompt the user to assign room/name)

### State Fetching
- Fetch entity states from HA for app-managed devices only
- Cache states in ETS with configurable TTL
- Poll HA periodically (5-10 seconds) and diff against cache to detect changes

### Cover Control (v1)
- Open a cover: `POST /api/services/cover/open_cover` with `entity_id`
- Close a cover: `POST /api/services/cover/close_cover` with `entity_id`
- Stop a cover: `POST /api/services/cover/stop_cover` with `entity_id`
- Set cover position: `POST /api/services/cover/set_cover_position` with `entity_id` and `position` (0-100)
- Validate device exists in app database and maps to a valid HA entity
- Validate position is an integer 0-100
- Return the updated entity state after the action completes

### Multi-Device Operations
- Accept a list of device_ids and a command (open/close/stop/set_position)
- Resolve device_ids to HA entity_ids via the devices table
- Execute against all specified entities
- Return per-device success/failure results

## JSON Import

- Accept JSON payloads for bulk import of rooms, devices, and configurations
- Validate against type-specific JSON schemas before import
- Return detailed error messages for validation failures
- Idempotent: update existing records if identifiers match, create if new
- JSON schemas serve as the canonical data format for MCP tool inputs too

## Scheduling

### Schedule Management
- Create a schedule: name, list of target entity_ids, action (open/close/set_position), position (if applicable), cron expression or time-of-day, timezone, active flag
- Update a schedule
- Delete a schedule
- List schedules (with current active/inactive status)
- Activate/deactivate a schedule (toggle the active flag)

### Schedule Execution
- Use Oban for persistent, reliable job scheduling
- When a schedule fires, execute the specified action against HA REST API
- Log each execution: schedule_id, timestamp, success/failure, error details if any
- If HA is unreachable, log the failure and optionally retry (configurable)

## API Endpoints

### Auth
- `POST /api/auth/callback` — receive Auth0 token, verify, upsert user, return session/JWT
- `POST /api/auth/logout` — invalidate session
- `GET /api/auth/me` — return current user profile and role

### Rooms
- `GET /api/rooms` — list all rooms (with device counts)
- `POST /api/rooms` — create a room
- `PUT /api/rooms/:id` — update a room
- `DELETE /api/rooms/:id` — delete a room

### Devices
- `GET /api/devices` — list all devices (with current HA state)
- `GET /api/devices/:id` — get single device with current HA state
- `POST /api/devices` — create a device (register in app)
- `PUT /api/devices/:id` — update a device
- `DELETE /api/devices/:id` — delete a device
- `POST /api/devices/:id/command` — execute a command on a single device
- `POST /api/devices/batch` — execute a command on multiple devices

### Saved Configurations
- `GET /api/configs` — list saved configurations
- `POST /api/configs` — create a configuration
- `PUT /api/configs/:id` — update a configuration
- `DELETE /api/configs/:id` — delete a configuration
- `POST /api/configs/:id/execute` — run a saved configuration

### Import
- `POST /api/import` — bulk JSON import (rooms, devices, configs)

### Schedules
- `GET /api/schedules` — list all schedules
- `POST /api/schedules` — create a schedule
- `PUT /api/schedules/:id` — update a schedule
- `DELETE /api/schedules/:id` — delete a schedule
- `POST /api/schedules/:id/toggle` — activate/deactivate
- `GET /api/schedules/:id/history` — view execution history

### Guest Keys
- `GET /api/guest-keys` — list all guest keys (admin only)
- `POST /api/guest-keys` — create a guest key (admin only)
- `DELETE /api/guest-keys/:id` — revoke a guest key (admin only)

### PATs
- `GET /api/pats` — list all PATs (admin only)
- `POST /api/pats` — create a PAT (admin only, returns token once)
- `DELETE /api/pats/:id` — revoke a PAT (admin only)

### System
- `GET /api/health` — health check (public, no auth)
- `GET /api/ha/status` — check HA connectivity (admin only)

## Device State

- BE polls HA REST API (`GET /api/states`) every 5-10 seconds via a GenServer
- Caches entity states in ETS keyed by entity_id
- Exposes `GET /api/homes/:home_id/blinds/states` endpoint that returns cached state for all blinds in a home
- Each blind's state includes: state (open/closed/opening/closing), position (0-100), available (true/false)
- FE polls this endpoint from LiveView on pages where live state matters
- Device command responses also return the updated state for immediate UI update
- No WebSocket/Channel between FE and BE — all communication is HTTP

## Data Persistence

- PostgreSQL database
- See technical design doc for full schema

## Dependencies

- The frontend depends on this API for all data and actions
- The MCP server depends on this API for device control
- This service depends on Home Assistant REST API for device operations
- This service depends on Auth0 for token verification (JWKS endpoint)
