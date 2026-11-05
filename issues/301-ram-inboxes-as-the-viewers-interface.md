# 301 — The RAM inboxes as the viewer's interface

**Phase:** 3 — Clients' connection
**Blocked by:** 211, 214

## Current Behavior

Nothing exists.  211 gives each mailbox gatherer an `inbox/` folder it
writes and a `typed/` folder it reads, in its RAM folder; this issue
defines what is in them.  Phase 1's `people/` links and the room tree are
on disk; 102 can draw the tree as text.

## Intended Behavior

The owner (2026-09-27): "Many data gatherers, one viewer, which is the
android app or HTML page, both simply viewers for the rmail inboxes
located in RAM, pulled from disk by the gatherers at startup, and synced
periodically. The user types, and it creates messages and puts them in the
right place - the user never needs to touch the filesystem at all, except
for pointing out where to store the mailboxes."

- **The viewer reads only RAM**: the `inbox/` and `state` of every gatherer
  of the home, found through the home's RAM root.  It never reads the disk
  home or a room's log.
- **One file per message, in rmail's inbox-file shape**: header lines,
  a blank line, the body — so a viewer written for rmail's inbox reads
  rao-chat's with its own field names:

  | line | holds | datatype |
  |---|---|---|
  | `id:` | message id | 32 hex |
  | `room:` | the room's local tag on this home | 32 hex |
  | `from:` | `me` or `"<address> <port>"`, or the direct-message label that holds that pair (103's `shown_as`) | text |
  | `written:` / `arrived:` | whole seconds since 1970 | integer |
  | `signature:` | 214's rule | text |
  | `edited:` / `deleted:` | `yes` or `no` | text |
  | `ignored:` | `none` or `mark` (a `hide` address is never filed) | text |
  | (blank line, then) | the body, signature removed, edits applied | text |

  Path: `inbox/<room local tag>/<written>-<id>`.  Sorted by name, a room's
  folder is the room's order (written time, then id — 105's order).
- **A room's own facts** beside its messages: `inbox/<room local tag>/.room`
  — label, kind, parent, the path of labels (102), member count, flagged
  count, the pile of undelivered messages per pair (202).
- **The tree** of the home: `inbox/.tree` in each gatherer, and the viewer
  joins the gatherers' trees into one.
- **Writing is dropping a file into `typed/`**: `room:` (local tag),
  `written:` (integer seconds), a blank line, then the text with the
  person's signature appended (214).  The filer gives it an id, files it
  and sends it; the file is removed when filed.  Config and the ignore list
  are changed through one home-level route the viewer uses (211's
  home-wide files).
- **The Android app and the web page are both viewers** of this folder,
  reaching it through their connection to the home (the rest of phase 3);
  a viewer running on the home machine itself reads it directly.

## Status

Built 2026-11-05: steps 1, 2 and 3.

- Step 1: every gatherer keeps `inbox/<room local tag>/<written>-<id>` in
  its RAM folder, in the shape above (`src/gatherer/181-inbox-files.lua`),
  each room's `.room` beside its messages, and the mailbox's `inbox/.tree`.
- Step 2: the filer reads `typed/` files in the shape above (`room:`,
  `written:`, a blank line, the text with its signature); 211's first
  shape is still read.
- Step 3: the reference viewer, `src/viewer/183-viewer.lua` (`tree`,
  `room`, `write`, `follow`, `problems`), reading and writing only the
  home's RAM folder.
- Referees 1 to 5 pass and catch their broken versions
  (`src/gatherer/tests/182-test-inbox-files.lua`), and the viewer's
  (`src/viewer/tests/184-test-viewer.lua`).

What is left belongs to the next phase 3 issues: open questions 1 and 2
(how a phone or a browser reaches the home and mirrors the folder).

## Decisions (2026-11-05)

Made by the builder; the owner can overturn each.

1. **The first slice is the message files alone.**  They are what every
   later step reads and what the referees mostly test; `.room`, `.tree`
   and the new `typed/` shape are separate pieces with their own checks.
