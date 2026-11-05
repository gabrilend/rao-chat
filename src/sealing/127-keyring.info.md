# 127-keyring.lua

The keys a port tries on a frame, and the trial opening across them
(issue 201, steps 4 and 5).  Load with `require("127-keyring")`; signs up
to the change bell (005) on load and drops a home's keyrings on its
`token`, `created`, `mailbox` and `removed-room` rings, so the next frame
rebuilds them.

A key opens a frame when GCM's check passes and the body begins with that
key's tying value (201a), so trying stops at the first key that opens it.
The trial is split into one slice per worker; this file splits and
combines, and the gatherer (211) will run each slice in its own worker.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `from_tokens(list)` | `{{room, token}, ...}` | keyring `{entries = {{room, key, tie}}}` | |
| `for_mailbox(rooms, home, mailbox_tag)` | 002's module, a home, a mailbox tag | keyring | The mailbox's rooms' keys (room = local tag); kept until the bell drops it. |
| `for_port(rooms, home, port)` | | keyring | Every mailbox on that port; a port's keys only. |
| `open_frame(ring, after_length, workers, opener)` | keyring, frame without length, workers (default 1), optional opener | room, record, keys tried; or nil, nil, keys tried | Two slices opening one frame is an error, never a choice. |
| `slices(n, w)` | keys, workers | `{{first, last}, ...}` | Every key once, in order, sizes differing by at most one. |
| `try_slice(...)`, `combine(answers)` | | | One worker's share, and the combining, for tests. |
