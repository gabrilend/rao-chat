# 201-phase-3-scenes.lua

The scenes of the phase 3 demo (issue 310), loaded by 200.

`M.ORDER`: the scenes in order, each `{key, title}`.  `M[key]` is a
function `(c) → {lines, gaps}`.  `M.setup(c)` makes the world (or gives
nil and why); `M.finish(c)` stops every process it started (starters and
device servers first through their `stop` files) and removes its folder.

`c` (from 200): `dir`, `scratch`, `m` (the modules by short name: rooms,
disk, message_log, recipients, ram, loopback, inbox, viewer, records,
server, device, mirror), `break_scene`, and `world` once made.

One world for every scene: homes A (127.0.0.2, mailbox port 7702, device
port 7712) and B (127.0.0.3, 7703, 7713) with one room between them,
each with its starter (164) and gatherer (163), and its device server
(187), on the real clock; a phone and a browser paired with A, each a
folder driven by the reference device (190).  The browser's config
names `websocket-path`, so it reaches A through 309's upgrade: it is 190
speaking WebSocket, standing in for phase 4's web client.

- `homes`: both homes started; their four processes, each on its own
  address; A's device server's state file.  Outside a loopback-only
  namespace the gatherers are started by hand, named as a part not run.
- `pairing`: 189 `add phone` and `add browser` on A (the token shown by
  its first word only), `list`, the devices file's mode, each device's
  `test`.
- `catch-up`: a message typed on B reaches A's inbox; each device
  catches up; each mirror compared with A's RAM folder file by file (every
  file there, every message's text the same; a `state`, `.tree` or `.room`
  that A's gatherer has written again since is named); the
  phone's mirror listed and the message shown; a second catch-up
  changing nothing.
- `writing`: the browser goes live (`live --for 300`, in the
  background); the phone writes into its mirror with 183's `write` and
  runs `send`; the times until the message is in A's log, in the
  browser's mirror (pushed) and in B's log; the browser's live output.
- `locked`: the phone runs `check-in --for 300` (base 6 s, 308's deck) in
  the background; B types a message; the time until it is in the
  phone's mirror, and the phone's check-in lines.
- `edit`: the stand-in, said in the output: no viewer or device command
  makes an edit yet, so the scene files a correction of the phone's
  message into A's RAM home with 081's `correct`, beside the running
  gatherer; the times until A's inbox file reads `edited: yes`, the
  browser's copy (pushed) and the phone's (at a check-in) do; the two
  copies compared byte for byte.

A scene raises an error when what it shows did not happen, so 200
counts it as could-not.

`M.helpers`: the small helpers the scenes use (`quote`, `seconds`,
`read_all`, `shell`, `write_private`, `wait_until`, `alive`, `listens`,
`holding`, `compare`, `body_lines`, `short`), given out so the phase 4
demo (228) builds its world and prints its figures the same way.
