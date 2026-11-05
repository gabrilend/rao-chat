# 132-send.lua

One attempt for one pair.  Everything the pair is missing goes out in log
order on one connection, 32 frames at a time.  Only answers that open
with the room's key, are `ack` records, and name ids sent on this
connection with `filed` or `duplicate` count.  `seams.connect` gives the
connection: a socket from 211, or the tests' relay.  Issue 202, step 3.
