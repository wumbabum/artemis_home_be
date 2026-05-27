# GET /states/{entity_id} — single cover, available

What HA returns for a cover entity that is fully online and reachable
through the Z-Wave radio. Companion to `02-get-state-unavailable.md`
(same endpoint, different state).

## Command

```bash
curl -sS "$HOME_ASSISTANT_URL/states/cover.living_room_tv_right_outbound_bottom" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" | jq
```

## Response (captured live)

```json
{
  "entity_id": "cover.living_room_tv_right_outbound_bottom",
  "state": "open",
  "attributes": {
    "current_position": 65,
    "device_class": "window",
    "friendly_name": "living room tv right Outbound Bottom",
    "is_closed": false,
    "supported_features": 15
  },
  "last_changed": "2026-05-24T21:35:24.910485+00:00",
  "last_reported": "2026-05-24T21:35:24.910485+00:00",
  "last_updated": "2026-05-24T21:35:24.910485+00:00",
  "context": {
    "id": "01KSDYM27E4X2FQJ1FM79H3M60",
    "parent_id": null,
    "user_id": null
  }
}
```

## Differences vs the unavailable shape

| Field                            | Unavailable                       | Available                                |
|----------------------------------|-----------------------------------|------------------------------------------|
| `state`                          | `"unavailable"`                   | `"open"` (or `"closed"`/`"opening"`/`"closing"`) |
| `attributes.current_position`    | absent                            | integer 0–100                            |
| `attributes.is_closed`           | absent                            | boolean — `true` iff `current_position == 0` |
| `attributes.restored`            | `true` (after HA restart)         | absent                                   |
| `attributes.friendly_name`       | `"Outbound Bottom"` (HA default)  | `"living room tv right Outbound Bottom"` (renamed in HA UI) |

## Implications for the StateCache

- The cache row's `state` field maps directly from `state` (string).
- The cache row's `position` field maps from `attributes.current_position`
  when present. When absent — i.e. the entity is `unavailable` — the
  cache should hold `nil` for position rather than guessing 0.
- The cache row's `available` flag is `state != "unavailable"`. Do not
  derive it from `restored: true` — `restored` only persists across the
  first poll after an HA restart.
- `is_closed` is a redundant convenience; the BE can ignore it and
  re-derive when needed.
- `last_changed` / `last_reported` / `last_updated` all carry the same
  ISO-8601 timestamp here, but HA distinguishes them: `last_changed`
  flips only when `state` itself changes, `last_updated` flips on any
  attribute change. For position-only moves (see
  `06-state-during-transition.md`) the BE should look at `last_updated`
  to detect movement, not `last_changed`.