2. **`from:` shows 103's `shown_as` text** (the direct-message label, or
   `<address> <port>` when there is none), as the table above says, and
   `me` for own messages.  The ignore level is looked up by the pair, so
   a label does not hide a `mark`.
3. **`<written>` is not zero-padded**, matching 215's copy names.  Name
   order is the room's order while written times have ten digits, which
   is every time from 2001 to 2286.
4. **A `hide` added after a message was filed removes its file.**  The
   rule "a `hide` address is never filed" is about arrival; a viewer
   should not go on showing what the owner has since hidden.  Taking the
   hide off brings the file back at the next pass.
5. **Written when the text changes, and every sync rewrites what
   differs.**  So an ignore-list change, or a file the person removed,
   is made good within a sync interval; removing a file deletes nothing.
6. **Open question 3 (the whole history in RAM): all of it, for now.**
   The RAM home already holds every room's log; the inbox roughly
   doubles that.  Keeping only recent messages needs a way for a viewer
   to ask for older ones, which is the catching-up the remote viewers
   need anyway — decide it there.
7. **Open question 4 (problems belonging to no room): from each
   gatherer's `state`**, as 211 already writes them; nothing new here.
8. **Open questions 1 and 2 (the device port, mirroring the folder)
   belong to the issues that build the remote viewers** and change
   nothing in this folder's layout, so they are left for those issues.

### Steps 1 (`.room`, `.tree`) and 2 (`typed/`), 2026-11-05

9. **`.room` is `key: value` lines** like the message files: `label:`,
   `kind:`, `parent:` (a tag, or `none`), `path:`, `members:`,
   `flagged:`, and one `pile: <address> <port> <missing> <oldest
   written>` line per pair still owed something, or `pile: none`.  Pairs
   owed nothing are left out: the pile is what waits.
10. **The parent and the path come from 102 on the disk home**, which
    holds every room of the home.  A gatherer's RAM home holds only its
    own mailbox's rooms, and a room filed under one in another mailbox
    would show there as a top room.  So each `.tree` line already names
    the room's real parent, and a viewer joining gatherers' trees joins
    by tag and places nothing itself.  The rule stays in one place (102),
    as the rubric asks for edits and signatures.
11. **`.tree` is one line per room: `<tag> <parent or none> <kind>
    <label>`**, in 102's order (top first, children by label then tag),
    and the label last because it may hold spaces.
12. **`.room` is rewritten after each sender pass and attempt**, as well
    as when a record is filed and every sync.  The pile moves when a
    member acknowledges, and a viewer should not wait a sync interval to
    see it empty.
13. **A typed file is filed under an id made from its own name and
    bytes** (32 hex of SHA-256).  The filer takes a file into `working/`,
    files it, then removes it; a crash between the last two puts it back
    at start-up (211's rule), and without a stable id it would be filed
    and sent twice.  With one, the filer finds it in the log and only
    removes it.  The id is a hash of the text, but it travels only inside
    sealed frames, beside that same text.
14. **`written:` is the time the person wrote it, but never later than
    the filer's clock**, so a viewer whose clock runs ahead cannot date a
    message in the future.  202's write still keeps it no earlier than
    this home's last own message, so own messages stay in order.
15. **211's `room = <tag>` shape is still read**, so the demo and 211's
    tests keep working; any other header line, or a header named twice,
    is refused with a problem line, so a misspelt `written:` is not
    silently replaced by the filer's clock.
16. **Referee 4's broken version.**  The issue names "a filer that sends
    before filing".  Here nothing can be sent before it is filed: 202's
    sender sends only what the log holds.  So the referee is run with a
    crash between filing and removing the typed file, against the two
    ways this filer can go wrong at that point: a new id each time the
    file is taken (sent twice), and removing the file before filing it
    (lost).  Referee 5 for `typed/` (a slow writer is never read before
    its rename) is 211's referee 6, which already covers every queue.


### Step 3 (the reference viewer), 2026-11-05

17. **A command-line text viewer in Lua**, like the rest of the
    project: one command per look (`tree`, `room`, `write`, `follow`,
    `problems`) rather than a full-screen program, so its output can be
    read by a test and by a person alike.  It is the reference: the
    app and the page do what it does.
18. **It is given the home's RAM folder**, not the disk home: the issue
    says the viewer reads only RAM, and the folder's name already joins
    the home's path to it (211).
19. **`follow` polls once a second** and compares each file's text with
    what it last showed, so a listing is a hint to re-read, never the
    record of what changed (delivery note R10).  No `inotify` binding is
    needed, and it works the same on any system.
20. **The signature is given with `--signature`** and checked by 214's
    one rule before anything is written: a signature that would be read
    back as body text, or not as itself, is refused rather than sent.
21. **Problems that belong to no room come from each gatherer's
    `state`** (decision 7), printed by `problems` with the mailbox they
    came from.

## Rubric

rmail's thin client and its inbox files are the neighbour (structure note,
"Clients"); the rules:

