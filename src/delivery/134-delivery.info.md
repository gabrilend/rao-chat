# 134-delivery.lua

`write` files your own message, correction or deletion (from "me", with
a new id) after `join`, and gives back the pairs to wake.  The stage
keeps one job and one retry timer per (room, pair):
- `wake`: something new to send.
- `start`: everything missing is due at start-up.
- `heard_at`: hearing from an address makes that address due now.
- `pass`: runs each due job once and moves its timer.
- `check` (204): a call-back check with its own timer, run in `pass`
  after the deliveries; a `yes` or `no` ends it, and no answer retries it.

211 runs the stage.  Issue 202, steps 2 and 4.
