# Repeated GET /states/{entity_id} during a transition

What the StateCache sees while a Z-Wave cover is mid-move. Captured
by issuing a service call and polling `GET /states/<entity>` once per
second for ~25 seconds.

## Two distinct transition shapes

The blind reports differently depending on whether the move was
triggered by `open_cover`/`close_cover` or by `set_cover_position`.

### A. `open_cover` / `close_cover` — `state` flips

```
t=0   state=open      pos=51   last_updated=21:35:24
--> open_cover
t=1   state=opening   pos=51   last_updated=21:41:23
t=2   state=opening   pos=51   last_updated=21:41:23
... (10s of "opening" with current_position pinned at 51)
t=11  state=open      pos=100  last_updated=21:41:36
```

Observations:

- HA flips `state` to `"opening"` (or `"closing"`) **immediately** on
  the service call; the response body of `open_cover` already carries
  this state (see `05-set-position-response.md`).
- `current_position` does **not** update during the transition —
  it stays pinned at the starting value. HA waits for the Z-Wave
  node's final position report to update both `state` and
  `current_position` together.
- `last_updated` advances exactly once per HA-side state change:
  on the initial flip to `opening` and on the final settle to `open`
  (or `closed`).
- The flip-back-to-`open` happens when HA receives the post-move
  position report from the node — ~10 seconds end-to-end on this
  network.

### B. `set_cover_position` — `state` stays, only `position` changes

```
t=0  state=open  pos=30  last_updated=21:40:12
--> set_cover_position 50
t=1  state=open  pos=30  last_updated=21:40:12
t=2  state=open  pos=30  last_updated=21:40:12
... (6s of pos=30, no last_updated movement)
t=7  state=open  pos=51  last_updated=21:41:13
... (stable thereafter at the new position)
```

Observations:

- HA never reports `state="opening"` or `state="closing"` during a
  position-only move. `state` stays at its previous value
  (`"open"`/`"closed"`) until the node finishes reporting the new
  position.
- `current_position` jumps **once**, from the old value to the new
  value, at the moment the node reports back — there are no
  intermediate values. HA does not interpolate position in flight.
- The achieved position can differ from the requested position by a
  small margin (requested 50, settled 51). Z-Wave returns what the
  motor actually managed, not what was asked for.
- `last_updated` advances only on the one state-attribute change.
  `last_changed` does **not** advance (since `state` did not change).

## Implications for the StateCache and the FE

- The cache's "is this entity moving?" signal should be the
  conjunction of `(state in {opening, closing})` OR `(last write was
  within N seconds AND current_position hasn't yet reported the
  expected change)`. Relying on `state` alone misses position-only
  moves entirely.
- Adaptive polling after a `set_cover_position` write needs to keep
  polling for the full Z-Wave round-trip window (~8–10s on this
  network), not just one extra cycle. Returning to 5s steady-state
  after the first post-write poll is too eager.
- The FE should display a pending/in-flight indicator from the moment
  the BE accepts a position write until the cached `current_position`
  matches (within ±2) the requested position OR a deadline elapses.
  The BE can surface this via a `last_write` timestamp on the cache
  entry that the controller includes in `GET /api/blinds/states`.
- For `open_cover` / `close_cover`, the FE can rely on the `state`
  field alone — `opening`/`closing` is unambiguous.
- The Z-Wave round-trip latency (~6–10s) is a hardware property, not
  a bug; the FE UX must accommodate it.

## Edge case: a write *during* an in-flight move

Captured live in `08-write-during-in-flight-move.md`. Summary: the
second command supersedes the first, the blind never visits the
first target, and HA reports only the final settled position
(`current_position` changes exactly once). Total settle time is
~12 s when the motor has to reverse mid-flight (vs ~7 s for a
single move). Both POSTs return the same `200 []` HA gives for any
successful service call; no warning that the prior command was
superseded.

## Settled-final-state shape

After ~30 seconds the right blind reported its restored position
exactly:

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
  "last_changed": "2026-05-24T21:42:15.765184+00:00",
  "last_reported": "2026-05-24T21:42:15.765184+00:00",
  "last_updated": "2026-05-24T21:42:15.765184+00:00"
}
```

This is the shape `04-get-state-available.md` documents; included
here so the transition file is self-contained.
