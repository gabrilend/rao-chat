# 133-receive.lua

Serves one connection.  For each frame it opens the frame with the port's
keyring, files the record (unless the sending address is ignored at
hide), records the member as heard when exactly one member is at that
address, and answers with one sealed `ack`.  A `did-you` (204) is answered from
the room's claims (141) instead, and nothing is filed.  A `hello` (205)
goes to the `on_claim` seam (145's `receive`, which starts the
call-backs) and is answered with an `ack` naming its claim id.  A frame that no key opens
closes the connection, and so does a frame refused for its length; each
is reported through a seam, which 139 turns into a failed-decryption
line (203).  The stage it runs in comes from 211's seams.  Issue 202,
step 5.
