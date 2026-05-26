# POST /services/cover/set_cover_position — response shape

Captured against the live SmartWings Z-Wave blind on
`cover.living_room_tv_right_outbound_bottom`. The blind physically
moved on every successful call.

## Command

```bash
curl -sS -X POST \
  "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom", "position": 50}'
```

## Response — set_cover_position

```json
[]
```

HTTP 200 with an **empty JSON array** body. HA's documented behaviour
is to return the affected states only when `?return_response=true` is
appended to the URL; without that query parameter, position-only moves
return `[]` even on success.

## Contrast: open_cover (no query param, same default)

For comparison, `POST /services/cover/open_cover` against the same
entity **does** return the affected entity states inline:

```json
[
  {
    "entity_id": "cover.living_room_tv_right_outbound_bottom",
    "state": "opening",
    "attributes": {
      "current_position": 51,
      "device_class": "window",
      "friendly_name": "living room tv right Outbound Bottom",
      "is_closed": false,
      "supported_features": 15
    },
    "last_changed": "2026-05-24T21:41:23.406146+00:00",
    "last_reported": "2026-05-24T21:41:23.406146+00:00",
    "last_updated": "2026-05-24T21:41:23.406146+00:00",
    "context": {
      "id": "01KSDYYZ1YJN6RSYP90FZ468A3",
      "parent_id": null,
      "user_id": "c23b443e891441aeb35d1780713a4192"
    }
  },
  {
    "entity_id": "cover.living_room_blinds",
    "state": "opening",
    "attributes": {
      "current_position": 58,
      "device_class": "blind",
      "entity_id": [
        "cover.living_room_tv_left_outbound_bottom",
        "cover.living_room_tv_right_outbound_bottom"
      ],
      "friendly_name": "Living room blinds",
      "is_closed": false,
      "supported_features": 15
    },
    "last_changed": "2026-05-24T21:41:23.406681+00:00",
    "last_reported": "2026-05-24T21:41:23.406681+00:00",
    "last_updated": "2026-05-24T21:41:23.406681+00:00",
    "context": {
      "id": "01KSDYYZ1YJN6RSYP90FZ468A3",
      "parent_id": null,
      "user_id": "c23b443e891441aeb35d1780713a4192"
    }
  }
]
```

Notes:

- The targeted entity AND any **cover group** containing it (here
  `cover.living_room_blinds`, which wraps the two TV-window blinds)
  appear in the response — HA reports state changes for every affected
  entity, not just the targeted one.
- `state` flips to `"opening"` **only because the service was
  `open_cover`**. A `set_cover_position` request that increases the
  position will *not* flip `state` to `"opening"`; `state` stays
  `"open"` and only `current_position` (and `last_updated`) move. See
  `06-state-during-transition.md`.

## Implications for the BE

- The BE must treat the `set_cover_position` response body as
  semantically empty. Success = HTTP 2xx; the body carries no
  information about the new state. The StateCache must re-poll
  (adaptive cadence — short interval after a write) to learn the
  achieved position.
- For `open_cover` / `close_cover` / `stop_cover`, the response body
  contains a list of state objects. The BE *could* opportunistically
  prime the cache from this list to shave one poll round-trip, but
  v0.1 keeps it simple and ignores the body (always re-polls). The
  optimization is a v0.2 candidate.
- The Z-Wave round-trip from "service accepted" to "HA reflects the
  new position" is **6–10 seconds** on this network with these
  blinds. The 1-second adaptive cadence after a write is therefore
  optimistic; the BE should plan for 2–3 poll cycles before the new
  position appears, and the FE UI should show a pending/in-flight
  indicator during that window.
- Z-Wave reports back what the motor *actually achieved*, not what
  was requested. Requesting `position: 50` settled at `current_position: 51`
  in this capture; requesting `position: 65` settled at exactly 65 the
  next move. The BE must not compare the requested position to the
  achieved one as a success/failure signal.

## Error shapes

The error and edge-case response shapes that were originally deferred
from this file are now captured in their own document:

- Out-of-range / non-numeric / missing `position` —
  `07-service-call-errors.md` §Scenarios C–E. All produce **HTTP 400**
  with a **plain-text** body `"400: Bad Request"` (not JSON).
- Nonexistent or wrong-domain `entity_id` —
  `07-service-call-errors.md` §Scenarios A–B. Both produce **HTTP 200**
  with body `[]`; HA silently drops non-matching targets.
- Float `position` (e.g. 50.5) — `07-service-call-errors.md`
  §Scenario F. HA accepts and the motor moves; v0.1's BE rejects this
  at the integer guard before reaching HA.
- Service call against an unavailable cover entity —
  `07-service-call-errors.md` §Scenario G discusses substitutes; a
  true unavailable-cover capture still requires power-cycling a
  SmartWings blind and is deferred.
