# 406 — Writing from the page

**Phase:** 4 — The web client
**Blocked by:** 405
**Blocks:** 407, 409

## Current Behavior

The page shows its rooms (405) but cannot say anything in them.

## Intended Behavior

As 305, with the page as the device; planning section 8's Room screen:
"The compose line at the bottom grows as you type and keeps the cursor in
view ... A 'sending… / sent / waiting' marker under your last message."

- **The compose line** at the bottom of the open room grows with its
  text.  Enter sends; Shift+Enter is a new line.
- **The signature field** is persistent (planning section 2: "typed by
  its writer in a persistent 'signature' field"), kept with the page's
  remembered settings, and checked by 214's one rule before anything is
  sent: a signature that would be read back as body text, or not as
  itself, is refused with 183's words.
- **A typed file in 301's shape**, exactly as 183's `typed_text` makes
  it: `room:`, `written:` (the browser's clock, whole seconds), a blank
  line, the text with "\r\n" made "\n" and trailing line breaks taken
  off, the signature after a blank line, one final "\n".  Its name is
  161's `<seconds>-<sequence>-<8 hex>`.
- **Sent as `typed`** (`id` the name, `content` the file); kept in the
  page until the home answers `typed-ok`.  `typed-refused` keeps it, shown
  under the compose line with the home's reason; nothing typed is lost
  silently.  What is still waiting when the connection drops is sent
  again, the same name and bytes, when it comes back (the home and the
  filer file it once: 305 decision 2, 301 decision 13).
- **The marker under the person's last message**: "sending…" while the
  home has not taken it, "sent" once taken, and "waiting" while the
  room's `.room` shows members still owed messages.
- **214's rule in the page** (`rao.signature`), graded by
  `src/signature/170-signature-examples.txt`, the table every reader of a
  signature is graded by.

## Status

Built 2026-11-06: `src/web/220-signature.js` (`rao.signature`, 214's
rule) and `221-writing.js` (`rao.writing`: the typed file, its name, the
outbox, the marker); the page's compose line, signature field, sending
after each catch-up, refused items with "put it back" and "forget it",
and the browser's "leave this page?" while something is still sending
(207); the stand-in's `signature`, `typed`, `write` and typing in
`draw`.  Referees 1 to 5 pass, 1 and 4 catching their broken versions
(`src/web/tests/222-test-writing-from-the-page.lua`), with 6 (the marker
says waiting while the room's `.room` shows members owed) and 7 (the
compose line on the paper document: Enter sends and empties it,
Shift+Enter is left to the text box, it grows, a bad signature keeps the
text and says why).

## Referees

1. **The rule is 214's.**  Every example in 170 reads, in the page, to
   its body and signature.  *Broken:* counting bytes, not characters
   (`bytes`).
2. **The same typed file as 183.**  For the same room, text, signature
   and time, the page's typed bytes equal 183's `typed_text`; a
   signature 183 refuses, the page refuses.
3. **Typed in the page, put by the home.**  `write` against a real
   device server: a file appears in the room's gatherer's `typed/`, and
   the page's pending list is empty.
4. **Refused stays.**  A room the home does not have: kept, with the
   home's reason.  *Broken:* dropping it (`drop-refused`).
5. **Sent again is filed once.**  A typed file whose `typed-ok` was lost
   (the connection cut first) is sent again on the next connection: one
   file in `typed/`.

## Suggested Implementation Steps

1. `rao.signature` (169) and `rao.writing` (the typed file, its name,
   the pending list, the marker).
2. The compose line and signature field in the page.
3. The stand-in's `write`, and the referees.

## Blockers that are not the owner's

- Needs 405, and 305's home side (built).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Enter sends, Shift+Enter breaks the line**, as most chat pages; the
   compose line's own words say so.
2. **The pending list lives in the page's memory**: closing the page
   with something still "sending…" asks the browser's own "leave this
   page?" question, rather than keeping typed text on disk.
3. **Edits are not made from the page yet**: a typed file holds only
   `room:` and `written:` (310 decision 2 found the same for the
   reference viewer), and no device record names a correction.  This is
   left for a later issue, said in the phase 4 progress file.

### While building, 2026-11-06

4. **A refusal's words are text**: a signature that would not read back
   is named in the reason as the person typed it, not as its bytes.
5. **A refused item waits for the person**: under the compose line, with
   the home's reason, until they put it back into the compose line (to
   change and send again) or forget it.  Nothing is dropped by the page
   on its own.
6. **The marker is shown only in a room this page has written in since
   it opened**: "sending…" while unanswered, then "sent", or "waiting"
   while the room's `.room` names members still owed messages.  The page
   cannot tell which messages in the room are its own sending, so it
   puts the marker after the room's last line.
7. **The signature is checked when it is changed and again when
   sending**, and kept in the browser's storage, under its own name, only
   when "remember" is ticked; "Forget this home" forgets it too.
8. **While the outbox waits for an answer**, a `file` the home pushes is
   taken into the mirror (with 404's path check) and a `pong` passes;
   anything else ends the sending, said, as a record not due ends a
   catch-up.  407 puts this in the one reader of a live connection.
9. **Referee 5's cut is the stand-in's own**: it sends the typed record
   and closes before any answer, then the page's outbox sends what is
   still unanswered on a new connection, as the page does after
   reconnecting.

## Related documents

- issues 214, 301 (the typed shape), 305
- `notes/vision-planning.md` section 8 ("Screens", the Room row)
