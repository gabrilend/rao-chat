# 186-device-records.lua

The records a home and its paired devices exchange inside device frames
(issue 302): 126's one-line shape (kind, then tab-separated fields with
the log's escaping) with a table of its own, so device kinds and room
kinds never mix.  `encode(record)` errors on a wrong record; `decode(line)`
gives the record or nil and why.  302's kinds: `ping` (id), `pong` (id,
at). 304's: `catch-up` (rooms), `file` (path,
content), `index` (room, entries), `want` (id, room, names), `sent`
(id), `caught-up` (at).
