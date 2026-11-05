# 173-text-copies.lua

The text copy of every message (issue 215), in
`<home>/git/<mailbox tag>/rooms/<token fingerprint>/<written>-<id>.txt`:
the agreed part only (id, written, kind, target, signature by 169's rule,
a blank line, the text as written), so members' copies are the same
bytes.  A correction rewrites the message's copy with the latest
correction (086's order); a deletion removes it.  `open` makes the
repository; `catch_up(tag)` (the filing hook) applies the records after
the copies' offset in the room's log; `sync(tags)` catches every room
up, rewrites `labels` (never tracked), commits once and saves the
offsets in `.git/rao-copies`.  Ids outside 105's alphabet, or longer than
128, are refused before a path is built.  The log is never written.
