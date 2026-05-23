# Doors

## Status: Future — not in v1

## Concept
Door locks and access control. This is also where guest key functionality lives — guests receive a shareable link that grants them temporary door access through the app.

## Guest Keys
- Admin creates a guest key scoped to door access
- Guest receives a URL with `?guest_key=<token>`
- Guest can open the door from the app without creating an account
- Keys have expiration and can be revoked
- Guest key table is scoped to a home (`home_id`)

## HA Integration (expected)
- HA domain: `lock`
- Services: `lock.lock`, `lock.unlock`, `lock.open`
- State: `locked`, `unlocked`, `locking`, `unlocking`

### Expected State Shape
```json
{
  "entity_id": "lock.front_door",
  "state": "locked",
  "attributes": {
    "friendly_name": "Front Door",
    "device_class": "lock"
  }
}
```

## Artemis Features (planned)
- Doors tab on dashboard showing lock status
- Lock/unlock buttons
- Guest key management lives here (not in home management)
- Activity log: who unlocked when
- Temporary access codes (if the lock supports them via Z-Wave)

## Device Config Schema (JSONB, planned)
```json
{
  "manufacturer": "TBD",
  "protocol": "zwave",
  "supports_codes": true,
  "max_codes": 30
}
```

## Open Questions
- Which smart lock to purchase
- Whether to use Z-Wave lock codes or app-level access control
- How to handle "lock jammed" states
- Whether to support doorbell/camera integration alongside the lock
