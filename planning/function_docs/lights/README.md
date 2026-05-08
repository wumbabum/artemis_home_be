# Lights

## Status: Future — not in v1

## HA Integration (expected)
- HA domain: `light`
- Services: `light.turn_on`, `light.turn_off`, `light.toggle`
- Supports attributes: `brightness` (0-255), `color_temp`, `rgb_color`, `effect`

### Expected Service Call
```json
{
  "entity_id": "light.living_room",
  "brightness": 200,
  "color_temp": 350
}
```

### Expected State Shape
```json
{
  "entity_id": "light.living_room",
  "state": "on",
  "attributes": {
    "friendly_name": "Living Room Light",
    "brightness": 200,
    "color_temp": 350,
    "supported_features": 63
  }
}
```

## Artemis Features (planned)
- Lights tab on dashboard
- On/off toggle per light
- Brightness slider
- Color temperature control (if supported)
- RGB color picker (if supported)
- Scenes: save light states as named presets
- Schedules: time-based automation

## Device Config Schema (JSONB, planned)
```json
{
  "manufacturer": "TBD",
  "protocol": "zwave or zigbee or wifi",
  "supports_brightness": true,
  "supports_color_temp": true,
  "supports_rgb": false,
  "min_brightness": 0,
  "max_brightness": 255
}
```

## Open Questions
- Which protocol (Z-Wave, Zigbee, WiFi) — depends on bulbs/switches purchased
- Whether to integrate with existing smart switches or replace with Z-Wave
- Group control: by room, by zone, by floor
