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

## Related documents

- `notes/vision-planning.md` section 6 ("Several devices at once", "When
  the connection is live")
