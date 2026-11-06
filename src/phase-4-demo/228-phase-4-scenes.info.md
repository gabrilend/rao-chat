# 228-phase-4-scenes.lua

The scenes of the phase 4 demo (issue 409), loaded by 227.

`M.ORDER`: the scenes in order, each `{key, title}`.  `M[key]` is a
function `(c) → {lines, gaps}`.  `M.setup(c)` makes the world (or gives
nil and why); `M.finish(c)` stops every process and removes its folder.
Both borrow the phase 3 demo's (201's `setup`, `finish` and `M.helpers`),
so the two demos make a home the same way (409 decision 3).

`c` (from 227): `dir`, `scratch`, `m` (the modules by short name), `node`
(its version), `break_scene`, and `world` once made.

One world for every scene: 310's two homes, A (127.0.0.2) and B
(127.0.0.3), with one room between them, each with its starter,
gatherer and device server; and a web page paired with each, a folder
holding its settings and its mirror, driven by the stand-in browser
(208) running the page's own scripts under Node.

- `folder`: the page's folder whole (every file the page names is there,
  none unnamed) and naming no address elsewhere; the scripts load and
  WebCrypto answers.
- `homes`: 310's `homes` scene.
- `pairing`: 189 `add laptop --browser` on A and on B (the token shown by
  its first word only); each page's connection test.
- `catch-up`: B types a first message, which reaches A's inbox; each page
  catches up, and its mirror is compared with its home's RAM folder.
- `talking`: page B goes live with `--write-when` (it answers once it
  hears page A); page A goes live and writes; the times until page A's
  message is in A's log, in B's inbox and pushed to page B, and the same
  for page B's answer back to page A.
- `rooms`: each page's room tree and room as the page lays them out
  (405's lines: side, a name where the speaker changes, anchor, time,
  text); each page's own message on its side and the other's on the
  other; each mirror's `from:` lines (its own `me`, the other's not).
- `drop`: page A live again; A's device server stopped (its port no
  longer listens), B types meanwhile, the server started again; page A
  reconnects by itself and gets B's message, with its live output.

A scene raises an error when what it shows did not happen, so 227
counts it as could-not.
