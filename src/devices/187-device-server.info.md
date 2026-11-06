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
then `caught-up`; `want` with the named files and `sent`.  As a module
it gives `read_devices`, `ring_of`, `handlers` and `serve_connection` to later issues and tests.
