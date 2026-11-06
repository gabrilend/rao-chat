# 507 — Live while showing, checking in while locked

**Phase:** 5 — The Android app
**Blocked by:** 506
**Blocks:** 508, 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

The home pushes to a connected device (306), and 190 keeps a connection
live with keep-alives; 308 deals the locked-screen check-in's offsets
from a deck of −5 … +5 without replacement, and 190's `check-in` runs
that loop.  Android's side of it, a foreground service, was left to
phase 5 (308's blockers).

## Intended Behavior

Planning section 6:

| the phone is… | the connection |
|---|---|
| showing the app | live: messages are pushed the moment they arrive |
| showing another app, screen on | still live |
| locked (screen off) | closed; the app checks in about every 30 seconds |

- **Live**: one connection to the home while the screen is on, kept with
  keep-alives as 190's; pushes (306) go into the mirror and the screens
  at once.
- **Locked**: the connection closed; a check-in (one 304 catch-up) after
  each wait of 30 seconds plus the next card of 308's deck, dealt
  without replacement and reshuffled when empty.
- **A foreground service** does the waking, with its permanent
  notification made quiet (the lowest importance Android allows for
  one); without it Android delays background work to 15 minutes or more.
- **Notifications** for new messages, with the detail chosen in Settings
  (508): sender and text, sender only, no preview, or none.
- **Several devices at once**: a message sent from the page appears on
  the phone, and one from the phone on the page (306).

## Status

Plan only (2026-11-06); not built.

## Rubric

From `notes/rmail-rubric/structure-and-defences.md`: no busy loop; a
wait that can be woken.

## Referees

1. **The deck is 308's**: a JVM test of the app's deck against 308's
   referees (eleven deals, each card once; any whole number of passes
   averages 30 s; reshuffled).
2. **Live**: with the screen on, a message from the other home reaches
   the phone in under a second or two (a person with a stopwatch, or an
   instrumented test).
3. **Locked**: with the screen off for five minutes, the home's device
   log shows a check-in about every 30 s and no connection kept between.
4. **The notification** shows only what Settings allows.

## Suggested Implementation Steps

1. The deck (JVM test), the live connection, the service, then
   notifications.

## Blockers that are not the owner's

- A phone (an emulator does not lock and sleep as a phone does) for
  referee 3.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **A foreground service, not WorkManager**: WorkManager's shortest
   period is 15 minutes, and section 6 asks for about 30 seconds; the
   planning document already names the foreground service and its
   notification.
2. **The deck is 308's, ported**, not a new one: the cards (−5 … +5) were
   decided there.

## Related documents

- issues 306, 308 (the deck), 407 (the page's live connection)
