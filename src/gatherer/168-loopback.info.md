# 168-loopback.lua

Brings `lo` up inside a network namespace of one's own (`unshare -rn`
leaves it down), with the same ioctl `ip link set lo up` makes, through
LuaJIT's FFI: no outside tool.  `only_loopback` says whether `lo` is the
only interface, so a program can tell that nothing it does can reach a
network.  Used by the phase 2 demo's real-process scenes (issue 211).
