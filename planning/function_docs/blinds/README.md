# Blinds

## Status: v1 — Primary device type

## Hardware
- 11 SmartWings Z-Wave smart blinds
- Controlled via Z-Wave USB stick → Z-Wave JS UI → Home Assistant
- No tilt support — open, close, and set position (0-100%) only

## HA Integration
- HA domain: `cover`
- Device class: varies — `blind` or `window` depending on how the device registers
- Entity IDs follow pattern: `cover.<friendly_name>`
- Filter by domain (`cover.*`), NOT by device_class
- `supported_features: 15` = OPEN (1) + CLOSE (2) + SET_POSITION (4) + STOP (8)

### HA REST API — Cover Services
- `POST /api/services/cover/open_cover` — fully open
- `POST /api/services/cover/close_cover` — fully close
- `POST /api/services/cover/stop_cover` — stop movement
- `POST /api/services/cover/set_cover_position` — set position (0=closed, 100=open)

### Service Call Body
```json
{
  "entity_id": "cover.living_room_left",
  "position": 50
}
```

### State Shape (from live HA instance)

When available:
```json
{
  "entity_id": "cover.living_room_blinds",
  "state": "open",
  "attributes": {
    "friendly_name": "Living room blinds",
    "device_class": "blind",
    "current_position": 75,
    "supported_features": 15
  },
  "last_changed": "2026-05-07T11:04:49.812217+00:00",
  "last_reported": "2026-05-07T11:04:59.136059+00:00",
  "last_updated": "2026-05-07T11:04:59.135911+00:00",
  "context": {
    "id": "01KR11SFZY9JPDQW21M6SV05MS",
    "parent_id": null,
    "user_id": null
  }
}
```

When unavailable (device offline / Z-Wave stick not connected):
```json
{
  "entity_id": "cover.living_room_blinds",
  "state": "unavailable",
  "attributes": {
    "device_class": "blind",
    "friendly_name": "Living room blinds",
    "supported_features": 15
  }
}
```

Note: `current_position` is **absent** when the device is unavailable, not null. Code must handle missing key.

## Artemis Features
- Dashboard: room-first navigation with outline and list views
- Controls: open, close, stop, position slider (0-100)
- Batch operations: "Open All", "Close All", multi-select
- Saved configurations: named presets (e.g., "Movie Mode")
- Schedules: time-based automation (e.g., "open at 7am")

## Device Config Schema (JSONB)
```json
{
  "manufacturer": "SmartWings",
  "protocol": "zwave",
  "supports_position": true,
  "supports_tilt": false,
  "min_position": 0,
  "max_position": 100
}
```

## Poll State Shape

The FE polls `GET /api/homes/:home_id/blinds/states` every 5-10 seconds. Response per blind:

```json
{
  "id": 3,
  "ha_entity_id": "cover.living_room_blinds",
  "state": "open",
  "position": 75,
  "available": true
}
```

When device is unavailable:
```json
{
  "id": 3,
  "ha_entity_id": "cover.living_room_blinds",
  "state": "unavailable",
  "position": null,
  "available": false
}
```

Possible `state` values (from HA):
- `open` — fully or partially open, not moving
- `closed` — fully closed, not moving
- `opening` — currently moving toward open
- `closing` — currently moving toward closed

FE rendering:
- `opening` / `closing` → show animation/spinner on the blind card
- `open` / `closed` → static state indicator
- `position: 40` → slider at 40%, label shows "40% open"
- `available: false` → dim card, disable controls, show "Offline"

## Live HA Instance Findings

Tested against live HA instance. 3 cover entities exist (all currently unavailable):
- `cover.living_room_blinds` — device_class: `blind`
- `cover.living_room_tv_right_outbound_bottom` — device_class: `window`
- `cover.living_room_tv_left_outbound_bottom` — device_class: `window`

Key findings:
- `current_position` attribute is **absent** (not null) when device is unavailable
- `device_class` varies (`blind` vs `window`) — cannot rely on it for filtering
- HA includes 3 timestamps: `last_changed`, `last_updated`, `last_reported`
- `context.user_id` is populated when a user triggers an action — useful for activity log
- `supported_features: 15` confirmed on all covers (open + close + set_position + stop)
- Two blinds have the same friendly_name "Outbound Bottom" — Artemis's user-defined name will override

Other devices already in HA: 1 climate (thermostat), 2 lights, 1 fan. Not relevant for v1.

## Open Questions
- Exact SmartWings Z-Wave pairing process — needs testing when Z-Wave stick is connected
- What `current_position` looks like when device is available — confirm it's an integer 0-100
