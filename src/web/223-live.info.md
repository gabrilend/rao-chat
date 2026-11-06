# 223-live.js

Live while the page is open (issue 407), as 306 keeps a device live: the
session reaches the home, catches up, sends what the outbox waits on and
listens, taking each pushed `file` into the mirror and each answer into
the outbox, pinging after `keep-alive` seconds of sending nothing; after
a drop it tries again in 5 seconds, doubling to 5 minutes, back to 5
after a catch-up.  The error strip's lines: the drop with its countdown,
then the home's problem lines from each mailbox's `state`.
