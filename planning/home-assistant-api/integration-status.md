# Detecting HA integration status via REST

What the BE can learn about HA's configured integrations (specifically
Z-Wave) through the same REST surface used in v0.1. Captured live so
the upcoming `GET /api/home` endpoint can surface integration
readiness to the FE without needing a WebSocket connection.

Three candidate endpoints were probed. Their trade-offs and the
recommended choice are below.

## Summary table

  | Endpoint                                           | Tells us                                          | Stability                                                | Use as primary?  |
  |----------------------------------------------------|---------------------------------------------------|----------------------------------------------------------|------------------|
  | `GET /api/config/config_entries/entry?domain=X`    | Installed? Loaded? Loaded with what error?        | Stable — same shape for any integration                  | **Yes**          |
  | `GET /api/config` → `components[]`                 | Integration is loaded                             | Stable but coarser; no error reason                      | Cross-check only |
  | `GET /api/states/sensor.<radio>_status`            | Radio is physically connected and ready           | Entity id varies per hardware (`zwa_2`, `aeotec_*`, etc.) | Health probe only |

## Endpoint 1 (recommended): config entries

```bash
curl -sS "$HOME_ASSISTANT_URL/config/config_entries/entry?domain=zwave_js" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY"
```

Response when the integration is installed and healthy:

```json
[
  {
    "created_at": 1765057662.461461,
    "disabled_by": null,
    "domain": "zwave_js",
    "entry_id": "01KBTT53FXENZ9JQM6BF8JY9MQ",
    "error_reason_translation_key": null,
    "error_reason_translation_placeholders": null,
    "modified_at": 1766423003.846377,
    "num_subentries": 0,
    "pref_disable_new_entities": false,
    "pref_disable_polling": false,
    "reason": null,
    "source": "zeroconf",
    "state": "loaded",
    "supported_subentry_types": {},
    "supports_options": false,
    "supports_reconfigure": true,
    "supports_remove_device": false,
    "supports_unload": true,
    "title": "Z-Wave JS"
  }
]
```

Response when the integration is not installed (probed with
`?domain=ring`):

```json
[]
```

HTTP status is **200 in both cases** — empty list signals "not
installed", not 404. No need for status-vs-body branching in the BE.

### Fields the BE cares about

  | Field                         | What to do with it                                                                                                  |
  |-------------------------------|---------------------------------------------------------------------------------------------------------------------|
  | `state`                       | `"loaded"` → integration is healthy. Other observed values: `"not_loaded"`, `"setup_error"`, `"setup_retry"`, `"setup_in_progress"`, `"failed_unload"`. Anything other than `"loaded"` means the FE should NOT enable the blinds button. |
  | `reason`                      | Free-form human-readable error string when `state != "loaded"` (e.g. `"Z-Wave JS Server unreachable"`). Surface verbatim to the FE for a tooltip. `null` when state is loaded. |
  | `error_reason_translation_key`| When non-null, HA has a localized message for this error. The BE can ignore this for v0.1 (no i18n) and lean on `reason`. |
  | `disabled_by`                 | Non-null means the user explicitly disabled the integration in HA's UI. Treat as "not available" from the FE's perspective. |
  | `title`                       | Human label HA picked (e.g. `"Z-Wave JS"`). Useful for the FE's "device hub: …" subtitle.                            |
  | `entry_id`                    | The config entry id — opaque ULID. Not needed for v0.1's readiness check but **is** the `entry_id` argument that downstream `zwave_js/*` WebSocket commands require for the eventual SmartStart pairing flow. Worth caching once it's fetched. |

### Mapping to the BE's `:integrations.zwave` shape

The proposed `GET /api/home` response uses `integrations.zwave =
{available, reason}`. The mapping:

```text
config entries result            -> integrations.zwave
[]                               -> { available: false, reason: "not_installed" }
[entry] where disabled_by != nil -> { available: false, reason: "disabled_in_ha" }
[entry] where state == "loaded"  -> { available: true,  reason: null }
[entry] otherwise                -> { available: false, reason: entry["reason"] || entry["state"] }
```

`source` (`zeroconf`, `user`, `usb`, etc.) is metadata about how the
integration was added; not relevant to readiness.

### Notes

