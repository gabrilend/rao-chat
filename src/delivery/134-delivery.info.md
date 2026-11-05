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
- `hello` (205): a hello job with its own timer, run in `pass` before the
  deliveries until an ack names its claim.  Made by `write` before the
  first message to a pair never heard from, by `start` for every pair, and
  afresh by `moved`; only when the stage's seams give `own_pairs` (212).
- `leave` (208): a leave job to every send-list pair, sent like a hello.
  The room's pending hellos are dropped, and it gets no start-up hello
  until this home writes in it again.  A pair whose leave is being
  checked gets no delivery attempt until the check settles.

211 runs the stage.  Issue 202, steps 2 and 4.