- **A reader never sees half a file** — every file here is written under a
  temporary name and renamed (211's rule, and rmail's partial-send lesson
  in another shape).
- **What a person sees must be what the record says**: edits applied by
  105's `read_ordered`, not re-implemented in the viewer; the signature by
  214's one rule.
- **Nothing is deleted by swiping** (planning section 8, a lesson rmail's
  app learned): removing an inbox file is never how a message is deleted.
- **The server cannot push through a file** (rmail's thin client polls):
  a viewer on the machine waits on file-change notices, treated as hints to
  re-read, never as the record of what changed (delivery note R10).

## Where we differ

rmail's app talks to its daemon over `/api/` requests inside sealed
frames.  The formation here is **the folder is the interface**: the
viewer's whole contract is a folder layout, so any program that can list
a folder is a viewer, and the network part of phase 3 only has to carry
folder changes to a phone or a browser.

- **Gains:** the viewer and gatherers can be built and tested apart; the
  demo (210) can drive the system exactly as a viewer does; a person can
  `ls` their inbox.
- **Costs:** a second copy of every message in RAM (the log, and the
  inbox); the remote viewers need a way to mirror a folder over their
  connection, which is the next phase 3 issues' problem.

## Referees

1. **Order by name.**  Messages filed out of order (a late message) list in
   written-then-id order.  *Broken:* names by arrival.
2. **Edits applied.**  A correction and a deletion: the inbox shows the
   corrected text, and the deleted message with `deleted: yes` and empty
   body.  *Broken:* a viewer applying edits itself from raw records.
3. **Hidden stays hidden.**  A message from a `hide` address has no inbox
   file; a `mark` address's has `ignored: mark`.
4. **Typed becomes sent.**  A file dropped in `typed/` is filed, sent,
   acknowledged, and appears in `inbox/` as `from: me`; the `typed/` file
   is gone.  *Broken:* a filer that sends before filing.
5. **Never half a file.**  A slow writer to `typed/`: the filer never
   reads it before its rename.

## Suggested Implementation Steps

1. The inbox file writer in the filer, and `.room` and `.tree`.
2. The `typed/` reader in the filer.
3. A small viewer on the home machine (text) that reads and writes only
   these folders, as the reference for the app and the page.
4. The referees above.

## Blockers that are not the owner's

- Needs 211 (the folders) and 214 (signatures).

## Open questions

1. **Which port phones and browsers use** to reach the home: a mailbox port
   answers nothing in the clear, and a WebSocket starts with plain text.
   A separate device port per home?  (Rubric question 24.)
2. **How a remote viewer mirrors the folder**: a sealed "what changed since
   id X" per room (planning section 6's catching up), or the folder
   itself synchronised?
3. **The whole history in RAM**: every message of every room as a file is
   a lot of RAM for a long-lived home.  Keep only recent messages in
   `inbox/`, and fetch older ones from disk on request?
4. **Problems belonging to no room** in the viewer's error strip, read from
   each gatherer's `state` (211's question 7)?

## Related documents

- `notes/vision-planning.md` sections 6, 8, 9, 15 ("The server's shape")
- `notes/rmail-rubric/structure-and-defences.md` ("Clients: thin-client")
- issue 211 (the RAM folders)
