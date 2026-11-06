# 408 — People and Settings

**Phase:** 4 — The web client
**Blocked by:** 407
**Blocks:** 409

## Current Behavior

The page talks (404 to 407), but section 9's "People and Settings open
over the room view" are empty frames from 401, and the top bar's name
and connection state are not filled in.

## Intended Behavior

Planning section 9: "Top bar: the server's name (click to switch
servers), connection state, the error strip.  People and Settings open
over the room view."  Section 8's tabs: Rooms · People · Settings.

- **Settings** (over the room view): the pasted pairing lines (403), the
  token box, "remember on this computer", the signature field (406), the
  connection test and its words, and a "forget this home" button that
  clears what the page remembers (the "danger zone" of section 8, here
  only the page's own memory).
- **People**: the direct-message rooms (`.tree` kind `direct`), each with
  its label and the last line said in it.  Rooms tie to people through
  the home's `people/` links, which are not in the viewer's folder, so
  this list shows the direct-message rooms and opens one on a click
  (decision 1).
- **The top bar**: the home's name (the label the person gave it in
  Settings, or the address it reached), the connection state ("live",
  "catching up", "connecting…", "not connected"), and the error strip
  (407).  Several homes: the page keeps one home's settings per label,
  and clicking the name lists them to switch (section 9's "click to
  switch servers").
- **Panels open over the room** and close with Escape or their own
  close button; the room behind keeps its place.

## Status

Built 2026-11-06: `src/web/225-panels.js` (`rao.panels`: remembered homes
by label, People, the top bar's words and name); the page fills the top
bar, the People and Homes panels, opens on the last home remembered, and
keeps each home's lines and signature under its name (207); the
stand-in's `homes`, `people`, `topbar`, and a storage for `draw`.
Referees 1 to 4 pass, 2 catching its broken version
(`src/web/tests/226-test-people-and-settings.lua`), with 5 (the page's
own script, on the paper document: the form, the top bar and both lists
from what is remembered, and a browser with no storage said).

## Referees

1. **Settings round trip**: remembered settings read back as the same
   lines without the token; "forget this home" leaves nothing of it.
2. **Several homes**: two labels remembered, each with its own lines;
   switching chooses the other's lines.  *Broken:* one slot for every
   home (`one-home`).
3. **People lists the direct-message rooms** of every mailbox and no
   group room.
4. **The top bar's words** for each connection state, and the home's
   name falling back to the address reached.

## Suggested Implementation Steps

1. `rao.panels`: what Settings and People show, and the remembered homes.
2. The page's panels and top bar.
3. The stand-in's `people` and `homes`, and the referees.

## Blockers that are not the owner's

- Needs 407.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **People shows the direct-message rooms only, and edits nothing.**
   Section 8's People tab edits contacts "as a form", and 301 says config
   and the ignore list are changed "through one home-level route the
   viewer uses".  No device record carries such a change yet, and
   inventing one here would be a change to the home's protocol hidden
   inside a page issue.  Changing people, members, withheld and ignore
   lists from a device is left for its own issue, said in the phase 4
   progress file.
2. **The home's name is the person's own label for it**, typed in
   Settings, like a room's label (names belong to the reader); the
   address reached stands in until one is given.
3. **Remembered homes are keyed by that label** in the browser's storage,
   each holding its lines without the token (403 decision 2).

### While building, 2026-11-06

4. **The signature is kept per home**, with that home's lines, rather
   than once for the page (406 kept one): a person may sign differently
   on different homes.
5. **Remembering needs a name**: with "remember" ticked and no name, the
   page says so and keeps nothing, since a home is found again by its
   name.
6. **The page opens on the last home it connected to** (its lines, name
   and signature in the form; the token pasted again); Homes lists the
   others to choose.
7. **"Forget this home" forgets the home named in the form** and clears
   the form; with no name it only clears the form, and says so.

## Related documents

- `notes/vision-planning.md` sections 8 ("Look", "Screens"), 9
- issues 403, 406, 407
