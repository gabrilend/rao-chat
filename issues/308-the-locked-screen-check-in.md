# 308 — The locked-screen check-in

**Phase:** 3 — Clients' connection
**Blocked by:** 304, 306
**Blocks:** 310

## Current Behavior

A device is either connected (306) or not; nothing decides when a locked
phone checks in.

## Intended Behavior

Planning section 6: while locked the connection is closed and the app
checks in about every 30 seconds, "each wait is 30 seconds plus an offset
dealt from a shuffled deck of whole-second cards, without putting cards
back; when the deck runs out it is reshuffled", the cards adding up to
zero so the waits average exactly 30 seconds.

- **The deck** (`src/devices/` reference, the Android app follows it):
  the cards −5 … +5, eleven cards (decision 1).  Shuffled with the
  operating system's random bytes (Fisher–Yates), dealt without
  replacement, reshuffled when empty.
- **A check-in** is one 304 `catch-up` exchange, then the connection is
  closed.
- 190's `check-in --for <seconds>` runs the loop, for the referees.

## Referees

1. **Without replacement.**  Eleven deals from a fresh deck are the
   eleven cards once each.  *Broken:* dealing with replacement
   (`replace`).
2. **Averages exactly 30.**  Any whole number of passes through the deck
   sums to 30 seconds a wait.
3. **Reshuffled.**  The twelfth deal starts a new deck; two decks are not
   always in the same order.

## Blockers that are not the owner's

- The Android side (a foreground service, so Android does not delay the
  wake-ups) is phase 5's; this issue is the rule and its reference.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The cards are −5 … +5** (planning question 4).  The owner listed
   eleven cards, 0 … 10: a spread ten seconds wide.  −5 … +5 keeps both
   the count and the width and moves them so they add up to zero, which
   the owner's "averages 30" needs.

## Related documents

- `notes/vision-planning.md` section 6 ("When the connection is live, and
  when it checks in"), section 13 question 4
