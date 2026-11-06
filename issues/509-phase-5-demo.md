# 509 — Phase 5 demo: the phone and the page talking

**Phase:** 5 — The Android app
**Blocked by:** 501 to 508

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Intended Behavior

As 106, 210, 310, 409: one command (`run-phase-demo 5`), on the owner's
machine.  Planning section 12: "phases 4 and 5 end with the clients
talking to each other."

- **Two homes** on the owner's machine (127.0.0.2 and .3, as the
  earlier demos, or the owner's own two installed homes, 606).
- **The app** on a phone or emulator, paired with home A (189), built and
  installed by `scripts/compile-android`.
- **The web page** (phase 4) paired with home B.
- **They talk**: the phone writes and the page shows it; the page answers
  and the phone shows it, live; the phone locked, it catches up at its
  check-ins.
- **What is printed** is read from the homes' folders and the phone's
  mirror (through `adb`, read-only), never text about them.

## Status

Plan only (2026-11-06); not built.

## Referees

1. **The demo runs whole** on the owner's machine with a phone or
   emulator connected; without one it says what is missing and exits 1.
2. **They talk**: the page's mirror holds what the phone wrote, and the
   phone's mirror what the page wrote.
3. **Broken versions fail**: a scene made to fail
   (`RAO_PHASE5_DEMO_BREAK`), and no phone connected.

## Blockers that are not the owner's

- None besides the toolchain and a phone or emulator.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The phone and the page**, not two phones: section 12 asks for the
   clients talking to each other, and the page already runs here
   (phase 4); one phone is what the owner has to hand.
2. **The phone's mirror is read through `adb`** (`run-as` on the debug
   build): what is printed is what the phone holds.

## Related documents

- issues 106, 210, 310, 409 (the earlier demos), 606
