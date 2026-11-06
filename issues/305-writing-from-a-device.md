# 305 — Writing from a device

**Phase:** 3 — Clients' connection
**Blocked by:** 304
**Blocks:** 306, 310

## Current Behavior

A device's mirror (304) can be read but what the person types there goes
nowhere.

## Intended Behavior

- **The person writes into the mirror exactly as on the home machine**:
  183's `write`, pointed at the mirror, drops a file in 301's `typed/`
  shape into `<mailbox>/typed/`.
- **The device sends each typed file** as `typed` (`id`, `content`), the
  oldest first, and removes it only when the home answers `typed-ok`
  (`id`).  `typed-refused` (`id`, `why`) leaves it in place with the
  reason beside it (`<name>.refused`), so nothing typed is lost silently.
- **The home checks it as the filer will** (161's `decode_typed`, a room
  of this home) and puts it into that room's gatherer's `typed/` with
  161's `put`, under a fresh name; the gatherer files and sends it as if
  it were typed on the home machine.
- **Sent twice is filed once**: the home keeps the ids it accepted per
  device (in RAM), so a device that lost the `typed-ok` and sends again
  gets `typed-ok` without a second file.

## Referees

1. **Typed on the phone, sent by the home.**  A file written by 183 into
   the mirror, then `send`: a file appears in the gatherer's `typed/` in
   301's shape, and the mirror's is gone.
2. **Refused stays.**  A typed file for a room the home does not have:
   kept, with its reason.  *Broken:* removing it anyway (`drop-refused`).
3. **Twice is once.**  The same `typed` sent twice: one file in `typed/`.
   *Broken:* no memory of ids (`no-dedupe`).

## Blockers that are not the owner's

- Needs 304.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The id is the typed file's own name** in the mirror (161's
   `new_name`): unique per device and sortable, so the oldest goes first.
2. **Accepted ids are remembered for the server's life only**: a typed
   file whose answer was lost across a server restart could be filed
   twice; the filer's own id check (161's `typed_id`) is the second line.

## Related documents

- `notes/vision-planning.md` section 6, issue 301 (the `typed/` shape)
