# 304 — Catching up

**Phase:** 3 — Clients' connection
**Blocked by:** 302, 303
**Blocks:** 305, 306, 310

## Current Behavior

A paired device can ping its home (302, 303) but receives nothing of the
viewer's folder.

## Intended Behavior

Decision of 2026-11-06 (301 decision 23; the owner may overturn it):
**sealed catching up per room, not a synchronised folder.**

- **The device keeps a mirror** of the home's RAM folder in 301's exact
  layout, under `<device folder>/mirror`: `<mailbox>/inbox/.tree`,
  `<mailbox>/inbox/<room>/.room`, `<mailbox>/inbox/<room>/<written>-<id>`,
  and `<mailbox>/state`.  The reference viewer (183) reads the mirror
  unchanged.
- **On connecting, the device sends `catch-up`** with one line per room
  it holds: `<room tag> <last message file name> <digest>`.  The digest is
  SHA-256 (hex) over the lines `<name> <SHA-256 hex of the file>` of every
  message file it holds in that room, sorted by name.
- **The home answers with `file` records** (`path`, `content`): every
  `.tree`, `.room` and `state`, and every message file after the device's
  last name in each room (a room the device did not list: all of them —
  "a new client gets the full history").
- **Where the digests disagree** (the home works out the same digest over
  its files up to the device's last name), it also sends `index` (`room`,
  `entries`: `<name> <hash>` lines up to that name).  The device drops the
  files the index does not list and asks with `want` (`id`, `room`,
  `names`) for those it lacks or holds differently; the home sends them
  and then `sent` (`id`).
- **`caught-up`** (`at`) ends the home's answer to `catch-up`.
- **Every path from the network is checked** before it is used: a mailbox
  and a room are 32 hex, a message name is 301's `<digits>-<32 hex>`, and
  nothing else is written.
- `luajit src/devices/190-device.lua <device folder> catch-up` runs one
  exchange and prints how many files changed.

## Status

Built 2026-11-06: `src/devices/192-mirror.lua` (the layout's path rule,
listing and digests, shared by both sides), the home's side in 187
(`catch-up`, `want`), the device's in 190 (`catch-up`); the records in
186.  Referees 1 to 5 pass and catch their broken versions
(`src/devices/tests/193-test-catching-up.lua`), with 0 (the records and
the path rule), 3b (a file the home no longer holds is dropped; a late
message is fetched), 3c (a room the home has left leaves the mirror) and
6 (the home closes on a catch-up or a want it cannot read).

## Rubric

- **Names from the network are cleaned before they are paths** (the
  structure note; rmail's attachment names).
- **Catching up is one exchange** for a device away a week (planning).
- **A reader never sees half a file** (211): the mirror is written under
  temporary names and renamed.

## Referees

1. **A new device gets everything.**  An empty mirror after `catch-up`
   equals the home's folder, file for file.
2. **A device away gets only what is new.**  After two new messages, a
   second `catch-up` sends exactly two message files.  *Broken:* sending
   from the start every time (`from-start`).
3. **An edit is caught.**  A message corrected on the home (its file
   rewritten with `edited: yes`): the device's copy is replaced.
   *Broken:* positions only, no digest (`no-digest`).
4. **A bad path is refused.**  A home answering `file` with
   `../../escape` or a non-hex room: nothing written outside the mirror,
   and the device says so.  *Broken:* no check (`no-path-check`).
5. **The mirror reads as a folder.**  183's `room` on the mirror shows
   what it shows on the home.

## Suggested Implementation Steps

1. The records `catch-up`, `file`, `index`, `want`, `sent`, `caught-up`.
2. The home's side in 187; the device's side in 190.
3. The referees.

## Blockers that are not the owner's

- Needs 302 and 303.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Positions are file names, not ids**: 301's names sort as the room's
   order, so "after" is a string comparison the home and the device make
   the same way.
2. **The digest covers only what the device holds up to its position**,
   so a device that holds everything and a home that has new messages
   agree, and only an edit or a loss starts the index.
3. **A new device gets the whole history**, as the planning document
   says.  How much history the home keeps in RAM is 301's question 3;
   whatever the inbox holds is what a device can be sent.

### While building, 2026-11-06

4. **A message name is `<written>-<id>` with 181's id rule** (letters,
   digits, `-`, `_`, at most 128), not only 32 hex as the intended
   behaviour above says: 181 files any id in 105's alphabet, so the
   stricter rule would refuse files the home really holds.  Every other
   part of the path rule stands.
5. **A room with no message files is not listed** in `catch-up` (it has
   no last name); its `.room` still comes with every answer.
6. **A room the home has left leaves the mirror**: at the end of a
   catch-up, room folders that no `.tree` of their mailbox names are
   removed.  A mailbox folder the home no longer sends is left alone:
   nothing tells a mailbox that is gone from one not started yet.
7. **An index of more than 4000 lines is split** into several `index`
   records for the same room, so a long room's index stays well under
   124's cap; the device acts on them together at `caught-up`.
8. **A refused path is said and skipped**: the rest of the exchange goes
   on, the device prints each refusal and exits 1.
9. **One module, 192, holds the path rule, the listing and the digest**
   for both sides (the issue named only 187 and 190), so the home and the
   device cannot drift apart on what a position or a digest means.

## Related documents

- `notes/vision-planning.md` section 6 ("Catching up")
- issue 301 (decision 23), issue 209 (the cross-check this follows)
