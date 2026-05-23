# Known blockers — Z-Wave radio offline

At the time of capture, every Z-Wave-derived entity reports
`state: "unavailable"` with `restored: true` (where applicable).

## Evidence

The Z-Wave stick itself reports unavailable:

```json
{
  "entity_id": "sensor.home_assistant_connect_zwa_2_status",
  "state": "unavailable",
  "attributes": {
    "restored": true,
    "friendly_name": "Status",
    "supported_features": 0
  },
  "last_changed": "2026-05-23T11:04:45.713801+00:00",
  ...
}
```

Both SmartWings blind nodes show the same:

- `sensor.living_room_tv_right_node_status` — `unavailable`, `restored: true`
- `sensor.living_room_tv_right_battery_level` — `unavailable`, `restored: true`
- `sensor.living_room_tv_left_node_status` — `unavailable`, `restored: true`
- `sensor.living_room_tv_left_battery_level` — `unavailable`, `restored: true`

`restored: true` is HA's signal that it brought the entity back from
its database snapshot rather than from a live radio report. The
integration has had no live data since HA's last restart.

## Likely causes (in order of likelihood)

1. **Z-Wave JS UI container isn't running.** The Z-Wave JS UI add-on
   (or the standalone container, if it's running separately) mediates
   between HA's Z-Wave JS integration and the USB stick. If it's down,
   the HA integration shows everything as unavailable. Check on the
   Synology: `docker ps | grep zwave`.
2. **USB stick is disconnected or unmounted.** The Z-Wave stick mounts
   as `/dev/serial/by-id/...`. If the Synology container lost its
   device passthrough (e.g. after a host reboot), the stick is invisible
   to Z-Wave JS UI even if the container is running.
3. **Z-Wave JS integration in HA needs reload.** Sometimes after a
   network blip or container restart, HA's Z-Wave JS integration
   doesn't reconnect automatically. Settings → Devices & Services
   → Z-Wave → ⋮ → Reload.
4. **HA itself just restarted recently** and the radio hasn't completed
   its initial node interview yet. Less likely — `restored: true`
   suggests HA has been up long enough to expect the radio to have
   reported in by now.

## Recovery steps

In order of effort:

1. Reload the Z-Wave JS integration in HA's UI.
2. SSH to the Synology and `docker restart zwave-js-ui` (or whatever
   the container name is locally).
3. Reseat the USB stick.
4. Restart Home Assistant.

After recovery, the following entities should flip from `unavailable`
to a real state (battery percent, ready/dead/alive, open/closed/etc.):

```
sensor.home_assistant_connect_zwa_2_status     -> "ready"
sensor.living_room_tv_right_node_status        -> "alive"
sensor.living_room_tv_right_battery_level      -> "<percent>"
cover.living_room_tv_right_outbound_bottom     -> "open"|"closed"|"opening"|"closing"
(and the mirror set for *_left)
```

## Impact on v0.1 planning

The implementation plan can be drafted entirely on what's already
known — the schemas, the state shape (unavailable is the only one
that needs special handling), and the services schema are all
captured. The BE can be built and unit-tested without working Z-Wave.

What **does** require Z-Wave back online:

- Capturing `state: open` / `state: closed` / `state: opening` /
  `state: closing` shapes with populated `current_position`. These
  are needed to finalize the StateCache diff logic and to write the
  ExUnit fixtures for non-unavailable scenarios.
- The B-α and B-β smoke pauses (raw HA REST call against a real
  device, then full FE-shaped JSON response).
- The eventual end-to-end test (curl through the BE moves a real
  blind).

Recommendation: get Z-Wave back online before starting commit B-α (the
HA client smoke test). All commits before B-α are safe to land without
working hardware.

## After recovery — captures to fill in

When Z-Wave is back:

- `04-get-state-available.md` — `GET /states/cover.<entity>` with
  populated `current_position`.
- `05-set-position-response.md` — the response body shape from
  `POST /services/cover/set_cover_position`.
- `06-state-during-transition.md` — repeated `GET /states/<entity>`
  immediately after a set_position to capture `opening`/`closing`
  states and intermediate `current_position` values.
