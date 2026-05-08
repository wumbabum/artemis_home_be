# Technical Notes

## Resolved Decisions

- Q: Should we build a custom app or use Home Assistant's dashboard directly?
  A: Build a custom app. HA dashboards don't work well with AI-assisted editing, and we want custom auth, scheduling UX, and MCP server control. HA stays as a device control backend.

- Q: What language/framework for the backend?
  A: Elixir / Phoenix (JSON API, no LiveView on the backend). Chosen for OTP scheduling, concurrency, and existing developer experience.

- Q: What language/framework for the frontend?
  A: Elixir / Phoenix LiveView. Chosen for fast development speed, real-time UI via WebSocket, and one-language stack. The backend exposes a JSON API so the frontend can be swapped for React or a native app later.

- Q: Should backend and frontend be one app or separate?
  A: Separate apps. The API backend is isolated so future native mobile clients (Swift, Kotlin) can consume it without changes. Two Docker containers, one docker-compose.

- Q: App names?
  A: Backend: `artemis_home_be`. Frontend: `artemis_home_fe` (app name "Artemis"). MCP server: `artemis_mcp`.

- Q: Mobile strategy?
  A: PWA for v1. The LiveView frontend installs as a home screen app with no browser chrome. Native Swift app is a future possibility — the isolated API backend supports this.

- Q: Auth provider?
  A: Auth0 for identity only (Google OAuth + email/password). Auth0 handles OIDC authentication — who is this person. All authorization (which home, what role, what permissions) is managed in Artemis's database via `homes` and `home_memberships` tables. No Auth0 Organizations or groups needed. Free tier compatible.

- Q: User tiers?
  A: Three roles per home: admin (full control + user/home management), resident (device control, schedules), guest (temporary access via shareable link, limited to specific features). Roles are stored in `home_memberships`, not in Auth0. A user can be admin of one home and resident of another.

- Q: Guest access model?
  A: Shareable URL with a guest key as a query parameter. Guest keys are admin-created, primarily for door access (unlock front door for a guest/delivery). Keys expire after a set time or manual revocation. Guest key management is part of the Doors feature, not home management settings.

- Q: Scheduling?
  A: App-owned schedules stored in Postgres. Backend executes them against HA REST API at scheduled times. Users can activate/deactivate schedules. Oban for persistent job queues.

- Q: MCP server?
  A: Built as a separate component (`artemis_mcp`) that calls the backend API. Authenticated via Personal Access Tokens (PATs). PATs are exclusively for MCP server authentication — they are not used for human user access. PAT management table accessible to admins only.

- Q: How does the app talk to Home Assistant?
  A: HA REST API over the local Docker network (both on Synology NAS). Auth via long-lived HA access token stored as env var. No tunnel needed for this leg since both containers are on the same host.

- Q: Deployment target?
  A: Synology NAS via Docker Compose. All services (Phoenix BE, Phoenix FE, Postgres, HA, Z-Wave JS) run on the NAS.

- Q: Public access?
  A: Cloudflare Tunnel or Tailscale Funnel from NAS to the internet. Gives a public hostname for the frontend. HA itself is never exposed publicly.

- Q: Device types for v1?
  A: Blinds only (11 SmartWings Z-Wave covers). Other devices (lights, thermostat, garage, door, cameras) added incrementally in later versions.

- Q: Cameras?
  A: Deferred. No live streaming in v1. Will revisit later.

- Q: Animation/UI quality?
  A: Smooth animations required — expanding boxes, button press effects, modal open/close transitions. Achieved via Tailwind CSS transitions + LiveView JS commands + JS hooks where needed.

- Q: Push notifications?
  A: Desired. Web Push works reliably on Android PWA. iOS PWA push is limited (requires add-to-home-screen, iOS 16.4+). May add a thin native Swift wrapper later for reliable iOS push.

- Q: Cloudflare Tunnel vs Tailscale Funnel?
  A: Tailscale Funnel for now. Simpler setup since Tailscale is already planned for private services (Plex, SSH, NAS admin). Funnel exposes the app publicly via a `*.ts.net` hostname with automatic HTTPS. No DDoS protection or WAF — acceptable for a personal app with low traffic. Can upgrade to Cloudflare Tunnel later if needed.

