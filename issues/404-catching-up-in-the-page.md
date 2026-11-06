# 404 — Catching up in the page

**Phase:** 4 — The web client
**Blocked by:** 403
**Blocks:** 405 to 409

## Current Behavior

The page can reach its home (403) but holds none of the home's rooms.

## Intended Behavior

As 304, with the page as the device: "On connecting, a client says the
last message id it holds in each room; the server sends everything
after.  ... A new client gets the full history."

- **The page keeps a mirror in memory** of 301's layout: a map from
  path (`<mailbox>/state`, `<mailbox>/inbox/.tree`,
  `<mailbox>/inbox/<room>/.room`, `<mailbox>/inbox/<room>/<written>-<id>`)
  to the file's bytes.  Nothing of a room is written to the computer's
  disk (decision 1).
- **`catch-up` by 192's rule**: one line per room holding a message,
  `<room> <last name> <digest>`, the digest SHA-256 (hex) over
  `<name> <SHA-256 hex of the file>\n` lines of the files held, sorted by
  name.  A page opened afresh lists nothing and is sent everything.
- **The home's answer is taken as 190 takes it**: `file` records written
  into the mirror after 192's path check; `index` records kept; at
  `caught-up`, for each room indexed, files the index does not list are
  dropped and those held otherwise are asked for with `want`, until its
  `sent`; rooms that no mailbox's `.tree` names leave the mirror.
- **A refused path is said and skipped**, and the rest of the exchange
  goes on (304 decision 8).
- The stand-in's `catch-up` writes its mirror into a folder at the end
  (`--mirror-out`), so the referees compare it with the home's file for
  file, as 304's do.

## Status

Built 2026-11-06: `src/web/216-mirror.js` (`rao.mirror`: the path rule,
rooms, digests, positions, taking a file, the index and want, pruning,
`catchUp`); the page catches up after reaching its home and keeps the
mirror for as long as it is open; the stand-in's `catch-up` (with
`--mirror-in`, `--mirror-out`, `--twice`) and `positions`.  Referees 1 to
5 pass, 2 to 4 catching their broken versions
(`src/web/tests/217-test-catching-up-in-the-page.lua`), with 3b (a file
the home no longer holds is dropped), 3c (a room the home has left leaves
the mirror), 3d (a late message is fetched, and a second catch-up at once
gets none) and 4b (a record not due ends the catch-up, said).

## Referees

1. **A new page gets everything**: its mirror equals the home's RAM
   folder's mirrored files, byte for byte.
2. **Only what is new**: after two new messages, a second catch-up from
   the same mirror receives exactly two message files.  *Broken:*
   sending positions of nothing every time (`from-start`).
3. **An edit is caught**: a message file rewritten on the home is
   replaced in the page's mirror.  *Broken:* positions without digests
   (`no-digest`).
4. **A bad path is refused**: a stand-in home answering `file` with
   `../../escape` or a non-hex room: nothing taken, and said.
   *Broken:* no check (`no-path-check`).
5. **The digests are 192's**: for the same files, the page's catch-up
   lines equal 192's `positions_text`.

## Suggested Implementation Steps

1. `rao.mirror`: the path rule, listing, digests, positions, taking a
   file, the index and want, pruning.
2. The stand-in's `catch-up` (with `--mirror-in` and `--mirror-out`, so
   a second run starts from the first's mirror).
3. The referees.

## Blockers that are not the owner's

- Needs 403, and 304's home side (built).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The mirror is in memory only**: opening the page catches up from
   nothing ("a new client gets the full history"), and a reconnect while
   the page is open (407) catches up from what it holds.  Keeping it in
   the browser's storage would leave every room's history on the
   computer's disk, readable by other pages opened from files.  How much
   history a home sends is 301's question 3, still open.
2. **The path rule, the digest and the listing are written again in the
   page** from 192, and referees 1, 4 and 5 hold them to it, as 402's
   table is held to 186.
3. **`state` files are mirrored as files** like the rest; 407 reads their
   problem lines for the error strip.

### While building, 2026-11-06

4. **The broken version `no-digest` is the page's side of it**: the page
   still sends digests, but does nothing with the home's index, so an
   edit is never fetched.  (187's own `no-digest` is the home's side,
   tried by 304's referees.)
5. **Names compare byte for byte**, as Lua compares them, so the page's
   position in a room is the home's.
6. **The stand-in writes only paths the rule passes** when it saves its
   mirror into a folder; a broken version holding another is said
   ("held-unchecked"), never written outside the folder.

## Related documents

- issues 301 (decision 23), 304
