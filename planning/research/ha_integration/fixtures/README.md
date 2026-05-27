# HA Integration Fixtures

Captured artifacts from a live HA + zwave-js-ui pair, used as ground
truth for `:core/ha/client` and `:core/ha/zwjs_admin` tests on the
BE side, and to inform MCP tool schemas in `:mcp`.

These are BE-only concerns. The FE never consumes HA's raw shapes —
the BE mediates everything via `:web`'s JSON API, and FE tests mock
the BE surface (not HA's). If the FE later wants response fixtures,
they would be a separate set derived from the BE's REST output, not
these HA captures.

The architectural decision docs that motivate this directory live in
the FE planning corpus (cross-cutting v1 architecture):

- `../../../../artemis_home_fe/planning/research/ha_integration/README.md`
  — HA-primary decision with rationale.
- `../../../../artemis_home_fe/planning/research/ha_integration/zwjs_admin_escape.md`
  — when the BE talks to zwave-js-ui directly.

## Layout

```
fixtures/
├── README.md                       this file
├── 01-ha-config.json               GET /api/config
├── 02-cover-entities.json          /api/states filtered to cover.*
├── 03-services-cover.json          /api/services entry for the cover domain
├── 04-services-zwave_js.json       /api/services entry for the zwave_js domain
├── 05-zwjs-state-snapshot.json     zwave-js-server `start_listening` snapshot
└── 06-config-entries.json          HA config_entries list (for zwave_js entry_id)
```

Files are JSON; format with `jq .` before commit so diffs are readable.

## Capture commands

Run from a shell with these env vars set (do not commit the token):

```bash
export HA_BASE_URL="http://antares.local:8123"
export HA_TOKEN="<HA long-lived access token>"
export ZWJS_WS="ws://antares.local:8991"
```

```bash
curl -s "$HA_BASE_URL/api/config" -H "Authorization: Bearer $HA_TOKEN" \
  | jq . > 01-ha-config.json

curl -s "$HA_BASE_URL/api/states" -H "Authorization: Bearer $HA_TOKEN" \
  | jq '[.[] | select(.entity_id | startswith("cover."))]' \
  > 02-cover-entities.json

curl -s "$HA_BASE_URL/api/services" -H "Authorization: Bearer $HA_TOKEN" \
  | jq '.[] | select(.domain == "cover")' > 03-services-cover.json

curl -s "$HA_BASE_URL/api/services" -H "Authorization: Bearer $HA_TOKEN" \
  | jq '.[] | select(.domain == "zwave_js")' > 04-services-zwave_js.json

# Direct zwave-js-server snapshot (one-shot send + close):
echo '{"messageId":"1","command":"start_listening"}' \
  | websocat -1 "$ZWJS_WS" | jq . > 05-zwjs-state-snapshot.json

# HA config entries (needed to discover the zwave_js entry_id used by
# zwave_js/* WS commands):
websocat "$HA_BASE_URL/api/websocket" <<EOF | jq . > 06-config-entries.json
{"type":"auth","access_token":"$HA_TOKEN"}
{"id":1,"type":"config_entries/get"}
EOF
```

## What each file is for

- **01-ha-config.json** — HA version, components installed, timezone,
  unit system. Pins the BE's HA version assumption in tests.
- **02-cover-entities.json** — every `cover.*` entity the user has,
  with `attributes` (friendly_name, supported_features bitmask,
  current_position, device_class). Drives the blind table seed and
  the HA-client decoder.
- **03-services-cover.json** — exact field schema for
  `open_cover`, `close_cover`, `stop_cover`, `set_cover_position`,
  `set_cover_tilt_position`. Drives `Core.HA.Client` request shapes
  and MCP tool definitions.
- **04-services-zwave_js.json** — pairing/inclusion service schemas
  (`add_node`, `parse_qr_code_string`, etc.). Drives the v1 pairing
  flow's BE side.
- **05-zwjs-state-snapshot.json** — the full Z-Wave network state from
  zwave-js-server. Useful for v1 design discussions and for verifying
  what the admin escape hatch (`Core.HA.ZwjsAdmin`) exposes.
- **06-config-entries.json** — yields the `entry_id` value that the
  HA WS API requires for every `zwave_js/*` command.

## Redaction before commit

Strip before committing:

- `HA_TOKEN` (never appears in capture output, but double-check).
- `friendly_name` if any reveal sensitive info (e.g., kid's name).
- IP addresses in `01-ha-config.json` and `06-config-entries.json`
  (`internal_url`, `external_url`).
- Z-Wave network keys in `05-zwjs-state-snapshot.json` (look for
  `securityKeys.*`, `S0_Legacy`, `S2_*`). These are 32-hex-char
  strings; if present in the snapshot, replace with `<REDACTED>`.

A `jq` one-liner to redact security keys:

```bash
jq 'walk(if type == "object" and has("securityKeys") then .securityKeys = "<REDACTED>" else . end)' \
   05-zwjs-state-snapshot.json
```

## Refresh cadence

Re-capture when:

- HA is upgraded to a new minor version.
- zwave-js-ui or zwave-js-server is upgraded to a new major.
- A new physical device is added to the Z-Wave network.

The captured fixtures are reference data, not unit-test ground truth
that gets compared byte-for-byte. Tests should match on the *shape* of
responses, not specific entity IDs or node counts.
