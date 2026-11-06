# 187-device-server.lua

The home's device port (issue 302): one process per home,
`luajit src/devices/187-device-server.lua <project> <disk home>`.
Listens on `devices.address` `devices.port`; opens each connection's
first frame under every paired device's key (the `devices` file, rmail's
contacts format with `own = true`, mode 600), keeps that device for the
connection, answers each record (186) through `M.handlers` under the
device's own key, and closes on anything else without a byte in the
clear.  The `devices` file is read again at each connection's first
frame.  State, running log and the `stop` file are in
`<home RAM folder>/devices/`.  Catching up (304): `catch-up` is answered
with every `state`, `.tree` and `.room`, the message files after the
device's position in each room, an `index` where the digests disagree,
then `caught-up`; `want` with the named files and `sent`.  Writing
(305): a `typed` file checked as the filer will is put into the room's
gatherer's `typed/` under the device's id, once per id.  Live (306):
after a catch-up each new or changed file is pushed to every live
device from one listing a second; a connection quiet for
`devices.idle-limit` after its first frame is closed.  As a module
it gives `read_devices`, `ring_of`, `handlers` and `serve_connection` to later issues and tests.  The browser's way in (309): an HTTP/1.1 WebSocket
upgrade on `devices.websocket-path` is answered with the standard 101,
any other request with not a byte; then one 302 frame per masked binary
message (`M.websocket`, with a client half the reference device uses).
