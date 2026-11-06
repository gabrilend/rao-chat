# 505 — How a room looks on the phone: Rooms and Room

**Phase:** 5 — The Android app
**Blocked by:** 504
**Blocks:** 506 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

The page lays out a room as section 7 says (405), from the mirror's
`.tree` and `.room` files and the message files.  The app shows nothing.

## Intended Behavior

Planning section 8's screens:

- **Rooms (tab)**: "the room trees, folded like folders.  Each row: the
  room's name, the last line said in it, an unread marker.  Rooms that
  arrived as separate trees are separate rows at the top level."
- **Room**: the conversation as section 7 lays it out: the reader's
  messages on one side and everyone else's on the other, set apart by
  position and colour; a name only where the speaker changes; notices
  centred, quieter and boxed; every message with its anchor (its id).
  The title is the room's path of names, each tappable.
- **The same rules as the page**: what 405 decided about order, names,
  notices and edits holds here, so a room reads the same in both
  (decision 1).
- **Nothing is deleted by swiping.**

## Status

Plan only (2026-11-06); not built.

## Referees

1. **The same room, the same order and names as the page**: for a mirror
   made by 504, a JVM test lays out each room and compares it with the
   page's layout of the same files (405's `room-view` run under Node by
   the stand-in browser, writing its layout to a file).
2. **The tree**: nested rooms fold and unfold; separate trees are
   separate top rows.
3. **Unread**: a room with a message newer than the last one shown has
   its marker.

## Suggested Implementation Steps

1. The layout as a plain Kotlin function of the mirror's files (testable
   on the JVM), then the Compose screens.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The page's layout rules are the reference** (405): the two clients
   show one room the same way, and a referee compares them.
2. **"Unread" is kept on the phone** (the last message shown per room),
   since the home keeps no read state and read receipts are not decided
   (planning question 11).

## Related documents

- `notes/vision-planning.md` sections 7 and 8; issue 405
