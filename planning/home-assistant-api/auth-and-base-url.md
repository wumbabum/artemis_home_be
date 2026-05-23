# HA REST API — auth and base URL

## Base URL

`HOME_ASSISTANT_URL` is expected to be the **full API root**, including
the `/api` suffix. So all relative paths in these examples assume
something like:

```
HOME_ASSISTANT_URL=http://homeassistant.local:8123/api
```

Sub-resources are then `${HOME_ASSISTANT_URL}/states`,
`${HOME_ASSISTANT_URL}/services`, etc. — NOT `${HOME_ASSISTANT_URL}/api/states`.

Confirmed live by hitting `${HOME_ASSISTANT_URL}/`:

```bash
curl -sS "$HOME_ASSISTANT_URL/" -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY"
```

```json
{"message":"API running."}
```

A 404 on this endpoint means the env var was set to the server root
instead of the API root (or vice versa); double-check trailing
segments before debugging deeper.

## Authentication

All requests carry a long-lived access token in the `Authorization`
header:

```
Authorization: Bearer <HOME_ASSISTANT_API_KEY>
```

The token is generated from the HA user profile at
`<HA host>/profile/security` → "Long-lived access tokens". It does
not expire on its own and must be rotated manually.

The Artemis BE will load this from `HA_TOKEN` (per-home, eventually
stored in the `homes` table with optional Cloak encryption — see
`planning/smart-blinds/plan.md` Open Decision #4).

## Header expectations

- `Authorization: Bearer <token>` — required for every call.
- `Content-Type: application/json` — required for POST bodies.
- No `Accept` header needed; HA always returns JSON.

## Response shape conventions

- All state and service responses are JSON.
- Service calls (`POST /services/<domain>/<service>`) return either an
  empty array `[]` on success or an object describing the error on
  failure.
- State endpoints (`GET /states`, `GET /states/<entity_id>`) return an
  object (single) or array of objects (list), each with `entity_id`,
  `state`, `attributes`, `last_changed`, `last_reported`,
  `last_updated`, and `context`.
- `state` is always a string. The set of valid values varies by domain
  (e.g. `open|closed|opening|closing|unavailable` for `cover`).
- `attributes` is a free-form map; required keys vary by domain.

## Error responses

- `401 Unauthorized` — missing or invalid token (no body).
- `404 Not Found` — unknown entity_id or wrong URL path (text body
  `404: Not Found`, not JSON).
- `400 Bad Request` — malformed JSON or missing required service field.

The BE should treat any non-2xx as `{:error, {:ha_status, status,
body}}` so the caller can decide what to do.
