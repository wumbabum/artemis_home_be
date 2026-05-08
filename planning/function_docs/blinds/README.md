# Blinds

## Status: v1 — Primary device type

## Hardware
- 11 SmartWings Z-Wave smart blinds
- Controlled via Z-Wave USB stick → Z-Wave JS UI → Home Assistant
- No tilt support — open, close, and set position (0-100%) only

## HA Integration
- HA domain: `cover`
- Device class: `blind`
- Entity IDs follow pattern: `cover.<friendly_name>`

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

### State Shape
```json
{
  "entity_id": "cover.living_room_left",
  "state": "open",
  "attributes": {
    "friendly_name": "Living Room Left",
    "device_class": "blind",
    "current_position": 75,
    "supported_features": 15
  }
}
```

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
  "ha_entity_id": "cover.living_room_left",
  "state": "open",
  "position": 75,
  "available": true
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

## Open Questions
- Exact SmartWings Z-Wave pairing process — needs testing when hardware arrives
- Whether SmartWings reports `current_position` in state attributes (most Z-Wave covers do)
