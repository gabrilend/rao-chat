# 185-settings.lua

The config names the device server (187) reads: `devices.port`,
`devices.address`, `devices.frame-deadline`, `devices.idle-limit`,
`devices.websocket-path`.  None has a default; 017
finds this list by scanning `src/`, so a home's `config` may hold them.
