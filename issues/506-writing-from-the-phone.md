# 506 — Writing from the phone

**Phase:** 5 — The Android app
**Blocked by:** 505
**Blocks:** 507 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

A device writes by putting a typed file into its mirror's `typed/`
folder and sending it (305); the page does the same from its compose
line, signing with the signature the person set (406).

## Intended Behavior

Planning section 8, Room: "The compose line at the bottom grows as you
type and keeps the cursor in view (rmail's cursor-aware scrolling).  A
'sending… / sent / waiting' marker under your last message."

- **The compose line** grows with what is typed, keeps the cursor in
  view, and sends on its button (not on Enter: a phone's Enter is a new
  line).
- **What is sent is 305's typed file**, with the room, the time written,
  the text and the signature (406's rule; set in Settings, 508).
- **The marker**: "sending…" until the home has the typed file, "sent"
  once the home's log holds it (it comes back by catch-up or push),
  "waiting" when the home cannot be reached, kept and sent when it can.
- **A typed file is never lost**: it stays in `typed/` until the home
  has it, across the app being stopped.

## Status

Plan only (2026-11-06); not built.

## Referees

1. **The home files it**: a message written on the phone appears in the
   home's room log, and reaches the other home of the room.
2. **Waiting, then sent**: with the home stopped the marker says
   waiting; started again, the message goes and the marker says sent.
3. **The typed file is 305's**: a JVM test of the file's text against
   190's (the vectors of 502).

## Suggested Implementation Steps

1. The typed file and its sending, then the compose line and the marker.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The send button sends; Enter is a new line**: on a phone keyboard
   Enter is where a new line is typed.  (The page sends on Enter, 406,
   with Shift+Enter for a new line.)
2. **No editing from the phone yet**, as the page (406 decision 3): an
   edit from a device needs a device record the home does not have.

## Related documents

- issues 305, 406
