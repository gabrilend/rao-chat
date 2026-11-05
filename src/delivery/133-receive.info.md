# 133-receive.lua

Serves one connection.  For each frame it opens the frame with the port's
keyring, files the record (unless the sending address is ignored at
hide), records the member as heard when exactly one member is at that
address, and answers with one sealed `ack`.  A `did-you` (204) is answered from
the room's claims (141) instead, and nothing is filed.  A `hello` (205)
or `leave` (208) goes to the `on_claim` seam (147's `on_claim`, which
starts the call-backs) and is answered with an `ack` naming its claim id.
A `members-digest`, `members-ask` or `members` (207) goes to the
`on_members` seam (152's `answer`) and is answered with the record it
gives; the connection stays open for the rest of the exchange.  A
`summary` or `versions` (209) goes to `on_summary` (156's `answer`) the
same way.
A message from the address of a pair that left, written after its leave,
re-adds the pair and clears its `left` line (208).  A frame that no key opens
closes the connection, and so does a frame refused for its length; each
is reported through a seam, which 139 turns into a failed-decryption
line (203).  The stage it runs in comes from 211's seams.  Issue 202,
step 5.
