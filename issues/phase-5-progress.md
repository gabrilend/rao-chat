# Phase 5 Progress

## Goals
The Android app (planning sections 6, 7, 8 and 11): Kotlin with Jetpack
Compose, like rmail's app, laid out and coloured as rmail's so the two
feel like one family; a viewer of its home's RAM inboxes like the
reference device (190) and the web page (phase 4): pairing, catching up,
writing, live while showing and checking in while locked.  It ends with
the clients talking to each other.
Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.

## Needs the Android toolchain on the owner's machine

Every issue of this phase does.  The machine these issues were written
on has a JDK and Gradle but no Android SDK, no Kotlin compiler of its
own and no phone or emulator, and nothing could be installed on it.  So
phase 5 is a plan, written 2026-11-06: each issue says what to build and
how to check it, and no Kotlin is committed until it can be compiled
(501 decision 3).  Phase 6 (installation) did not wait on it.

## Issues (written 2026-11-06 from planning sections 6, 7, 8 and 11 and a reading of rmail's app)

Build order, each blocked only by earlier ones:

- 501 — the app's project: Kotlin and Compose as rmail's, the palette,
  the shell (tabs, title, error strip), `scripts/compile-android`
- 502 — sealing on the phone (123, 124 and 186 in `javax.crypto`),
  checked against vectors made by the home's own code
- 503 — pairing and reaching the home: Servers and Setup, the test,
  choosing an address
- 504 — catching up on the phone (a mirror in the app's files)
- 505 — how a room looks on the phone: Rooms and Room (section 7, the
  page's rules)
- 506 — writing from the phone (the compose line, the marker)
- 507 — live while showing, checking in while locked (the foreground
  service, 308's deck, notifications)
- 508 — People and Settings on the phone
- 509 — phase 5 demo: the phone and the page talking

Every open question was answered by the builder on 2026-11-06 under the
owner's standing instruction of 2026-11-02; each answer is a dated
decision in its issue, and the owner may overturn it.  The one the owner
will most want to look at is 501 decision 4: the app's libraries come
through Gradle, as rmail's do, against the project's rule of vendored
libraries and no package manager.

Left for later issues, not phase 5's: editing a message from a device,
and changing people and members from a device (as phase 4 left them);
the rmail link (phase 7).

## Completed Issues
(None yet.)

## In Progress
(None: waiting on the Android toolchain.)
