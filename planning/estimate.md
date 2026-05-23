# Estimate: Artemis Home

## Milestones

### Milestone 1: Scaffold & Local HA Setup
**~1 weekend**

Set up the foundation for both apps and confirm HA API access works.

- Generate `artemis_home_be` Phoenix app with `--no-html --no-assets --no-live-view --database postgres`
- Generate `artemis_home_fe` Phoenix app with `--no-ecto`
- Add `.tool-versions` to both
- Create initial `docker-compose.yml` with Postgres, HA, Z-Wave JS containers
- Write Dockerfiles for both Phoenix apps
- Confirm HA is reachable from the BE container (`GET /api/`)
- Create BE database migrations for `users` table
- Wire up basic health endpoint (`GET /api/health`)
- Confirm FE can call BE (`GET /api/health`) via Req

**How:** Mostly generator commands and config wiring. The HA/Z-Wave containers are already running on the NAS — this milestone integrates them into the docker-compose and verifies connectivity.

### Milestone 2: HA Client & Device API
**~1 weekend**

Build the HA integration layer and expose devices via the BE API.

- Implement `ha_client.ex` using Req — `list_states/0`, `get_state/1`, `call_service/3`
- Implement `device_cache.ex` (ETS or GenServer) with TTL-based state caching
- Define `Device` struct (entity_id, friendly_name, domain, state, attributes, position)
- Filter to `cover` domain entities
- Implement `DeviceController` — `GET /api/devices`, `GET /api/devices/:entity_id`
- Implement `POST /api/devices/:entity_id/command` (open, close, stop, set_position)
- Implement `POST /api/devices/batch` for multi-device commands
- Input validation (valid entity_id, position 0-100)
- Error handling for HA unreachable / entity not found

**How:** Req calls to HA REST API. Map HA JSON responses into `Device` structs. ETS cache keyed by entity_id with a 10-second TTL. Controllers are thin — validate input, call device context, return JSON.

### Milestone 3: Auth0 Integration
**~1 week**

Full login flow for both BE and FE.

- Add `jose` and `req` deps to BE for JWKS/JWT verification
- Implement `auth0_client.ex` — code exchange, ID token verification via JWKS
- Implement user upsert (by auth0_sub) in accounts context
- Implement session creation (BE issues a signed session token / cookie)
- Create auth plugs: `Authenticate` (verify session), `Authorize` (check role)
- Protect device and schedule API endpoints behind auth
- FE: Build login page with Auth0 redirect buttons
- FE: Handle `/callback` route — exchange code with BE, store session
- FE: Show logged-in user in nav bar, logout flow
- Configure Auth0 tenant: create application, add Google connection, set callback URLs
- First user auto-assigned `admin` role

**How:** Auth0 Universal Login handles the OAuth complexity. The FE redirects to Auth0, Auth0 redirects back with a code, the FE sends the code to the BE, the BE exchanges it for tokens and verifies the ID token against Auth0's JWKS endpoint. The BE creates a session cookie that the FE stores.

### Milestone 4: Frontend — Dashboard & Blind Control
**~1-2 weeks**

Build the core UI for viewing and controlling blinds.

- FE: `ApiClient` module (Req wrapper for all BE API calls, attaches session cookie)
- FE: `DashboardLive` — grid of blind cards with current state/position
- FE: Blind card component — friendly name, state indicator, quick action buttons (Open/Close)
- FE: Blind detail modal — full controls (Open, Close, Stop, position slider)
- FE: Position slider JS hook (`position_slider.js`) — drag interaction, debounced API call on release
- FE: "Open All" / "Close All" batch action buttons
- FE: Multi-select mode — tap to select multiple blinds, then apply command
- CSS transitions: modal open/close fade+scale, card expand, button press feedback
- Responsive layout: mobile-first grid, tablet/desktop breakpoints
- Tailwind styling: clean, modern card design with status colors

**How:** LiveView renders the dashboard. Each blind is a card component. The position slider is a JS hook that sends `phx-hook` events to the LiveView, which calls the BE API. Batch operations call `POST /api/devices/batch`. All styling via Tailwind utility classes + CSS transition properties.

### Milestone 5: Device State Polling
**~2-3 days**

Keep device state reasonably fresh in the UI.

