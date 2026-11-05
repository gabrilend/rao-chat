# 130-delivered.lua

The `delivered` file beside a room's `log`: one line per pair on the send
list (address, port, a mark, and the ids acknowledged after the mark).
What a pair is missing is worked out from the log, never stored.  `join`
makes lines for pairs that are new to the send list and drops lines for
pairs that left it.  `acknowledge` adds ids and moves the mark forward.
`pile` gives the counts for the viewer.  `drop` removes one pair's line
(208: a confirmed leave drops what was not yet delivered).  Since 209
each line also keeps `after`, the newest own record when the line was
made: `meant_for` gives the own records written for the pair since then,
and `forget` makes some of them missing again (the cross-check's gap
filling; only an acknowledgement marks them again).  Issue 202, step 1.
