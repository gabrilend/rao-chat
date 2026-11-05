# 134-delivery.lua

`write` files your own message, correction or deletion (from "me", with
a new id) after `join`, and gives back the pairs to wake.  The stage
keeps one job and one retry timer per (room, pair):
- `wake`: something new to send.
- `start`: everything missing is due at start-up.
- `heard_at`: hearing from an address makes that address due now.
- `pass`: runs each due job once and moves its timer.

211 runs the stage.  Issue 202, steps 2 and 4.
