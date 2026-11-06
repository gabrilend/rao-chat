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

## Status

Built 2026-11-06: `issues/completed/demos/phase-3-demo` (also
`./run-phase-demo 3`) runs `src/phase-3-demo/200-phase-3-demo.lua`,
whose six scenes are in `201-phase-3-scenes.lua`: the homes, pairing,
catching up, the phone writing (pushed to the browser, received by B),
the locked phone's check-ins, and an edit reaching both devices.  The
referee, `src/phase-3-demo/tests/202-test-phase-3-demo.lua`, runs it
through `run-phase-demo 3` and checks every scene's figures, with two
broken versions.

## Open questions

(None.)

### While building, 2026-11-06

1. **The browser is the reference device (190) speaking 309's
   WebSocket.**  The web client is phase 4's; until then the demo's
   browser is a device folder whose config names `websocket-path`, and
   the output says so.  So the demo shows it, 190's "reached the home"
   line now ends ", through a WebSocket upgrade on <path>" when it did.
2. **The edit is a stand-in, said in the output.**  No viewer or device
   command makes an edit yet (183 has no edit command, and a typed file
   holds only room: and written:), so the scene files a correction
   of the phone's message into A's RAM home with 081's `correct`, beside
   the running gatherer, as its filer would.  What the demo shows is the
   rest of the path, which is phase 3's: the gatherer writing the inbox
   file again at its sync, the browser pushed the change, the phone
   catching it at a check-in.  It does not claim the edit reaches B.
3. **One world for all six scenes, built on in order** (the browser stays
   live from `writing` on, the phone checks in from `locked` on), as the
   issue tells it as one story.  A scene that needs what an earlier one
   did not make fails too, saying which.
4. **The demo stops every process it started and removes its folder**
   at the end (phase 2's demo left its folder for 160 to remove): its
   devices run in the background, and a demo left running would hold
   loopback ports the next run needs.
5. **A token is shown by its first word only**, though it is the demo's
   own: the output may be pasted somewhere, and every token opens the
   whole home.

## Related documents

- issues 106 and 210 (the earlier demos)
