# 133-receive.lua

Serves one connection.  For each frame it opens the frame with the port's
keyring, files the record (unless the sending address is ignored at
hide), records the member as heard when exactly one member is at that
address, and answers with one sealed `ack`.  A frame that no key opens
closes the connection.  The stage it runs in comes from 211's seams.
Issue 202, step 5.
