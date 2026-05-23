# GET /states (filtered to `cover.*`)

The shape the BE's StateCache poll loop sees on every cycle.

## Command

```bash
curl -sS "$HOME_ASSISTANT_URL/states" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  | jq '[.[] | select(.entity_id | startswith("cover."))]'
```

## Response (captured live)

All three covers currently `unavailable` — see
`known-blockers.md` for the underlying reason. The shape is what
matters; treat the specific values as fixtures only.

```json
[
  {
    "entity_id": "cover.living_room_blinds",
    "state": "unavailable",
    "attributes": {
      "device_class": "blind",
      "friendly_name": "Living room blinds",
      "supported_features": 15
    },
    "last_changed": "2026-05-23T11:04:36.549713+00:00",
    "last_reported": "2026-05-23T11:04:45.716551+00:00",
    "last_updated": "2026-05-23T11:04:45.716374+00:00",
    "context": {
      "id": "01KSA84JWHTTCF0DZF36E5VMMA",
      "parent_id": null,
      "user_id": null
    }
  },
  {
    "entity_id": "cover.living_room_tv_right_outbound_bottom",
    "state": "unavailable",
    "attributes": {
      "restored": true,
      "device_class": "window",
      "friendly_name": "Outbound Bottom",
      "supported_features": 15
    },
    "last_changed": "2026-05-23T11:04:45.713959+00:00",
    "last_reported": "2026-05-23T11:04:45.713959+00:00",
    "last_updated": "2026-05-23T11:04:45.713959+00:00",
    "context": {
      "id": "01KSA84JWHTTCF0DZF36E5VMMA",
      "parent_id": null,
      "user_id": null
    }
  },
  {
    "entity_id": "cover.living_room_tv_left_outbound_bottom",
    "state": "unavailable",
    "attributes": {
      "restored": true,
      "device_class": "window",
      "friendly_name": "Outbound Bottom",
      "supported_features": 15
    },
    "last_changed": "2026-05-23T11:04:45.714270+00:00",
    "last_reported": "2026-05-23T11:04:45.714270+00:00",
    "last_updated": "2026-05-23T11:04:45.714270+00:00",
    "context": {
      "id": "01KSA84JWJPK8DAK8TAPW0RVMD",
      "parent_id": null,
      "user_id": null
    }
  }
]
```

## Observations

- `supported_features: 15` confirms each device claims OPEN (1) +
  CLOSE (2) + SET_POSITION (4) + STOP (8). No tilt.
- `current_position` is **absent** from `attributes` on every entry
  (matches the prior research note in
  `planning/function_docs/blinds/README.md`). Defensive parsing must
  treat the missing key as "no position known", not "position 0" or
  "null".
- `restored: true` appears on the two SmartWings entities (the new
  TV right/left) but not on `cover.living_room_blinds`. This flag
  indicates HA brought the state back from its on-disk snapshot
  rather than from a live radio report — a strong signal that the
  device hasn't communicated since HA last restarted.
- `device_class` varies (`blind` vs `window`) — confirms the
  domain-not-device_class filtering rule.
- Two of the three entities share the same `friendly_name`
  ("Outbound Bottom"). The Artemis `blinds.name` column will need to
  carry a user-meaningful name; we can't rely on HA's friendly name
  alone.
- The `context.id` on the first two entities is identical
  (`01KSA84JWHTTCF0DZF36E5VMMA`) — they were marked unavailable in
  the same HA restart event. Worth ignoring in test fixtures.

## What we still need to capture

When the Z-Wave radio comes back online (see `known-blockers.md`):

- A `cover.*` entry with `state: "open"|"closed"` and
  `current_position` populated as an integer 0–100.
- A `cover.*` entry with `state: "opening"|"closing"` in transition,
  showing how `current_position` reports during movement.

These are needed to finalize the StateCache diff logic and unit
tests. Until then the v0.1 BE will be coded against the unavailable
shape with a documented placeholder for the available shape.
