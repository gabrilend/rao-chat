# 306 — Live pushing, and several devices at once

**Phase:** 3 — Clients' connection
**Blocked by:** 304, 305
**Blocks:** 308, 310

## Current Behavior

A device catches up when it connects (304) and writes when it sends
(305), but between those it hears nothing.

## Intended Behavior

Planning section 6: "A phone and a browser can both be connected; each
message reaches both, and one sent from either appears on the other",
and messages are "pushed the moment they arrive" while the app is shown.

- **After `caught-up` the connection stays open.**  The home watches the
  RAM folder (as 183's `follow` does: a listing is a hint to re-read)
  and sends each new or changed file to every connected device as a
  `file` record.
- **Several devices at once**: each connection has its own position per
  room; a change is sent once to each.
- **Keeping the connection**: a device sends `ping` when it has heard
  nothing for a while; the home closes a connection that has sent nothing
  for `devices.idle-limit` seconds.

## Status

Built 2026-11-06: the home's side in 187 (`go_live`, `push_round`, a
listing once a second while any device is live, one writer per
connection, `devices.idle-limit`); 190's `live [--for <seconds>]` (pushed
files into the mirror, typed files sent as they appear, `keep-alive`
pings).  Referees 1 to 3 pass and catch their broken versions
(`src/devices/tests/195-test-live-pushing.lua`), with 1b (a corrected
message is pushed), 3b (a live device with keep-alive stays past the
idle limit) and 3c (the setting is required and checked).

## Referees

1. **Pushed at once.**  A message filed while a device is connected
   reaches its mirror within two seconds, without a new `catch-up`.
2. **Both devices hear it.**  Two devices connected; a message typed on
   one appears in the other's mirror.  *Broken:* pushing only to the
   device that wrote (`only-writer`).
3. **A quiet connection is closed** after the idle limit; a pinging one
   is kept.

## Blockers that are not the owner's

- Needs 304, 305.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Polled once a second**, like 183's `follow`: the folder is in RAM,
   so a listing is cheap, and polling needs no file-change library.
2. **The idle limit is a setting with no default**, like every limit in
   the project.

### While building, 2026-11-06

3. **A file removed on the home is not pushed as a removal**: it reaches
   a device at its next catch-up, where the digest catches it (304).
   Removals are rare (a `hide` added, 301 decision 4), and a record of
   their own would be one more thing a device must trust.
4. **The device pings when it has *sent* nothing for `keep-alive`
   seconds** (the issue says "heard nothing").  The home closes a
   connection that has sent it nothing for the idle limit, so a device
   pushed to all the time but silent would be dropped if it counted what
   it heard.  `keep-alive` is a device setting with no default, needed
   only by `live`.
5. **The idle limit counts from the end of the last frame to the start
   of the next**; the first frame of a connection still has only the
   frame deadline (302), so a connection that never says who it is is
   not kept for the idle limit.
6. **One listing a second for the whole home, shared by every live
   connection**, each keeping its own record of what it was sent (size
   and time of each file, so only a file that changed is read again).

## Related documents

- `notes/vision-planning.md` section 6 ("Several devices at once", "When
  the connection is live")
