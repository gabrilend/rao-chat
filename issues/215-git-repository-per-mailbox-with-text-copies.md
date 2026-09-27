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

## Related documents

- `notes/vision-planning.md` section 15 ("The server's shape, the outside
  port, and rooms as git history"; "Key-tying, the log and git";
  "Git per mailbox, signatures settled, sharing edits")
- `notes/rmail-rubric/structure-and-defences.md` (R5, R14, R15)
