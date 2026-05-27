# GET /states/{entity_id} — single cover, unavailable

How the BE looks up one specific entity. Same shape as one element
of `01-list-cover-states.md`, but verified the single-resource
endpoint behaves identically.

## Command

```bash
curl -sS "$HOME_ASSISTANT_URL/states/cover.living_room_tv_right_outbound_bottom" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" | jq
```

## Response (captured live)

```json
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
}
```

## 404 on unknown entity

```bash
curl -sS -w "\n%{http_code}\n" \
  "$HOME_ASSISTANT_URL/states/cover.does_not_exist" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY"
```

Returns `404: Not Found` (plain text body, not JSON). The BE should
treat this as `{:error, :entity_not_found}` and never as a transport
failure.

## Implication for the BE

The StateCache poll loop will use the bulk `GET /states` filter
rather than per-entity lookups for efficiency. Per-entity lookup is
useful for:

- One-shot smoke tests during pause points.
- Future "force-refresh after a write" optimization (skip the next
  scheduled poll if we just wrote and got back a fresh state).
- The CLI when a user wants to inspect a single blind without
  waiting for the next poll cycle.