- BE: Implement state poller GenServer — polls HA `GET /api/states` every 5-10 seconds
- BE: Diff polled state against ETS cache, update changed entries
- BE: Expose `GET /api/homes/:home_id/blinds/states` endpoint returning cached state per blind (state, position, available)
- BE: Device command responses include updated state in the response body
- FE: LiveView `handle_info(:poll_states)` loop via `Process.send_after` on pages with live state
- FE: Poll BE states endpoint, update assigns, UI re-renders
- FE: Render transitional states (`opening`, `closing`) with animation/spinner
- FE: Render `available: false` as dimmed/disabled card with "Offline" label

**How:** No WebSocket or Channel between FE and BE. The BE GenServer polls HA and caches in ETS. The FE LiveView polls the BE states endpoint via Req on a timer. Device commands return updated state immediately for instant feedback; the poll loop catches changes from other sources (other users, schedules, HA automations). Simpler architecture than Channels — can add real-time push later if needed.

### Milestone 6: Schedules
**~1 week**

Schedule-based blind automation.

- BE: Add Oban dependency, configure Oban in `application.ex`
- BE: Create `schedules` and `schedule_runs` migrations
- BE: `Schedule` and `ScheduleRun` Ecto schemas
- BE: `Schedules` context — CRUD, toggle active/inactive, list history
- BE: `ScheduleWorker` (Oban worker) — loads schedule, executes action against HA
- BE: Oban cron plugin to enqueue schedule workers at the right times
- BE: `ScheduleController` — full CRUD + toggle + history endpoints
- BE: Log each run in `schedule_runs` with status and error details
- FE: `SchedulesLive` — list schedules, toggle active/inactive with switch animation
- FE: `ScheduleFormLive` — create/edit form (pick devices, action, time, name)
- FE: Schedule history view (last N runs with status)

**How:** Oban's cron plugin evaluates cron expressions and enqueues `ScheduleWorker` jobs. The worker loads the schedule from the DB, calls the device context to execute the action, and records the result in `schedule_runs`. The FE schedule form uses `to_form/2` for validation and submits to the BE API.

### Milestone 7: Device Pairing via HA WebSocket
**~1 week**

Allow adding/removing Z-Wave devices from within Artemis.

- BE: Implement HA WebSocket client GenServer in `:core` — persistent connection, auth, message routing
- BE: Implement pairing context — start/stop inclusion, start/stop exclusion, parse QR code, provision SmartStart
- BE: Forward pairing events to FE via Phoenix Channel (new `"pairing:lobby"` topic)
- BE: API endpoints — `POST /api/pairing/start-inclusion`, `POST /api/pairing/stop`, `POST /api/pairing/parse-qr`, `POST /api/pairing/provision-smartstart`
- BE: On successful device addition in HA, auto-create device record in Artemis DB (or return info for user to complete)
- FE: Pairing page in settings with two flows (SmartStart QR + Classic Inclusion)
- FE: JS hook for camera-based QR code scanning (using `html5-qrcode` or similar)
- FE: Fallback text input for QR code string
- FE: Real-time pairing status via Channel subscription (progress, success, error states)
- FE: On success, form to assign device name, room, and position

**How:** The BE maintains a WebSocket connection to HA alongside the existing REST client. A GenServer manages the connection lifecycle and routes incoming HA events. When the user starts pairing from the FE, the BE sends `zwave_js/add_node` over WebSocket and streams the resulting events back through a Phoenix Channel. For SmartStart, the FE scans a QR code via JS, sends the string to the BE, which calls `parse_qr_code_string` then `provision_smart_start_node`. The camera QR scanning uses a JS hook with `phx-hook` and `phx-update="ignore"` since it manages its own DOM.

### Milestone 8: Guest Keys & PATs
**~3-4 days**

Admin features for access control.

- BE: Create `guest_keys` and `personal_access_tokens` migrations
- BE: Schemas and contexts for both
- BE: Guest key validation plug — check token, expiry, scopes
- BE: PAT validation in the `Authenticate` plug — hash incoming token, lookup
- BE: `GuestKeyController` and `PatController` (admin-only CRUD endpoints)
- FE: `GuestKeysLive` — list, create (with scope picker and expiry), copy link, revoke
- FE: `PatsLive` — list, create (with scope picker), show-once token display, revoke
- FE: Guest landing flow — validate key via BE, render scoped UI

