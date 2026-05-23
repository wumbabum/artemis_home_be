# Requirements: artemis_home_fe

## Context

Phoenix LiveView frontend app named "Artemis". Consumes the `artemis_home_be` JSON API. Provides the web UI for all user interactions. Installable as a PWA on phones and tablets.

## Authentication

### Login Flow
- Login page with "Sign in with Google" and "Sign in with Email" buttons
- Buttons redirect to Auth0's Universal Login page
- Auth0 redirects back to the frontend with an authorization code
- Frontend exchanges the code with the backend (`POST /api/auth/callback`)
- Backend returns a session token; frontend stores it (cookie or session)
- Subsequent API calls include the session token

### Guest Flow
- Guest arrives via URL with `?guest_key=<token>`
- Frontend sends the key to the backend for validation
- If valid, frontend renders a limited UI scoped to the guest key's allowed features
- No login required for guests

### Session Management
- Persist session across page reloads
- Show logged-in user's name and avatar in the nav/header
- Logout button clears session and redirects to home

## Pages & Views

### Home / Dashboard
- Shows a summary of all controllable devices grouped by room or type
- v1: shows all 11 blinds with current position/state
- Each device card shows: friendly name, current state (open/closed/position %), quick action buttons
- Real-time state updates via Phoenix Channel subscription to the backend

### Device Control — Blinds
- Tap a blind card to expand it into a detail view or modal
- Controls: Open, Close, Stop buttons
- Position slider (0-100) with smooth drag interaction
- Visual indicator of current position (e.g., a blind illustration that moves)
- Batch operations: "Open All", "Close All" buttons
- Group selection: select multiple blinds, then apply a command to all selected

### Schedules
- List all schedules with: name, target devices, action, time, active/inactive toggle
- Create new schedule: pick devices, pick action, set time, set name
- Edit existing schedule
- Delete schedule (with confirmation)
- Toggle active/inactive with a smooth switch animation
- Show execution history for a schedule (last N runs with success/failure)

### Admin — User Management
- List all users with role
- Change user roles (admin only)
- Not in v1 scope: invite users

### Admin — Guest Keys
- List all guest keys with: label, allowed features, expiration, created date
- Create new guest key: set label, select feature scopes, set expiration
- Copy shareable link button
- Revoke (delete) a guest key

### Admin — PAT Management
- List all PATs with: label, permissions, created date, last used
- Create new PAT: set label, select permission scopes
- Show the token value once on creation (with copy button, warning it won't be shown again)
- Revoke (delete) a PAT

### Settings — Device Pairing
- "Add Device" button in device settings
- Two options: SmartStart (QR code) or Classic Inclusion
- SmartStart flow:
  - Open phone camera via JS QR scanning library
  - Scan QR code from device packaging
  - Display parsed device info (manufacturer, product, security classes)
  - Fallback: paste QR code string manually
  - Submit to backend, which provisions via HA WebSocket API
- Classic inclusion flow:
  - Button to start inclusion mode
  - Live status updates ("Waiting for device...", "Device found", "Interviewing...")
  - Button to cancel inclusion
- On successful pairing: prompt user to assign name, room, and position on room outline
- Show pairing progress and errors in real-time via Channel subscription

### Profile
- Show current user's name, email, avatar
- Show role
- Logout button

## UI/UX

### Animations
- Modal open/close: fade + scale transition (LiveView JS.show/JS.hide with transition classes)
- Device card expand: smooth height transition
- Button press: subtle scale-down + release effect via CSS active state
- Toggle switches: smooth slide animation
- Position slider: smooth drag with debounced API call on release
- List item add/remove: fade in/out transitions
- Page transitions: fade between views

### Responsive Design
- Mobile-first layout (phone is the primary device)
- Works well on iPad (wall-mounted tablet use case)
- Desktop layout for larger screens
- Touch-friendly tap targets (minimum 44x44px)

### PWA
- `manifest.json` with app name "Artemis", theme color, icons
- Service worker for offline splash screen and asset caching
- Full-screen standalone display mode (no browser chrome)
- Home screen installable on iOS and Android

## Device State Polling

- On pages with live device state (blinds dashboard, room views), LiveView runs a poll loop via `Process.send_after`
- Polls `GET /api/homes/:home_id/blinds/states` every 5-10 seconds
- Updates assigns with new state, UI re-renders automatically
- Device command responses also return updated state for immediate feedback
- No WebSocket/Channel connection to the BE — all communication is synchronous HTTP
- Polling only runs on pages that need it (not on settings, profile, etc.)

## Dependencies

- Depends entirely on `artemis_home_be` API for data and actions
- No direct database access
- No direct HA communication
