# HA entity inventory (snapshot)

Captured live. Useful for choosing the right entity_ids when wiring
new device contexts and for spotting what's missing.

## Command

```bash
curl -sS "$HOME_ASSISTANT_URL/states" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  | jq '[.[] | {entity_id, state, device_class: .attributes.device_class}]
        | group_by(.entity_id | split(".")[0])
        | map({
            domain: .[0].entity_id | split(".")[0],
            count: length,
            entities: [.[] | .entity_id]
          })'
```

## Snapshot (counts + entity IDs)

| Domain          | Count | Notes                                                                |
|-----------------|------:|----------------------------------------------------------------------|
| `binary_sensor` |     9 | All Z-Wave-derived: occupancy, battery warnings, AC mains            |
| `button`        |     4 | Z-Wave ping + identify on the two TV right/left blind devices         |
| `climate`       |     1 | `climate.living_room_nest` (Nest thermostat, Wi-Fi)                  |
| `conversation`  |     1 | HA's built-in voice/assist                                           |
| `cover`         |     3 | All blinds; all currently `unavailable` (see `smart-blinds/`)        |
| `event`         |     1 | Backup automatic-backup event                                        |
| `fan`           |     1 | `fan.living_room_nest_fan` (paired with the Nest)                    |
| `light`         |     2 | `light.home_assistant_connect_zwa_2_led` (stick LED) + TV right LED  |
| `person`        |     1 | `person.joseph_toney`                                                |
| `sensor`        |    15 | Backup metadata, sun, node statuses, batteries                       |
| `sun`           |     1 | Sun position                                                         |
| `todo`          |     1 | HA shopping list                                                     |
| `tts`           |     1 | Google Translate TTS                                                 |
| `update`        |     6 | Firmware/integration updates                                         |
| `weather`       |     1 | `weather.forecast_home`                                              |
| `zone`          |     1 | `zone.home`                                                          |

## Cover entities (full list)

```
cover.living_room_blinds                        device_class: blind   state: unavailable
cover.living_room_tv_right_outbound_bottom      device_class: window  state: unavailable
cover.living_room_tv_left_outbound_bottom       device_class: window  state: unavailable
```

The naming difference (`blind` vs `window` device_class) confirms the
finding from `planning/function_docs/blinds/README.md`: filter by
domain `cover.*`, not by `device_class`. The two "outbound bottom"
entities are the SmartWings Z-Wave blinds (Z-Wave node entities live
under `binary_sensor`, `sensor`, `button`, and `light` with
`living_room_tv_right` / `living_room_tv_left` prefixes).

## Related Z-Wave node entities

For each SmartWings blind, HA exposes auxiliary entities tied to the
same Z-Wave node:

```
sensor.living_room_tv_right_node_status        (Z-Wave node status)
sensor.living_room_tv_right_battery_level      (battery %)
button.living_room_tv_right_ping               (Z-Wave ping)
button.living_room_tv_right_identify           (LED blink to identify)
light.living_room_tv_right                     (status LED on the device)
update.living_room_tv_right_firmware           (firmware update entity)
binary_sensor.living_room_tv_right_*           (battery warnings, AC mains state)
```

…and the mirror set for `living_room_tv_left`.

The Artemis BE does **not** need to track these node-level entities
for v0.1 — only the `cover.*` entities matter. They're documented
here so future milestones (battery low alerts, identify-on-pair UX)
have somewhere to start.
