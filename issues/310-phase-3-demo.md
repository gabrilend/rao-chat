# 310 — Phase 3 demo

**Phase:** 3 — Clients' connection
**Blocked by:** 302 to 309

## Intended Behavior

As 106 and 210: one command (`run-phase-demo 3`) on loopback only.  Two
homes on 127.0.0.2 and .3, each with its gatherers and device server; a
"phone" and a "browser" (309's WebSocket) paired to the first home.  The
phone writes, the browser sees it pushed, the second home receives it;
the phone locks (308) and catches up on its next check-in; a message is
edited and the edit reaches both devices.  Each scene prints what it
shows and passes or fails.

## Open questions

(None.)

## Related documents

- issues 106 and 210 (the earlier demos)
