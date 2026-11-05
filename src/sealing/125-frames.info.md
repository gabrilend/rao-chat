# 125-frames.lua

Reads a frame from a connection and writes one to it (issue 201, step 3).
A connection is anything with LuaSocket's `receive(n)` and `send(data, i,
j)`.  Load with `require("125-frames")`.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `read_frame(conn, cap)` | connection, optional smaller cap | the frame without its length, or nil and why (and, for a length refusal, the length announced) | Reads the 4-byte length, refuses under 28 or over the cap having read only those 4 bytes, then reads exactly that many, gathering partial reads.  A cap above 124's `CAP` is an error. |
| `write_frame(conn, frame)` | connection, whole frame | true, or nil and why | Sends every byte once: `send` answers the index of the last byte sent, and the next send starts one past it. |
| `receive_exactly(conn, n)` | | n bytes, or nil and why | |
| `PATIENCE` | — | 3 | Timeouts in a row with no progress before giving up.  How long each waits is the connection's (211). |
