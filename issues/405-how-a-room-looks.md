# 405 — How a room looks

**Phase:** 4 — The web client
**Blocked by:** 404
**Blocks:** 406 to 409

## Current Behavior

The page holds a mirror of the home's rooms (404) but shows none of it.

## Intended Behavior

Planning sections 7 and 9, taken from double-diaper-dungeon's
conversation pages; the reference viewer (183) is what the page follows
for what is read from the files.

- **The room trees in the left column**, joined from every mailbox's
  `.tree` as 183 joins them (a tag's first listing wins, a room under its
  parent when the parent is held, otherwise at the top; children by
  label, then tag), shown like folders that open and fold.  A direct
  message is marked as one.  Each row: the label, the last line said in
  it, and an unread mark (messages that arrived since the room was last
  open in this page).
- **The open room**, its path of labels as the title, its messages in
  file-name order (301: the room's order):
  - **speakers on opposite sides**: the person's own (`from: me`) on one
    side, everyone else's on the other, set apart by position and colour;
  - **a name only where the speaker changes**: a run of messages from the
    same `from:` and signature carries the name (the signature, with the
    `from:` quieter beside it) once, at its top;
  - **notices are neither speaker**: what the home says — members owed
    messages (`.room`'s `pile:` lines, "3 messages could not be
    delivered yet to A P"), flagged members — centred, quieter, boxed;
  - **every message has an anchor**, `#m-<id>`, so a notice or a search
    can link to it;
  - edited messages are marked "edited"; a deleted one shows "(deleted)"
    and no body; a message from an address marked in the ignore list
    (`ignored: mark`) shows only "someone you ignore spoke".
- **What is drawn is worked out apart from drawing it**: `rao.view`
  turns the mirror into plain lists (the tree's rows, the room's lines,
  each with its side, name or none, anchor, text and marks); the page's
  own script only places them, with `textContent`.  The stand-in prints
  the same lists as text, so the referees and the demo read what the
  page would show.

## Rubric

- **What a person sees must be what the record says** (301): edits are
  already applied in the inbox files; the page applies nothing itself.
- **One palette, read by every part** (401).

## Referees

1. **The tree is 183's.**  The page's tree, printed as text, lists the
   same rooms at the same depths in the same order as 183's `tree` on
   the same folder.  *Broken:* children in tag order (`tag-order`).
2. **A name only where the speaker changes.**  Three messages from one
   address and signature, then one from another, then two of the
   person's own: names on the first, fourth and fifth only; sides
   theirs, theirs, theirs, theirs, mine, mine.  *Broken:* a name on
   every line (`name-every-line`).
3. **Notices are neither side**: a room with a pile line shows one
   centred notice naming the address, port and count.
4. **Anchors**: every message line carries `m-<its id>`, and no two
   lines the same.
5. **Marks**: edited, deleted (no body) and ignored-mark (no body) shown
   as above.  *Broken:* showing a marked message's body
   (`show-ignored`).
6. **Markup is text**: a message holding `<b>` and `&amp;` keeps those
   characters in its line's text.

## Suggested Implementation Steps

1. `rao.view`: reading inbox files (183's `read_fields`), the tree, the
   room's lines, unread counts.
2. The page's drawing of the tree and the room.
3. The stand-in's `tree` and `room`, and the referees.

## Blockers that are not the owner's

- Needs 404.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The speaker is the `from:` and the signature together.**  The sender
   is unknowable by design (section 3); `from:` is where the message came
   from (a direct-message label or an address) and the signature is what
   it says about itself.  A change in either starts a new run.  The name
   shown is the signature, as the owner put it: "We don't know anything
   else except what they sign it by."
2. **The person's own messages are on the right**, everyone else's on
   the left, as in chat programs and in the transcript pages the look is
   taken from.
3. **Notices go after the room's last message**: they say how things
   stand now (who is still owed messages), not where in the history
   something happened.
4. **A marked message's body is not shown** ("hide them but show that
   they spoke", section 3), though the inbox file holds it; the
   reference viewer, which shows everything for checking, keeps showing
   it.
5. **Unread counts live in the page's memory**: a room's unread mark is
   the messages that arrived since it was last open in this page.
   Nothing is sent to the home or to anyone (planning question 11, read
   receipts, is untouched).
6. **Times are shown in the browser's own time zone**, as `YYYY-MM-DD
   HH:MM`, like 183.

## Related documents

- `notes/vision-planning.md` sections 7, 8 ("Screens"), 9
- issue 301 (the inbox files), 183 (the reference viewer)
