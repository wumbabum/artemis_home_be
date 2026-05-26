# Write during an in-flight Z-Wave move

Closes the edge case flagged in `06-state-during-transition.md`
§"Edge case: a write *during* an in-flight move". Captured live
against `cover.living_room_tv_right_outbound_bottom` with the
Z-Wave radio online.

## Scenario

1. Blind sits at `current_position: 51`.
2. Issue `set_cover_position` with `position: 20`.
3. Wait 3 seconds (well within HA's 6–10 s Z-Wave round-trip
   window — the motor has been told to move but no position
   report has come back yet).
4. Issue a second `set_cover_position` with `position: 80`
   against the same entity.
5. Poll `GET /states/<entity>` once per second for 20+ seconds
   and observe what HA reports.

## Result — timeline

```
t=-0    state=open  pos=51   last_updated=00:45:46  (pre-state, stable for prior 5+ min)
t=0     --> POST set_cover_position {position: 20}    status=200 body=[]
t=2.5   state=open  pos=51   last_updated=00:45:46    (no change yet — motor en route)
t=3     --> POST set_cover_position {position: 80}    status=200 body=[]
t=4..14 state=open  pos=51   last_updated=00:45:46    (no change for 11 more polls)
t=15    state=open  pos=80   last_updated=00:46:55    (single jump to second target)
t=16..23 stable at pos=80
```

## Observations

- **The second command wins.** The blind never visited position
  20. It jumped directly from 51 to 80 once the Z-Wave node
  reported back.
- **HA reports no intermediate state.** `current_position`
  changed exactly once, from 51 → 80, at t=15s. The position 20
  target left no observable trace in HA's state.
- **`state` did not flip.** Both commands were `set_cover_position`,
  which (consistent with `06-state-during-transition.md` §B) never
  toggles `state` to `"opening"` or `"closing"`.
- **`last_updated` advances once,** at the moment the new
  `current_position` is reported.
- **Settle time was ~12 s after the second command,** vs ~7 s for
  a single move (`06`). The motor had to start toward 20, reverse,
  and head for 80 — the extra wall-clock cost is the reversal.
- **Both POSTs returned `200 []`** — HA does not warn the caller
  that a prior command is being superseded.

## Implications for the BE

- The `Core.Blinds.set_position/2` API does not need any
  special-casing for "blind is already moving". HA handles
  supersession internally; the BE just issues calls.
- `Core.Blinds.StateCache.schedule_refresh_after/2` only schedules
  a single refresh ~1 s out. After a second call lands, the
  scheduled poll is cancelled-and-rescheduled (`cancel_timer`
  branch in `state_cache.ex`), so the cache picks up the new
  target's eventual position without extra logic. Confirmed by
  the v0.1 `schedule_refresh_after/2 cancels a pending scheduled
  poll` test.
- The window between issuing a command and HA reporting the new
  position can stretch to ~12 s when the caller flip-flops
  mid-flight. The state cache's stale-after-30s threshold remains
  comfortable, but the FE's pending-indicator timeout (currently
  20 s in the FE plan) should stay at least that long to cover
  this case.

## Implications for the FE

- An optimistic pending indicator targeting the **most recent**
  requested position is correct. The first request's target is
  overwritten as soon as a second request arrives.
- The "moving" UX heuristic in
  `planning/smart-blinds/blinds-endpoint.md` §"Latency and the
  cached state" — `(state in {opening, closing})` OR `(last_write
  within N seconds AND position not yet at target)` — naturally
  handles the in-flight-supersede case: each new write resets the
  `last_write` timestamp and the `target`.
- If the FE wants to debounce rapid slider drags, do it
  client-side (e.g. only send on `mouseup` or after 200 ms of
  inactivity) rather than relying on the BE or HA to coalesce.
  The wire fires every write as a real Z-Wave transaction;
  flooding the network with intermediate positions does no good
  and wears the motor.

## Edge cases still not verified

- A second `set_cover_position` issued **after** the first has
  already settled. Expected to behave as a fresh single move —
  unsurprising and not worth a dedicated capture.
- Mixing service types mid-flight (e.g.
  `set_cover_position` followed by `stop_cover` 2 s later).
  Anecdotally `stop_cover` halts the motor immediately, but the
  exact `current_position` reported on settle is hardware-dependent.
  Recommend capturing if `stop_cover` becomes user-facing in the
  FE (currently exposed via `/api/blinds/:id/stop` but not yet
  surfaced in the FE plan as a primary UX element).
- A `set_cover_position` issued *during* an `open_cover` /
  `close_cover` transition (when `state` IS `"opening"` /
  `"closing"`). Different from the position-only flip-flop above
  because `state` is already non-stable.
