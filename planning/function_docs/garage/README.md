# Garage

## Status: Future — not in v1

## HA Integration (expected)
- HA domain: `cover` (same as blinds, but with device_class `garage`)
- Services: `cover.open_cover`, `cover.close_cover`, `cover.stop_cover`, `cover.toggle`
- No position control typically — garage doors are binary (open/closed)

### Expected Service Call
```json
{
  "entity_id": "cover.garage_door"
}
```

### Expected State Shape
```json
{
  "entity_id": "cover.garage_door",
  "state": "closed",
  "attributes": {
    "friendly_name": "Garage Door",
    "device_class": "garage",
    "supported_features": 3
  }
}
```

## Artemis Features (planned)
- Garage tab on dashboard
- Open/close toggle with large button (easy phone access)
- Current state indicator (open/closed/opening/closing)
- Auto-close schedule (e.g., "close garage if open after 10pm")
- Activity log: when was it opened/closed
- Notifications: alert if garage left open for >N minutes

## Device Config Schema (JSONB, planned)
```json
{
  "manufacturer": "TBD",
  "protocol": "zwave or myq or ratgdo",
  "supports_position": false,
  "auto_close_timeout_minutes": 30
}
```

## Open Questions
- Which garage door controller (Z-Wave relay, MyQ, RATGDO for older openers)
- Whether to use a tilt sensor or contact sensor for open/closed detection
- Safety: confirmation dialog before opening remotely?
