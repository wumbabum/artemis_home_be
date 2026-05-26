# GET /services — cover domain schema

The schema HA publishes for every service the `cover` domain supports.
Independent of device availability — works even when every cover
entity is `unavailable`.

## Command

```bash
curl -sS "$HOME_ASSISTANT_URL/services" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  | jq '.[] | select(.domain == "cover")'
```

## Response (captured live)

```json
{
  "domain": "cover",
  "services": {
    "open_cover": {
      "fields": {},
      "target": {
        "entity": [{ "domain": ["cover"], "supported_features": [1] }]
      }
    },
    "close_cover": {
      "fields": {},
      "target": {
        "entity": [{ "domain": ["cover"], "supported_features": [2] }]
      }
    },
    "set_cover_position": {
      "fields": {
        "position": {
          "required": true,
          "selector": {
            "number": {
              "min": 0.0,
              "max": 100.0,
              "unit_of_measurement": "%",
              "step": 1.0,
              "mode": "slider"
            }
          }
        }
      },
      "target": {
        "entity": [{ "domain": ["cover"], "supported_features": [4] }]
      }
    },
    "stop_cover": {
      "fields": {},
      "target": {
        "entity": [{ "domain": ["cover"], "supported_features": [8] }]
      }
    },
    "toggle": {
      "fields": {},
      "target": {
        "entity": [{ "domain": ["cover"], "supported_features": [3] }]
      }
    },
    "open_cover_tilt":       { "fields": {}, "target": {"entity":[{"domain":["cover"],"supported_features":[16]}]} },
    "close_cover_tilt":      { "fields": {}, "target": {"entity":[{"domain":["cover"],"supported_features":[32]}]} },
    "stop_cover_tilt":       { "fields": {}, "target": {"entity":[{"domain":["cover"],"supported_features":[64]}]} },
    "set_cover_tilt_position": {
      "fields": {
        "tilt_position": {
          "required": true,
          "selector": {
            "number": { "min": 0.0, "max": 100.0, "unit_of_measurement": "%", "step": 1.0, "mode": "slider" }
          }
        }
      },
      "target": {"entity":[{"domain":["cover"],"supported_features":[128]}]}
    },
    "toggle_cover_tilt":     { "fields": {}, "target": {"entity":[{"domain":["cover"],"supported_features":[48]}]} }
  }
}
```

## What v0.1 actually uses

Of the 11 services, v0.1 wires four:

| Service              | Required `supported_features` bit | Body |
|----------------------|-----------------------------------|------|
| `open_cover`         | 1                                  | `{entity_id}`                    |
| `close_cover`        | 2                                  | `{entity_id}`                    |
| `set_cover_position` | 4                                  | `{entity_id, position: 0..100}`  |
| `stop_cover`         | 8                                  | `{entity_id}`                    |

The SmartWings blinds advertise `supported_features: 15` (=
1+2+4+8), so all four are supported.

Tilt services (`*_tilt`) are not used; SmartWings doesn't support
tilt.

`toggle` is not used; the FE is the source of truth on intended
state and will issue explicit open/close based on the current
cached state.

## Service-call request format

All four follow the same shape — POST to
`/services/cover/<service>` with a JSON body containing the
`entity_id` (and `position` for `set_cover_position`):

```bash
# Example: set position to 50%
curl -sS -X POST \
  "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom", "position": 50}'
```

Response body shapes are captured in:

- `05-set-position-response.md` — success body (`[]` for
  `set_cover_position`, full state list for `open_cover` /
  `close_cover`).
- `07-service-call-errors.md` — every observed error and
  edge-case response (HTTP 400 plain-text for schema violations,
  HTTP 200 `[]` for nonexistent / wrong-domain targets, accepted
  float positions).
