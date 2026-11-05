# 215 — One git repository per mailbox, with a text copy of every message

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 105, 211, 214
**Blocks:** 215a, 215b, 210

## Current Behavior

Nothing exists.  Each room's `log` (105) is the append-only delivery
record: one tab-separated line per record, repeat-safe by id, never
rewritten.  Nothing writes a human-editable copy anywhere, and rao-chat
has no hook points (planning section 13, "Licence": "rao-chat has no hooks
yet").

## Intended Behavior

The owner (2026-09-27):

> not just the outbox. We build on_receive hooks that create text files
> and store them in git history, dynamically created per room. record
> changes. encourage changes and deletions. perhaps, if desired, a shared
> upstream, so you can coordinate more.

and, settling the repository's scope: "each mailbox gets a git
repository".

- **The log stays the delivery record**; this issue adds a **reading and
  editing copy** beside it.  Nothing in this issue ever changes what is
  sent, acknowledged, or cross-checked.
- **One git repository per mailbox**, made when the mailbox is made (and,
  for mailboxes made before this issue, at the gatherer's first start),
  at `rao-home/git/<mailbox tag>/` (open question 1).
- **A filing hook** runs in the filer stage (211) for every record filed
  into any room of the mailbox — received and own alike — and the built-in
  hook writes the text copy.  Hooks run after the record is filed and
  never block or undo filing; a hook that fails is a running-log problem
  line, and the copy is rewritten from the log at the next sync.
- **The text copy holds only the agreed part** — what every home holding
  the room writes identically, so that two members' copies of one message
  are the same bytes:

  | line | holds | datatype |
  |---|---|---|
  | `id:` | the message id | 32 hex characters |
  | `written:` | when written, as whole seconds since 1970 and as an ISO-8601 UTC stamp | integer, text |
  | `kind:` / `target:` | `message`, `correction` or `deletion`; the id an edit changes, or empty | text |
  | `signature:` | the signature, read by 214's rule | text |
  | (blank line, then) | the text exactly as written | text |

  Per-home facts — `from` and `arrived` — stay in the log only.
- **Layout**: `rooms/<room fingerprint>/<written>-<id>.txt`, the room
  folder named by the token fingerprint (64 hex; the same on every home,
  unlike the local tag, and revealing nothing without the token).  A
  per-home `labels` file outside the tracked tree maps fingerprints to the
  reader's own labels, for people reading the working tree (labels are
  never sent, planning section 2).
- **Edits are commits.**  A correction received rewrites the target's copy;
  a deletion removes it; both are committed, so history keeps every
  version.  The person may edit or delete any copy by hand ("encourage
  changes and deletions"); those edits are committed at the next sync and
  are **not** sent to anyone — they reach others only through a shared
  upstream (215b).
- **Committed every sync cycle** (211): one commit per cycle for the rooms
  that changed, its message listing how many copies were added, changed
  and removed.
- **The running source code** is also in the repository, on a branch of its
  own (`code/<home name>`): at start-up the starter commits the program
  folder it is running from, if it changed.  The owner: "the git
  repository should also have the source-code that the user is running,
  potentially in their own branch".  Nothing is ever checked out from it.
- **git is required**: a gatherer that cannot find it stops with an error
  naming the missing program, rather than running without copies.

## Rubric

The neighbour for this issue is git itself, read as a rubric, and rmail's
rules where they reach.

- **Two copies agree only if they are made of the same bytes** (git's
  content addressing): anything per-home in a shared file makes every
  message a conflict.  Hence the agreed part — the same rule 209's
  fingerprints follow.
- **Names from the network never become paths without cleaning**
  (structure R14; rmail's 2026-02-16 escape): file names here are built
  only from hex ids, hex fingerprints and integers.
- **Write only the fields that belong on disk** (structure R15): each line
  is written from a named field, never from a whole table.
- **A code error in one piece of work ends that piece only** (structure
  R5): a failing hook does not stop filing.
- **Refuse to start rather than fall back** (rmail refuses without its
  change watchers or `zip`; the house rule: errors over fallbacks).
- **A git commit costs a process start**; one commit per sync cycle, not
  per message, keeps a busy room from forking git hundreds of times a
  minute.

## Where we differ

rmail's inbox is one file per message and its history is whatever the
disk holds.  The formation here is **git as the reading copy, the log as
the record, one-way**: the log feeds the copy; the copy never feeds the
log.  The person gets free editing, diffing, blame and history with tools
they already have, and nothing they do there can corrupt delivery.

- **Gains:** "record changes, encourage changes and deletions" without
  touching the append-only log; members' copies are mergeable because
  they hold only agreed bytes; any git viewer is a history browser.
- **Costs:** two stores of every message; a person's hand edit is later
  overwritten if a correction for the same message arrives (history keeps
  both, open question 3); git becomes a dependency of the server.

## Referees

1. **Two homes, one copy.**  Two homes hold one room; the same message
   filed on both gives byte-identical copies at the same path.  *Broken:*
   `arrived` or `from` in the copy; the local tag as folder name.
2. **Every filed record gets a copy**, own messages included; after a sync
   cycle, `git log` has one commit covering them.  *Broken:* a hook only on
   receive, missing own messages.
3. **Edits are history.**  A correction then a deletion: the working tree
   lacks the file; `git log --follow` shows three versions.
4. **The log is untouched by hand edits.**  Edit and delete copies by hand;
   after sync, every room's log is byte-identical to before and nothing was
   sent.  *Broken:* a watcher that turns copy edits into corrections.
5. **A failing hook does not stop filing.**  A hook that throws: the record
   is still filed and acknowledged; one problem line; the copy appears at
   the next sync.
6. **Hostile ids stay inside.**  A record whose id is not 32 hex is refused
   by 105 before any path is built; no file appears outside `rooms/`.
7. **No git, no start.**  With git absent from the path, the gatherer exits
   naming it.

## Suggested Implementation Steps

1. The hook point in the filer, and the built-in text-copy hook.
2. The agreed-part writer (shared with 209's fingerprint) and 214's
   signature reader.
3. Making the repository with the mailbox; the layout and `labels`.
4. Committing at the sync cycle; rewriting copies from the log after a
   failed hook.
5. The `code/<home name>` branch at start-up.
6. The referees above.

## Blockers that are not the owner's

- Needs 105 (records), 211 (the filer and sync cycle), 214 (signatures).

## Open questions

1. **Where the repositories live**: `rao-home/git/<mailbox tag>/`
   (proposed) or wherever the person points "where to store the
   mailboxes"?
2. **Custom hooks**: may the person add their own hook scripts (a folder
   of programs run on each filed record)?  If so, rmail's extra licence
   permission for hook scripts was deliberately not carried over — does
   rao-chat want one?
3. **A hand edit, then a correction for the same message arrives**: the
   copy is rewritten (proposed, history keeps the hand edit), or the hand
   edit wins and the correction is written beside it?
4. **Commit author**: the home's name, a fixed `rao-chat`, or config?  A
   pushed author name says who ran the home.
5. **The room folder named by fingerprint**: confirm (the local tag differs
   per home; the label is private).
6. *(answered 2026-09-27)* **One repository per mailbox** (owner: "each
   mailbox gets a git repository"), the log staying the delivery record
   (owner's reading (b)).

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/git-copies/` (172 running git, 173 the text copies, 174
settings, 175 the referees), with 214's reader in `src/signature/`
(169–171), and changes to 211's gatherer (163: git required, the filing
hook, a commit each sync cycle) and starter (164: the code branch).  175
passes 8 of 8 checks against real gatherers on 127.0.0.2 and .3 inside
`unshare -rn` and the copies module on a home on disk; every broken
version the referees name is caught.

1. **Where the repositories live** (open question 1): as proposed,
   `rao-home/git/<mailbox tag>/`, beside `rooms/`.  Undo: one function
   (173's `repository`).
2. **Custom hooks** (open question 2): not built.  The hook point is a
   function in the gatherer with one built-in hook (the text copy); a
   folder of the person's own programs, and whether rao-chat wants rmail's
   extra licence permission for them, stay the owner's.  Undo: nothing to
   undo; adding the folder is a loop in `run_hooks`.
3. **A hand edit, then a correction** (open question 3): as proposed, the
   copy is rewritten and history keeps the hand edit.  Undo: one branch
   in 173's `apply`.
4. **Commit author** (open question 4): a new setting, `git.home-name`,
   with no default (174), which also names `code/<name>` (and 215a's
   `running-log/<name>`).  Author and committer are `<name>
   <name@rao-chat.invalid>`: `.invalid` never routes, and a pushed author
   says only the name the person chose.  Every home that runs a gatherer
   needs the line; the demo and the tests set it.  Undo: one setting.
5. **The room folder named by fingerprint** (open question 5): confirmed,
   the 64-hex token fingerprint (007).  A room whose token changes writes
   its later copies under the new fingerprint; older copies stay in the
   old folder (not moved: left).
6. **The `signature:` line needed 214, which was not built**: 214's steps
   1 and 2 are built with this issue (169, the reader; 170, the table of
   examples; 171, its referees), its open questions 1–4 answered as
   proposed there (see 214's decisions).  Step 3, the viewer's field,
   waits on 301.
7. **What a corrected copy says**: the copy keeps its message's path for
   life; after a correction it holds the latest correction's agreed part
   (its id and written time, `kind: correction`, `target:` the message),
   chosen by 086's order (written time, then id), so every home writes
   the same bytes whatever order corrections arrived in.  A deletion
   removes the file.
8. **When the repository is made**: at the gatherer's start (and the
   starter's, before it starts a mailbox's gatherer), when it is not
   there, rather than inside 101's `make_mailbox`.  A mailbox gets
   messages only through a gatherer, so no message is missed, and phase
   1's code and tests stay free of git.  This differs from the issue's
   wording ("made when the mailbox is made"); the effect is the same for
   every message.  Undo: call 172's `ensure` from `make_mailbox`.
9. **How the hook and the sync share the work**: each room's copies
   carry an offset into its log (`.git/rao-copies`, never tracked).  The
   hook (after a frame is answered, so it never delays an
   acknowledgement; and after an own message is written) and each sync
   cycle both apply the records after the offset, in log order.  So a
   failed hook is made good from the log at the next sync, and a record is
   never applied twice (a hand edit made since is not written over).
   Offsets are saved after each commit; a gatherer that dies between
   syncs re-applies the records since the last commit, which rewrites
   identical bytes.
10. **One commit covers the whole working tree**, not only `rooms/`: a
    file the person adds to the repository is committed too (the
    commit's message counts it as "other").  `labels` is left out by
    `.git/info/exclude`.
11. **git runs apart from the machine's settings**: no system or global
    config, hooks off, no pager, no signing, no password prompt (172).  A
    person's own `commit.gpgsign` or template hooks cannot change or stop
    a sync, and nothing in a repository runs a program.
12. **Referee 6's wording**: the issue says a record whose id "is not 32
    hex" is refused by 105, but 105 accepts ids from other homes made of
    letters, digits, `-` and `_` of any length (082: ids from elsewhere
    are not required to be 32 hex).  Built to 105's rule: those ids are
    path-safe (no `/`, no `.`), and the copies refuse anything else, and
    any id over 128 characters, before a path is built.  An id over 128
    is filed by 105 but gets no copy (a problem line).
13. **The code branch**: committed by the starter before a mailbox's
    gatherer first starts, from the folder it runs from, with that
    folder's own `.gitignore` applied (so `tmp/` with the demo's homes
    is left out), through an index of its own; nothing is checked out.
    Its commit message names no path (a path can name the person's
    account).
14. **Sync cost**: the commit runs in the sync thread, two process starts
    per cycle that changed something (`git add -A` and `git diff`, then
    `commit`) and one per cycle that did not.  The issue's rubric already
    chose one commit per cycle over one per message.

## Related documents

- `notes/vision-planning.md` section 15 ("The server's shape, the outside
  port, and rooms as git history"; "Key-tying, the log and git";
  "Git per mailbox, signatures settled, sharing edits")
- `notes/rmail-rubric/structure-and-defences.md` (R5, R14, R15)