- The `?domain=` query string parameter narrows the response server-
  side, which is preferable to fetching the full list and filtering
  in Elixir.
- The endpoint requires the same bearer token as the rest of the REST
  surface. No additional permissions needed.

## Endpoint 2 (cross-check only): /config components

```bash
curl -sS "$HOME_ASSISTANT_URL/config" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" | jq '.components | map(select(startswith("zwave")))'
```

Response (this install):

```json
[
  "zwave_js.cover",
  "zwave_js.event",
  "zwave_js.humidifier",
  "zwave_js.switch",
  "zwave_js.siren",
  "zwave_js.update",
  "zwave_js.lock",
  "zwave_js.sensor",
  "zwave_js",
  "zwave_js.button",
  "zwave_js.fan",
  "zwave_js.light",
  "zwave_js.select",
  "zwave_js.binary_sensor",
  "zwave_js.number",
  "zwave_js.climate"
]
```

The `components` array on `/config` lists every loaded platform —
`zwave_js` plus its per-domain platforms (`zwave_js.cover`,
`zwave_js.lock`, …). Presence of the bare `"zwave_js"` string is a
reliable "loaded" signal.

Downside: no error reason if the integration is in a non-loaded
state (it's simply absent). Useful as a sanity-check or a fallback
if the config-entries endpoint changes shape; not a substitute for
Endpoint 1.

Same call returns useful home metadata that `GET /api/home` may
want to surface — `version`, `location_name`, `time_zone`,
`country`. Worth grabbing in the same trip.

## Endpoint 3 (radio health probe, not capability check)

```bash
curl -sS "$HOME_ASSISTANT_URL/states/sensor.home_assistant_connect_zwa_2_status" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY"
```

Response:

```json
{
  "entity_id": "sensor.home_assistant_connect_zwa_2_status",
  "state": "ready",
  "attributes": { "friendly_name": "zwave controller Status" },
  "last_changed": "2026-05-24T21:31:50.935562+00:00",
  "last_reported": "2026-05-24T21:31:50.935562+00:00",
  "last_updated": "2026-05-24T21:31:50.935562+00:00"
}
```

`state == "ready"` means the radio is alive and the controller
firmware is talking to HA. Other documented values include
`"unavailable"` (the state observed when the radio went offline
earlier in the milestone — see `smart-blinds/known-blockers.md`),
`"starting"`, `"shutdown"`, etc.

**Why not use this as the primary signal?** The entity id is
hardware- and user-specific. This install has
`sensor.home_assistant_connect_zwa_2_status` because the USB stick
is an Aeotec Z-Stick numbered 2; a different user might have
`sensor.aeotec_zstick_7_status` or no such sensor at all. The BE
would need a discovery step to find the right entity, which the
config-entries endpoint avoids entirely.

This signal is still useful for a future `/api/home/health` probe
that surfaces "device available but radio is acting up" — finer-
grained than Endpoint 1.

## Recommendation for v0.1 `GET /api/home`

1. Single HA call per request:
   `GET /config/config_entries/entry?domain=zwave_js`.
2. Map the response to `integrations.zwave` per the table above.
3. Cache the result on the BE for ~5 s so a dashboard load that
   triggers multiple device-list fetches doesn't fan out N times
   to HA. Cache TTL can be invalidated proactively after a
   provision/unprovision call once the SmartStart flow lands.
4. Don't probe the radio sensor in v0.1. The integration-loaded
   signal is sufficient for the "show the blinds button green" UX
   the FE wants today.
5. Extend the same shape to other integrations as they're added —
   `integrations.zigbee`, `integrations.matter`, etc. all use the
   same config-entries query with their respective `domain=` value.

## What this unblocks downstream

- The `entry_id` in the config-entries response is the same value
  the WebSocket `zwave_js/*` commands require for the eventual
  SmartStart pairing flow. The BE can fetch it once and cache, so
  the upcoming `Core.HA.WsClient` doesn't need a duplicate
  discovery step.
- The per-platform components list (`zwave_js.cover`,
  `zwave_js.lock`, …) is a forward-looking signal for which
  device-type buttons the FE should expose at all on a given
  home. v0.1 doesn't need this — only blinds matter — but the
  `GET /api/home` response can include `integrations.zwave.platforms`
  later without a contract break.
