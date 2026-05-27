# HA-Primary Device Control — Decision

Architectural decision: the Artemis BE talks to **Home Assistant** (HA)
as its device-control plane. Direct talk to `zwave-js-ui` over its
WebSocket protocol is reserved for admin/diagnostic operations only.

This doc exists so future contributors don't relitigate the question.
It complements (does not replace):

- `ha_websocket/` — Elixir WS client library evaluation (Fresh vs
  WebSockex vs Mint.WebSocket).
- `../../technical-design.md` — the v1 architecture and data model.
- `../../technical-notes.md` — running list of resolved Q&A.

## Decision

Default control path:

```
Artemis BE ──HTTP──► HA REST     /api/services/cover/*, /api/states/...
Artemis BE ──WS────► HA WS       events, zwave_js/add_node, etc.
HA         ──────► zwave-js-ui   the Z-Wave JS integration
zwave-js-ui ────►  Z-Wave stick  the 800-series controller
```

`zwave-js-ui` is also reachable directly from the BE for a narrow set
of admin operations (see §"Escape hatch" below), but no day-to-day
device control should go that route.

## Why HA, not direct zwave-js-ui

Five reasons grounded in the existing planning docs:

1. **Future device types span protocols.** v1 ships blinds (Z-Wave
   covers). v2+ device types listed in `requirements-be.md` and
   `technical-design.md` (lights, thermostats, garage doors, locks,
   cameras) will not all be Z-Wave. HA already abstracts protocol
   differences behind a uniform entity/service model. A direct-to-zwave
   BE would need a parallel transport per protocol.
2. **HA is the user's existing source of truth.** Mobile app,
   HomeKit/Alexa bridges, automations, energy monitor, and other HA
   integrations all read HA's entity state. State changes Artemis
   makes through HA are visible to those clients immediately. State
   changes that bypass HA show up only on HA's next poll of the
   subordinate integration.
3. **The data model already assumes HA addressing.** Per
   `technical-design.md`, each `blind` row stores `ha_entity_id`
   (e.g. `cover.living_room_left`). Going direct to Z-Wave JS would
   force tracking `(nodeId, endpoint, commandClass, property)` tuples
   instead and reconciling them with whatever HA shows in its UI.
4. **Stable testable boundary.** Mocking the HA REST+WS surface is a
   smaller, more stable contract than mocking the Z-Wave JS Server
   protocol. The Z-Wave JS Server protocol churns across major
   versions; HA's REST is essentially frozen.
5. **MCP tools map cleanly.** The `:mcp` umbrella app exposes
   device-class operations (`set_cover_position`, `unlock_door`,
   `set_temperature`). These line up 1:1 with HA service calls. They
   would not line up with raw Z-Wave commands.

## What goes through HA

All of:

- Device state reads (`GET /api/states`, polled by `:core/device_cache`).
- Device commands (`POST /api/services/<domain>/<service>`).
- Device pairing UX: `zwave_js/add_node`, `zwave_js/stop_inclusion`,
  `zwave_js/remove_node`, `zwave_js/parse_qr_code_string`,
  `zwave_js/provision_smart_start_node`.
- Real-time event subscriptions: `state_changed`,
  `zwave_js_notification`, inclusion progress events.
- Long-lived access token auth (no per-call OAuth dance).

## Escape hatch: direct zwave-js-ui WS

`zwave-js-ui` exposes the full Z-Wave JS Server protocol on its
WebSocket port (3000 inside the container; host-mapped to 8991 in the
current Synology compose). The BE keeps a thin client module for the
narrow set of operations HA's surface does not cover cleanly:

- **Firmware updates** for individual nodes (manufacturer-supplied
  files). zwave-js-ui's surface is richer than HA's wrapper.
- **NVM backup / restore.** Z-Wave network-state preservation.
  Pure admin operation. Surface as a scheduled `:dispatch` job.
- **Network diagnostics.** Health check, link-quality probe, neighbor
  table. Useful as MCP "diagnostics" tools.
- **Zniffer capture.** Debug Z-Wave traffic. Power-user only.

Module placement: `apps/core/lib/core/ha/zwjs_admin.ex` (or similar),
sibling to the primary `apps/core/lib/core/ha/client.ex`. Both wrapped
behind behaviours so Mox can isolate tests.

These are admin/debug surfaces. Nothing user-facing or in the
device-control hot path uses this client.

## What's deliberately not on the table

- **Bypassing HA for "performance".** The ~50–200 ms hop is real but
  irrelevant for blinds, lights, locks. Reconsider only if a future
  device type needs sub-50 ms loop control (rare).
- **Running Artemis without HA.** Even if Z-Wave is the only protocol
  forever, HA gives us the entity catalog, areas, friendly names, and
  automation engine for free. Cost to replicate in the BE is large.
- **Building parallel Z-Wave-specific data tables.** Stay in HA's
  addressing model.

## Open follow-ups

- Capture fixture data from a live HA instance — see
  `fixtures/README.md` for the layout and what commands populate it.
  These fixtures back `:core/ha/client` tests.
- Decide WS event-bus filtering strategy. HA's WS event stream is
  verbose; the BE should subscribe with a narrow event filter and let
  unrelated events drop. Documented separately when `Core.HA.Client`
  lands.
- Confirm long-lived token rotation cadence with the BE deployment
  (Synology Docker Compose) — token sits in env var, must survive
  restarts.

## See also

- `ha_websocket/README.md` — chosen Elixir WS client library.
- `../../v0_docs/implementation-plan.md` — v0 PoC architecture (auth
  only; HA integration is v1).
- `../../technical-design.md` — v1 data model and component
  responsibilities. The `:core` app's HA client modules live there.
