# 131-retry-timer.lua

One timer per pair.  The wait after a failed attempt starts at the floor
and doubles up to the ceiling.  Each wait is offset by a card dealt,
without replacement, from the timer's own deck (-5 .. 5 units of
interval/12), shuffled from the kernel's random source.  A delivered
attempt puts the timer back to the floor.  A round with nothing to send
moves nothing.  Settings: `delivery.retry-floor` and
`delivery.retry-ceiling`, with no defaults.  Issue 202, step 4.