- Q: Should the MCP server be a separate Elixir app, a sidecar in Python/Node, or just additional endpoints in the BE app?
  A: Inside the BE. The BE will be an umbrella app with four child apps: `:core` (business logic, schemas, contexts), `:dispatch` (Oban job scheduling/execution), `:mcp` (MCP JSON-RPC protocol handling), and `:web` (Phoenix API controllers, channels, plugs).

- Q: Should the app support tilt control for blinds, or just position?
  A: No tilt. SmartWings blinds support open, close, and set position (0-100%). No tilt control.

- Q: How should rooms and devices be managed?
  A: App-managed, not auto-discovered. Rooms and blinds are added manually via a settings page (form or JSON import). Each room has a name and an outline schematic (coordinates for a graphical room map). Each blind belongs to a room and has device-specific setup info. Future device types will have their own schema.

- Q: How should the dashboard navigation work for blinds?
  A: Room-first navigation. Dashboard shows a button per room plus an "All" button. Tapping a room enters a detail view with two switchable sub-views: (1) Outline view — graphical room outline with blind controls positioned where the blinds physically are, (2) List view — table of blinds with name and current state.

- Q: Should saved blind configurations be supported?
  A: Yes. Users can save named configurations (e.g., "Movie Mode" = bedroom blinds at 20%, living room closed). Configurations can be loaded and executed.

- Q: JSON ingestion?
  A: The app should support JSON-based bulk import for rooms, devices, and configurations. JSON schemas are type-specific (room schema includes outline coordinates, blind schema includes HA entity_id and device-specific setup). This also serves as the data model for MCP tool inputs.

- Q: Multi-home / multi-tenant?
  A: Yes. The app supports multiple homes. A `homes` table stores each home with its name and HA connection info. A `home_memberships` table maps users to homes with per-home roles (admin, resident, guest). All data (rooms, devices, schedules, configs, guest keys, PATs) is scoped to a home via `home_id` foreign key. Users can belong to multiple homes. Admins of a home can invite users by email — the invitee receives a link, signs in via Auth0, and is added to the home with the specified role.

- Q: Home-scoped HA connections?
  A: Each home has its own HA connection (base URL + token). This means the app could theoretically manage devices across multiple HA instances (e.g., a vacation home with its own HA). For v1, one home with one HA is the expected setup, but the data model supports multiple.

- Q: Schedules table design?
  A: Type-specific schedule tables. `blind_schedules` instead of a generic `schedules` table. Each device type gets its own schedule table. This eliminates the ambiguous `device_ids` JSONB problem.

- Q: Dynamic scheduling with Oban?
  A: GenServer-based evaluator. A GenServer runs periodically (every minute), queries due schedules from the DB, and enqueues Oban workers for execution. No Oban cron plugin needed.

- Q: Multi-home HA connections?
  A: The backend runs on the NAS and can only talk to one HA instance without significant extra work. The `homes` table still stores `ha_base_url` and `ha_token_enc` for the data model, but v1 assumes one backend → one HA. Multi-HA support is a future consideration. Need more info about HA connection topology before finalizing.

- Q: Home context in API requests?
  A: URL param. All home-scoped routes are nested: `/api/homes/:home_id/blinds`, `/api/homes/:home_id/rooms`, etc. The authorize plug extracts `home_id` from the URL and verifies the user's membership/role for that home.

- Q: First-user bootstrap?
  A: Seed a superuser from env vars in the Dockerfile. No UI for initial user creation — use an API endpoint for user management. The seed script reads `ADMIN_EMAIL` and `ADMIN_AUTH0_SUB` from env vars and creates the admin user + first home on startup. Dockerfile will be needed for Synology Container Manager deployment.

- Q: FE-to-BE authentication mechanism?
  A: Must resolve before starting implementation. Open question — needs design work on how the FE stores and forwards BE-issued tokens in Req calls, or whether distributed Erlang eliminates this need.

- Q: Invitation delivery?
  A: Email or SMS. Swoosh for email + an SMS provider (Twilio or similar) for text. Provider selection deferred.

- Q: HA token encryption?
  A: Needs more research after understanding HA connection patterns better. Likely `cloak_ecto` for at-rest field encryption.

- Q: Umbrella scaffolding?
  A: Covered by existing Phoenix umbrella scaffolding rule. Child apps named without parent prefix (`:core`, `:web`, `:dispatch`, `:mcp` — not `:artemis_core`, etc.).

