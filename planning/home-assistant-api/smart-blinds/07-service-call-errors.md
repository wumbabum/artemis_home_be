# POST /services/cover/set_cover_position — error and edge-case shapes

Closes the gap flagged in `05-set-position-response.md` §"Error
shapes (not yet captured)" and the obsolete-by-now uncertainty
note in `03-cover-services-schema.md`. Captured live against the
SmartWings setup with the Z-Wave radio online.

## Summary table

  | Scenario                                  | HTTP status | Body                  | BE error code   |
  |-------------------------------------------|-------------|-----------------------|-----------------|
  | Nonexistent cover entity                  | 200         | `[]`                  | (silent no-op)  |
  | Wrong-domain entity (e.g. `light.*`)      | 200         | `[]`                  | (silent no-op)  |
  | `position` out of range (e.g. 200, -10)   | 400         | `400: Bad Request`    | `ha_status`     |
  | `position` non-numeric (e.g. `"abc"`)     | 400         | `400: Bad Request`    | `ha_status`     |
  | `position` missing entirely               | 400         | `400: Bad Request`    | `ha_status`     |
  | `position` non-integer numeric (e.g. 50.5)| 200         | `[]` (motor moved)    | (success)       |

Every scenario was reproduced via direct `curl` / `Req.post` against
the live HA instance. All bodies are reproduced verbatim. The
`400: Bad Request` body is a **plain-text string**, not JSON — the
BE must not assume an `{"error": ...}` envelope on HA 4xx.

## Scenario A — nonexistent cover entity

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.does_not_exist", "position": 50}'
```

Response:

```
HTTP/1.1 200 OK
Content-Type: application/json

[]
```

HA returns success with an empty array even though no entity
matched. The BE has **no way** to distinguish "service call
succeeded against a real entity" from "service call hit no
entities at all". The cover service is filtered by target schema
on HA's side; entities that don't match the schema are silently
excluded.

**BE implication:** the existing pre-write `Repo.get(Blind,
blind_id)` check in `Core.Blinds.set_position/2` is the only
guard against acting on a stale or wrong id. There's nothing HA
will tell us after-the-fact.

**FE implication:** a successful write does NOT confirm the blind
actually moved. Pair every write with a poll-until-position-changes
window (the FE already does this).

## Scenario B — wrong-domain entity

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.living_room_tv_right", "position": 50}'
```

Response:

```
HTTP/1.1 200 OK
Content-Type: application/json

[]
```

Same shape as Scenario A. HA filters non-matching entities by the
service's target schema (`cover.set_cover_position` targets
`domain: ["cover"], supported_features: [4]`), so a `light.*`
entity is silently dropped. No error to the caller.

Same BE / FE implications as A.

## Scenario C — `position` out of range

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom", "position": 200}'
```

Response:

```
HTTP/1.1 400 Bad Request
Content-Type: text/plain

400: Bad Request
```

The body is **literal plain text**: the 17 bytes `"400: Bad Request"`,
not a JSON object. HA's Voluptuous schema validator rejects the
request before it reaches the cover integration.

Negative positions (`-10`) and any other out-of-range numeric
value produce the same response. The boundary is `[0.0, 100.0]`
inclusive (per `03-cover-services-schema.md`).

## Scenario D — `position` non-numeric

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom", "position": "abc"}'
```

Response: identical to Scenario C — `400 Bad Request` plain text.

## Scenario E — `position` missing

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom"}'
```

Response: identical to Scenario C — `400 Bad Request` plain text.

The `position` field is declared `required: true` in HA's service
schema.

## Scenario F — `position` non-integer numeric (50.5)

```bash
curl -sS -X POST "$HOME_ASSISTANT_URL/services/cover/set_cover_position" \
  -H "Authorization: Bearer $HOME_ASSISTANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "cover.living_room_tv_right_outbound_bottom", "position": 50.5}'
```

Response:

```
HTTP/1.1 200 OK
Content-Type: application/json

[]
```

**The blind physically moved** in response to this call. HA
accepts a float, rounds (or truncates — Z-Wave reports back 51 in
practice), and dispatches the move. The service schema declares
`step: 1.0` but does not enforce integer-typed inputs.

**BE implication:** `Core.Blinds.set_position/2` rejects floats
via the `is_integer/1` guard, so this scenario is unreachable
through the BE's HTTP surface. The integer guard remains worth
keeping — it makes the API contract explicit and matches the FE's
slider integer-step UI.

## Scenario G — unavailable cover entity (substitute)

A genuinely-unavailable cover entity was not present in HA's
state at capture time. The closest substitutes:

  | Available substitute              | Response                         |
  |-----------------------------------|----------------------------------|
  | Nonexistent entity (Scenario A)   | `200 []` — silent no-op          |
  | Wrong-domain entity (Scenario B)  | `200 []` — silent no-op          |

Both suggest that an unavailable cover entity would also produce
`200 []`: HA filters the target list by the service schema; if
the entity is excluded (or just inert), the service call returns
empty without an error.

To verify this for an actually-unavailable cover, power-cycle one
of the SmartWings blinds (battery removal) until
`sensor.living_room_tv_<side>_node_status` reports `unavailable`,
then re-run Scenario A with the real entity id. Update this file
with the actual response if it differs.

## BE error-mapping for these scenarios

`Core.HA.RestClient.HttpFetcher.request/3` already maps these
correctly:

  | HA response          | `Req` result                                  | BE error code      |
  |----------------------|-----------------------------------------------|--------------------|
  | 200 with `[]`        | `{:ok, %{status: 200, body: []}}`             | `:ok` (success)    |
  | 400 plain-text body  | `{:ok, %{status: 400, body: "400: Bad ..."}}` | `{:ha_status, 400, body}` |

Status-based dispatch lands the plain-text body inside the
`{:ha_status, status, body}` tuple. The `BlindsController`
collapses that to `503 {"error": "ha_status"}` for the FE. No
parser-level brittleness on the BE side.

## Test fixtures derived from this capture

For `Core.HA.RestClient.HttpFetcher` tests (if/when those land
post-v0.1, currently coverage-skipped):

  - 200 with empty `[]` for both no-op-success and nonexistent-entity
  - 400 with body `"400: Bad Request"` for any schema-violating input

For `Core.Blinds.set_position/2` tests: the existing tests
exercise the integer + range guard before HA is touched, so HA
responses don't change those fixtures.
