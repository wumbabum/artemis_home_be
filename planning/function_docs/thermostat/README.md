# Thermostat

## Status: Future — not in v1

## HA Integration (expected)
- HA domain: `climate`
- Services: `climate.set_temperature`, `climate.set_hvac_mode`, `climate.set_fan_mode`
- HVAC modes: `off`, `heat`, `cool`, `heat_cool`, `auto`, `fan_only`

### Expected Service Call
```json
{
  "entity_id": "climate.main_floor",
  "temperature": 72,
  "hvac_mode": "heat_cool"
}
```

### Expected State Shape
```json
{
  "entity_id": "climate.main_floor",
  "state": "heat_cool",
  "attributes": {
    "friendly_name": "Main Floor Thermostat",
    "current_temperature": 70,
    "temperature": 72,
    "target_temp_high": 74,
    "target_temp_low": 68,
    "hvac_action": "heating",
    "fan_mode": "auto",
    "supported_features": 31
  }
}
```

## Artemis Features (planned)
- Temperature display on dashboard (current temp + target)
- Set target temperature
- Switch HVAC mode (heat/cool/auto/off)
- Fan mode control
- Schedules: temperature schedules by time of day
- History: temperature trends over time

## Device Config Schema (JSONB, planned)
```json
{
  "manufacturer": "TBD",
  "protocol": "zwave or wifi",
  "supports_heat": true,
  "supports_cool": true,
  "supports_fan": true,
  "min_temp": 50,
  "max_temp": 90,
  "temp_unit": "fahrenheit"
}
```

## Open Questions
- Which thermostat (Ecobee, Honeywell, Z-Wave native)
- Whether HA integration is via Z-Wave, WiFi, or manufacturer cloud API
- Multi-zone support (multiple thermostats or zone control)
