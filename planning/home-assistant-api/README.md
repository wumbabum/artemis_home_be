# Home Assistant API — research

Captured req/response examples and notes for talking to the local Home
Assistant instance from the Artemis BE.

Organized by device type. Generic HA-wide notes (auth, base URL,
inventory format) live in this folder; device-specific captures go in
the corresponding subfolder.

## Files

- `auth-and-base-url.md` — how the BE authenticates against HA and the
  URL conventions assumed throughout these examples.
- `entity-inventory.md` — snapshot of every entity HA currently knows
  about, grouped by domain. Useful for picking the right entity_ids
  when wiring new device contexts.

## Subfolders

- `smart-blinds/` — `cover.*` entity captures (state shapes, services
  schema, request/response examples).

Add new subfolders here when new device types come online
(`thermostat/`, `lights/`, etc.).

## Capture conventions

Each captured request/response is a markdown file containing:

1. A one-line summary of what the example demonstrates.
2. The `curl` invocation (with env vars, never raw secrets).
3. The literal response body (typically JSON), formatted via `jq`.
4. Commentary on anything non-obvious in the response.

Examples were captured against a live HA instance. Timestamps reflect
the moment of capture and should not be treated as canonical for the
test fixtures.
