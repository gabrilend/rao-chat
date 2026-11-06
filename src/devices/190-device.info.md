# 190-device.lua

The reference device (issue 303), as 183 is the reference viewer:
`luajit src/devices/190-device.lua <device folder> test [--public] | catch-up`.
Reads `<device folder>/config` (port, home-network, public, token, wait),
sends a sealed ping and says exactly what happened: answered in N ms;
nothing listens (refused); cannot be reached; closed without a word (the
token is not one the home knows); said nothing within the wait; or an
answer that is not this ping's pong.  `catch-up` (304) keeps a mirror of the
home's folder in 301's layout under `<device folder>/mirror`: one
exchange of positions and digests per room, every path checked by 192
before it is written.
