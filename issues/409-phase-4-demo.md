# 409 — Phase 4 demo

**Phase:** 4 — The web client
**Blocked by:** 401 to 408

## Intended Behavior

As 106, 210 and 310: one command (`run-phase-demo 4`) on loopback only,
ending as the planning document says phase 4 ends: "with the clients
talking to each other".

- **Two homes**, A on 127.0.0.2 and B on 127.0.0.3, each with its
  starter, gatherer and device server (310's world), and one room
  between them.
- **Two web clients**: one paired with A (`--browser`), one with B, each
  the page's own scripts run by the stand-in browser (401), reaching its
  home through 309's WebSocket upgrade.
- **The scenes**: the page's folder (whole, nothing from elsewhere); each
  page pairing, testing and catching up; the first page writes and the
  second is pushed it (A's gatherer sends it to B, B's device server
  pushes it to its page); the second answers and the first is pushed
  that; each room shown as the page lays it out (405's lines as text:
  sides, names where the speaker changes); a drop and a return (407).
  Each scene prints what it read and passes or fails.
- **Said plainly in the output**: Node stands in for the browser; the
  page's own drawing is not run here.

## Status

Built 2026-11-06: `issues/completed/demos/phase-4-demo` (also
`./run-phase-demo 4`) runs `src/phase-4-demo/227-phase-4-demo.lua`,
whose seven scenes are in `228-phase-4-scenes.lua`: the page's folder,
the homes (310's), a page paired with each home, each page catching up,
page A writing and page B pushed it and answering, each room as the page
lays it out, and home A's device port stopped and started again with
page A coming back by itself.  The referee,
`src/phase-4-demo/tests/229-test-phase-4-demo.lua`, runs it through
`run-phase-demo 4` and checks every scene's figures, with its two broken
versions.

## Referees

1. **The demo runs whole** through `run-phase-demo 4` from `/`: every
   scene passes, the exit status says so, and nothing is left running
   or on disk.
2. **The clients talk**: each page's mirror holds the other's message,
   with `from:` not `me`, and its own with `from: me`.
3. **Broken versions fail**: a scene made to fail, and a project copy
   missing the stand-in.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Two homes, one page each**, not two pages on one home: a page on
   each side is the planning document's "users can connect from their
   computers and talk to each other", and it carries the message across
   phase 2's delivery as well as phase 3's devices.
2. **Node stands in for both browsers** (401 decision 4), and a machine
   without Node is told so and the demo stops with status 1 before
   starting anything.
3. **310's world is borrowed, not copied**: the homes, gatherers and
   device servers are built by the phase 3 demo's own scene code where it
   allows, so the two demos cannot drift on how a home is made.

### While building, 2026-11-06

4. **Page B answers from inside its live run**: the stand-in's `live`
   takes `--write-when <words>` and writes once a message not its own
   holds them, so the answer is the page's own work on a message pushed
   to it, not a second run timed to follow.
5. **A live page ends when the scene says so** (`--until <file>`, the
   stand-in looking for the file five times a second), not after a run
   time guessed in advance.
6. **201 gives out its helpers** (`M.helpers`) for 228, rather than 228
   copying them: the same reason as decision 3.
7. **The drop stops only A's device server** (through its stop file),
   not the home: the drop 407 deals with is the page's connection, and
   B's message typed meanwhile still reaches A's inbox to be caught up.

## Related documents

- issues 106, 210, 310 (the earlier demos)
- `notes/vision-planning.md` section 12 ("phases 4 and 5 end with the
  clients talking to each other")