**How:** Guest keys are opaque random tokens stored in plaintext (they're short-lived and revocable). PATs are stored as SHA-256 hashes. On each API request, the `Authenticate` plug checks for a session cookie first, then falls back to `Authorization: Bearer` header for PAT auth. Guest keys are validated via a dedicated plug that restricts `conn.assigns` to the allowed scopes.

### Milestone 9: PWA & Polish
**~3-4 days**

Make the app installable and polished.

- Create `manifest.json` with app name, icons, theme color, display: standalone
- Create minimal service worker for offline splash and asset caching
- Generate PWA icons at required sizes (192x192, 512x512, etc.)
- Add `<link rel="manifest">` to root layout
- Test install-to-home-screen on iOS Safari and Android Chrome
- Refine animations: review all transitions, ensure 60fps
- Loading states: skeleton screens or spinners while API calls resolve
- Error states: friendly error messages for HA unreachable, auth failures
- Empty states: "No schedules yet" with CTA button
- Mobile UX pass: verify touch targets, scroll behavior, viewport handling

**How:** PWA manifest and service worker go in `assets/static/`. The service worker uses a cache-first strategy for static assets and network-first for API calls. Icon generation can be done with any PWA icon generator tool. The polish pass is manual QA on actual devices.

### Milestone 10: Deployment & Tunnel
**~1-2 days**

Get the full stack running on the NAS with public access.

- Finalize docker-compose for Synology (volume paths, network config, restart policies)
- Set up Tailscale Funnel: add `tailscale` container to docker-compose, configure serve.json to route HTTPS to `artemis_fe:4001`
- Generate Tailscale auth key, enable Funnel on the node
- Set up `.env` file on NAS with all secrets (Auth0, HA token, secret key bases, TS auth key)
- Update Auth0 callback URLs to use the `*.ts.net` hostname
- Test full flow: public URL → login → dashboard → control blinds → logout
- Test guest key flow from an external network

**How:** Tailscale runs as a Docker container alongside everything else. Funnel exposes the FE's port publicly via a `*.ts.net` hostname with automatic HTTPS. The FE proxies API calls to the BE internally. No ports need to be opened on the NAS firewall. Can upgrade to Cloudflare Tunnel later for DDoS protection/WAF if needed.

### Milestone 11 (Future): MCP Server
**~3-4 days**

Add AI/voice control capability.

- Define MCP tool schemas: `list_devices`, `control_device`, `get_device_state`, `list_schedules`, `toggle_schedule`
- Implement MCP JSON-RPC endpoint in the BE (or as a separate thin app)
- PAT authentication for MCP requests
- Test with an MCP client (e.g., Claude, or the OpenClaw voice assistant)
- Document tool schemas for MCP client configuration

**How:** MCP is just JSON-RPC. Either add a `/mcp` route to the BE that handles `tools/list` and `tools/call` JSON-RPC methods, or build a thin `artemis_mcp` Elixir app that translates MCP protocol into BE API calls. PAT auth means the MCP client just sends `Authorization: Bearer <PAT>` with each request.

## Summary

| Milestone | Effort |
|-----------|--------|
| 1. Scaffold & Local HA | ~1 weekend |
| 2. HA Client & Device API | ~1 weekend |
| 3. Auth0 Integration | ~1 week |
| 4. Dashboard & Blind Control UI | ~1-2 weeks |
| 5. Real-Time Updates | ~3-4 days |
| 6. Schedules | ~1 week |
| 7. Device Pairing via HA WebSocket | ~1 week |
| 8. Guest Keys & PATs | ~3-4 days |
| 9. PWA & Polish | ~3-4 days |
| 10. Deployment & Tunnel | ~1-2 days |
| 11. MCP Server (future) | ~3-4 days |

**Total to working v1 (milestones 1-10): ~7-9 weeks of evenings/weekends**

Milestones 1-2 get you a working API that can control blinds. Milestone 3 adds auth. Milestone 4 gives you a UI. At that point (~3 weeks in) you have a usable app. Milestones 5-10 add real-time updates, scheduling, device pairing, access control, and public deployment.

## Risks

- **HA API latency**: If HA is slow to respond (e.g., Z-Wave network congestion), blind control will feel sluggish. Mitigate with optimistic UI updates — show the expected state immediately, reconcile when HA confirms.
- **Z-Wave pairing**: The 11 blinds need to be paired with the Z-Wave stick. This is a manual hardware process outside the app's control and could be time-consuming.
- **Auth0 free tier limits**: Auth0's free tier supports 25,000 MAU and 2 social connections. Sufficient for a home app, but worth verifying before investing in the integration.
- **LiveView ↔ BE Channel**: Connecting a LiveView process to an external Phoenix Channel (on a different app) is non-trivial. The FE will need a GenServer or process that manages the Channel connection and forwards messages to the LiveView. This is the most architecturally novel part of the system.
