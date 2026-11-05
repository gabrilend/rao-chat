# 147-leaving.lua

Leaving a room (issue 208), and the tombstone a confirmed leave leaves.
- `receive`: what 133 hands a decoded `leave` to (through `on_claim`).
  It ignores this home's own leave sent back, pairs that are not members,
  and a leave older than the newest message filed from that pair (open
  question 1). It hands every other pair to 142's `heard`, so only the
  leaving pair itself can say yes.
- `confirm`: 142's leave action. It calls 103's `confirm_leave`, writes
  the pair's line in the room's `left` file (address, port, confirmed,
  claim id, the leave's written time) and drops its `delivered` line.
- `may_add_from_list`: the guard 207's members lists must call, so a
  replayed list does not undo a leave.
- `at_address`, `clear`: used by 133 to re-add a left pair whose new
  message arrives, and by 142 when its hello is confirmed.
- `mark_own`, `own_left`, `clear_own`: the leaver's own `left-by-me` file.
  While it exists, the room gets no start-up hellos.
- `on_claim`: sends a hello to 145 and a leave to `receive`.

Sending a leave is 134's `Stage:leave`.