## Unresolved

- Q: FE-to-BE authentication — exact token flow. Must resolve before starting.

- Q: Whether distributed Erlang (BEAM-native messaging) should replace HTTP for FE↔BE communication. Would simplify auth and real-time significantly.

- Q: What is the exact Synology Docker networking setup? Will containers use `synobridge`, host networking, or a custom Docker network?

- Q: Domain name for the public-facing app? Custom domain vs *.ts.net?

- Q: How should schedule timezone handling work? User's local timezone? HA's configured timezone?

- Q: Room outline format — what coordinate system? SVG path data? List of (x,y) line segments? Needs research on what's practical for the UI to render.

- Q: SmartWings Z-Wave blind setup details — what device-specific configuration does HA need? Need to research Z-Wave JS + SmartWings integration specifics.

- Q: QR code scanning library for the FE — which JS library for camera-based QR scanning in LiveView? Candidates: `html5-qrcode`, `jsQR`, or `zxing-js`. Needs evaluation.

- Q: HA token encryption approach — `cloak_ecto` likely, but needs confirmation after more HA connection research.

- Q: Email/SMS provider for invitations — SendGrid, Postmark, SES for email; Twilio for SMS. Pick later.

## HA WebSocket API Reference (for device pairing)

Device inclusion/exclusion and SmartStart provisioning are **only available via HA's WebSocket API**, not REST.

### Connection
- WebSocket endpoint: `ws://<HA_HOST>:8123/api/websocket`
- Auth: send `{"type": "auth", "access_token": "<HA_TOKEN>"}` after connection
- Messages use JSON with `id` (integer) and `type` fields

### Pairing Commands
- `zwave_js/add_node` — starts inclusion mode (requires `entry_id`, optional `secure`)
- `zwave_js/stop_inclusion` — cancels inclusion
- `zwave_js/remove_node` — starts exclusion mode
- `zwave_js/stop_exclusion` — cancels exclusion
- `zwave_js/provision_smart_start_node` — pre-provisions a SmartStart device (accepts QR provisioning info or planned provisioning entry)
- `zwave_js/unprovision_smart_start_node` — removes a pre-provisioned device
- `zwave_js/get_provisioning_entries` — lists all provisioned entries
- `zwave_js/parse_qr_code_string` — parses a QR code string into provisioning information
- `zwave_js/supports_feature` — checks if controller supports SmartStart

### Streaming Events During Inclusion
After calling `add_node`, HA sends events on the same WebSocket:
- `inclusion started`
- `inclusion failed`
- `inclusion stopped`
- `node added` — includes node_id, status, ready
- `device registered` — includes device name and HA device id

### QR Code String Format
- Minimum 52 characters
- Contains DSK, security classes, manufacturer/product IDs, firmware version
- Can be parsed via `parse_qr_code_string` before provisioning

## HA REST API Reference (for BE implementation)

### Endpoints Used

- `GET /api/` — health check
- `GET /api/states` — all entity states
- `GET /api/states/{entity_id}` — single entity state
- `POST /api/services/{domain}/{service}` — call a service

### Cover Services

- `cover.open_cover` — fully open
- `cover.close_cover` — fully close
- `cover.stop_cover` — stop movement
- `cover.toggle` — toggle open/close
- `cover.set_cover_position` — set position (0=closed, 100=fully open)
- `cover.set_cover_tilt_position` — set tilt (0=closed, 100=fully open)

### Service Call Format

```
POST /api/services/cover/set_cover_position
Authorization: Bearer <HA_TOKEN>
Content-Type: application/json

{
  "entity_id": "cover.living_room_blinds",
  "position": 50
}
```

### Cover Entity State Shape

```json
{
  "entity_id": "cover.living_room_blinds",
  "state": "open",
  "attributes": {
    "friendly_name": "Living Room Blinds",
    "device_class": "blind",
    "current_position": 75,
    "supported_features": 15
  },
  "last_changed": "2026-05-07T22:15:00+00:00",
  "last_updated": "2026-05-07T22:15:00+00:00"
}
```

### Authentication

All requests require `Authorization: Bearer <LONG_LIVED_ACCESS_TOKEN>` header.
Token is generated from HA user profile at `http://<HA_HOST>:8123/profile`.
Stored as `HA_TOKEN` environment variable in the backend container.
