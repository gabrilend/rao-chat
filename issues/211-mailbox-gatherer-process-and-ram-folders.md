# 211 — The mailbox gatherer: one process per mailbox, working in RAM folders

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 101, 105, 201
**Blocks:** 202, 203, 204, 212, 213, 215, 215a, 210, 301

## Current Behavior

Nothing exists.  Phase 1 keeps everything on disk in one home folder
(`rao-home/`: `config`, `mailboxes`, `ignore`, `rooms/<local tag>/…`,
`people/`), read and written by five modules in one program, which
share one in-process change bell (`docs/phase-1-module-contract.md`).
Every mailbox is already listed with its own listening port in
`rao-home/mailboxes`, and every room names its mailbox.

## Intended Behavior

The owner (2026-09-27):

> yes we want to have one mailbox per "server". the config and ignore list
> can be managed in one collected UI - they'll each report to the RAM
> directories as detailed in shape C. Many data gatherers, one viewer,
> which is the android app or HTML page, both simply viewers for the rmail
> inboxes located in RAM, pulled from disk by the gatherers at startup,
> and synced periodically. The user types, and it creates messages and
> puts them in the right place - the user never needs to touch the
> filesystem at all, except for pointing out where to store the mailboxes.

- **One gatherer process per mailbox** (one per top-level room tree, one
  for all direct messages).  It holds that mailbox's listening port, that
  mailbox's rooms and keys, its own retry timers and its own logs, and
  nothing of any other mailbox's.
- **A home starter** (one small process per home) reads `rao-home/mailboxes`,
  starts one gatherer per mailbox, restarts one that dies (saying so), and
  runs the home-wide tasks that belong to no mailbox (the public-address
  recheck, 212).  It does nothing else.
- **At start-up a gatherer loads its mailbox from disk into RAM** and from
  then on works in RAM.  **Every sync cycle** (config
  `gatherer.sync-interval`, whole seconds, no default) it writes what
  changed back to disk and commits to the mailbox's git repository (215,
  215a).  At shut-down it syncs once more.
- **The RAM folder of one mailbox** (under config `gatherer.ram-root`, an
  absolute path written into config when a home is made, e.g. on
  `/dev/shm`; one folder per home, then one per mailbox tag):

  | path | what it holds | written by → read by |
  |---|---|---|
  | `home/` | a rao-home-shaped copy: `config`, `mailboxes`, `ignore` (read-only copies of the home-wide files) and `rooms/<local tag>/` for this mailbox's rooms only | loaded at start-up; phase 1's modules run on it unchanged, passed `{ dir = <this path> }` |
  | `arrived/` | one file per frame read off the port: mailbox tag (string, 32 hex), source address (string), source port (integer), arrival time (integer seconds since 1970), frame bytes (binary) | listener → openers |
  | `opened/` | one file per opened frame: room local tag (string), inner record (201's shape), the `arrived/` name it came from | openers → filer |
  | `answers/` | one file per acknowledgement ready to send back, named after its `arrived/` file | filer → listener |
  | `typed/` | one file per message the person typed, in rmail's outbox-file shape (301) | viewer → filer |
  | `due/` | one file per (address, port) pair with something to send (202) | filer → sender |
  | `inbox/` | the viewer's copy of each room (301) | filer → viewer |
  | `running-log` | the gatherer's own log lines | every stage → git (215a) |
  | `failed-decryption` | 203's lines | openers → fail2ban |
  | `state` | small facts as `name = value` lines: process id (integer), started (integer seconds), last sync (integer seconds), each folder's pile size (integer) | gatherer → viewer, demo |

- **Every hand-off is a file written under a temporary name and renamed
  into place**, so a stage never reads half a file; a stage takes a file
  by renaming it into its own `working/` folder, so two workers never take
  the same one; at start-up anything left in a `working/` folder goes back
  to its queue.
- **The stages** (the note's shape C, one pipeline per mailbox):
  1. **listener** — claims the port, reads bounded frames (201's length
     check, a read deadline), writes each to `arrived/`, and holds the
     connection open until `answers/` has its answer, which it sends on the
     same connection (the only route back: the sender is unknowable and its
     source port is a throwaway number);
  2. **openers** — a pool of workers trying the mailbox's keyring (201,
     201a); a failure writes 203's line and drops the frame; a success
     writes `opened/`;
  3. **filer** — the only writer to `home/`: files through phase 1's
     modules (105's `append`, 103's `heard_from`, …), writes `inbox/`,
     runs the filing hooks (215), marks what is due (202), and writes the
     answer to `answers/` — after the write chosen by
     `gatherer.acknowledge-after` (below);
  4. **sender** — takes `due/` pairs and delivers (202), never blocking
     the other stages.
- **Write before acknowledging — still open, built both ways**, config
  `gatherer.acknowledge-after` (no default):
  - `disk`: the record is appended to the disk copy of the room's log and
    forced to disk before the answer is written (slower; nothing
    acknowledged is ever lost);
  - `ram`: the answer is written once the record is filed in RAM; disk
    catches up at the next sync cycle (a gatherer crash loses nothing,
    because RAM files outlive the process; a power cut loses what arrived
    since the last sync, and those senders believe it delivered).
- **Home-wide files** (`config`, `ignore`, `mailboxes`) are changed by the
  viewer on disk; each gatherer reloads its read-only copies at its next
  sync cycle and says so in its running log.
- **Problems that belong to no room** (a port that cannot be claimed, a
  pile that keeps growing) are written to the running log and to `state`,
  one line per distinct problem rewritten in place, never appended per
  cycle.

## Rubric

From `notes/rmail-rubric/structure-and-defences.md` section 2 (R-numbers
there) and `delivery-and-retries.md` (D-numbers).

- **Acknowledge on the connection the frame came in on, and only after it
  is filed** (R1, D-R3).  The sender forgets a message on hearing "filed";
  an answer before the write followed by a crash loses it with no one
  holding it as undelivered.  Which write counts ("filed") is the open
  switch above.
- **Bound everything an unauthenticated peer can make the server hold**
  (R2): frame length, read time, open connections, bytes buffered.  rmail
  has no connection limit.
- **One slow or dead peer never delays another peer or the listening
  side** (R4, D-R6).  rmail's inline sync cycle held its whole loop for
  8-second batches; two daemons dialling each other filed one message eight
  times (delivery note, E1).  Here the sender is its own stage.
- **A code error ends one piece of work; the clocks still move** (R5,
  D-R9).  One bad record in rmail spun the loop: 1,091,617 identical lines.
- **The server's own writes do not wake it** (R6).  The change bell is
  in-process, so each gatherer's bell hears only that gatherer's writes.
- **Every periodic task is on the wake-up clock** (R8): sync cycles,
  retries, summaries, rechecks.  rmail's address check ran only at
  start-up and went 46 days stale.
- **Claim the listening port first, before anything slow; say so where
  the person looks, named by the problem** (R9).
- **No default port, no default anything** (R10) — already rao-chat's:
  every setting above is declared (phase 1 round 4) and has no default.
- **Every repeated condition writes a bounded amount** (R16): problems are
  rewritten in place.
- **One home per service; everything per home named by its path** (R20):
  the RAM root is per home, so three homes on one machine (210) share
  nothing.
- **Record "the other side has it" per item as it confirms** (R21), not at
  the end of a batch.
- **A fresh random nonce per frame from the operating system**, including
  in every worker of the opener pool (R12): a worker forked after seeding
  one generator repeats its parent's numbers.
- **LuaJIT's limits** (R18: 60 upvalues, 200 locals per function) and the
  descriptor ceiling of `select` (R19) — one process per mailbox keeps each
  process far below it.

## Where we differ

rmail is one process per mailbox with one thread: one wait loop runs
incoming connections as coroutines and the sync cycle inline.  rao-chat
keeps "one process per mailbox" (the note's shape B) but **splits the
process into a pipeline joined by RAM folders** (shape C), and adds the
formation this issue tries: **the RAM copy is itself a rao-home**, so
phase 1's five modules run on it unchanged — the gatherer passes them a
home whose `dir` is in RAM, and disk is only reached by the sync cycle.

- **Gains:** each stuck stage is a growing folder anyone can `ls` (the
  demo can show pile sizes); one writer to `home/` means no locks; a
  mailbox that crashes or floods cannot touch another; trial opening is
  split across cores by the mailbox boundary for free; phase 1 needs no
  second implementation; disk writes are batched.
- **Costs:** more processes to supervise; an answer waits on three
  hand-offs; each folder is untrusted input to the next stage and needs its
  own format checks; home-wide files now live in several copies that must
  be reloaded; a hand edit made to the disk home while a gatherer runs is
  overwritten at the next sync (open question 3); the power-cut window of
  `ram` is real.

## Referees

From the rules above (structure note, section 5, rewritten for this shape).

1. **Crash between filing and answering** (R1).  Kill the gatherer at
   random points between reading a frame and answering; restart.  Every
   message is filed exactly once and the sender stops only after a real
   answer — under both `disk` and `ram`.  *Broken:* a filer that answers
   before filing.
2. **Power cut** (the switch).  Discard the RAM folder (as a reboot would)
   right after an answer: under `disk` the message is in the disk log;
   under `ram` it may be missing, and the referee reports how many — the
   measured cost of the choice.  *Broken:* `disk` that answers before
   forcing the write.
3. **Held connections are bounded** (R2).  500 connections each announcing
   the maximum length and trickling a byte a second: memory stays under a
   stated bound and a genuine frame on connection 501 is filed within 2 s.
   *Broken:* no connection limit.
4. **A dead peer delays nobody** (R4).  One member address black-holed: a
   message reaches every other member within 1 s and an inbound frame
   arriving meanwhile is answered within 1 s.  *Broken:* a sender inside
   the listener's loop.
5. **A throwing record** (R5).  A room whose filing throws: other rooms
   keep receiving; one running-log entry per ordinary cadence; wake-ups
   per minute stay bounded.  *Broken:* a guard that skips the clock step.
6. **Half-written files are never read.**  A stage stand-in that writes
   hand-off files slowly, byte by byte: the next stage never reads one
   before its rename.  Two openers never take one file.  *Broken:* writing
   in place; taking by reading.
7. **Port first** (R9).  A mailbox port already held by another program:
   that gatherer exits within 1 s, names the port and its `mailboxes` line
   in `state` and the running log, and made no outbound connection first.
   *Broken:* announcing before binding; choosing another port.
8. **Homes apart** (R20).  Three homes on one machine: no two share a RAM
   folder, running log, failed-decryption file or process id file.
   *Broken:* a fixed `/tmp/rao-chat.log`.
9. **Phase 1 runs on RAM.**  Phase 1's own test runners, pointed at a
   RAM-loaded home, pass unchanged; after a sync cycle the disk home equals
   the RAM home file for file.  *Broken:* a sync that misses a rewritten
   `entry`.

## Suggested Implementation Steps

1. The RAM layout and its hand-off rules (write, rename, take, return at
   start-up), with the format check each stage runs on what it takes.
2. Load at start-up (disk → RAM) and the sync cycle (RAM → disk, only what
   changed), with `gatherer.sync-interval` and `gatherer.ram-root`
   declared in this module's settings list.
3. The listener: port claim first, bounded reads, held connections, the
   answer path.
4. The opener pool around 201's trial opening.
5. The filer around phase 1's modules, with both `gatherer.acknowledge-after`
   variants and their options entry for the tally.
6. The sender stage's shell (202 fills it).
7. The home starter: one gatherer per mailbox, restarts, home-wide tasks.
8. The referees above.

## Blockers that are not the owner's

- Needs 101 (the mailboxes file, the settings check), 105 (filing), 201
  (opening).  202 fills the sender; 215/215a hang the git work on the sync
  cycle.

## Open questions

1. **Write before acknowledging** (still open, built both ways): `disk`
   or `ram`?  Owner (2026-09-27): "Still open: write a message to disk
   before acknowledging it, or accept losing the last few seconds before a
   power cut."
2. **Stages as coroutines inside the gatherer, or as child processes?**
   The owner named one process per mailbox; shape C allowed either.
   Leaning: listener, filer and sender as coroutines under one wait; the
   openers as a small pool of worker processes (the only CPU-heavy stage).
3. **Hand edits to the disk home while a gatherer runs** are overwritten
   at the next sync.  The owner: "the user never needs to touch the
   filesystem at all".  Refuse them (the sync notices a disk file changed
   since load and stops with an error), or let the disk win?  (Rubric
   question 25.)
4. **Is writing a line into a room's log by hand a way to send?**  Read as
   no from "the user types, and it creates messages" — to confirm.
   (Rubric question 33.)
5. **A mailbox port that cannot be claimed**: stop only that gatherer
   (the shape makes this natural) or the whole home?  (Rubric question 26.)
6. **A limit on open connections per gatherer**, as a setting — and does
   it count as the "flood defence of its own" that 203 rules out?  (Rubric
   question 27.)
7. **Where problems belonging to no room are shown**: `state` and the
   running log (proposed), and the viewer's error strip (301)?  (Rubric
   question 28.)
8. **Waiting for a frame's pieces**: a deadline per read (rmail's 10 s)
   or one deadline for the whole frame?  (Rubric question 12.)
9. **The RAM root's default in the home-making tool**: `/dev/shm/rao-chat/<home
   name>` written into config at making, as the log-file size is?
10. *(answered 2026-09-27)* **The server's shape.**  One gatherer per
    mailbox, RAM folders, one viewer (owner's words above).
11. *(to confirm)* **One program or two** (planning question 7): the
    gatherer is rao-chat's own program, not rmail's daemon.

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/gatherer/` (161 RAM folders, 162 the wait loop, 163 the
gatherer, 164 the home starter, 165 settings, 166 options, 167 the
referees, 168 loopback for the demo), with two changes to 202's code:
133's `answer_frame` (one frame's work, apart from the connection) with
an `on_filed` seam, and 134's `pass(now, run)`.  167 passes 13 of 13
checks against real processes on 127.0.0.2 to .4 inside `unshare -rn`,
each referee that names a broken version catching it.

1. **Write before acknowledging** (open question 1): built both ways,
   still the owner's.  `gatherer.acknowledge-after` has no default; the
   first variant, which demo homes start with, is `disk`.  Measured
   (referee 2 and the demo's acknowledge scene): with the RAM folder
   discarded right after 10 answers, `disk` lost 0 and `ram` lost 10; on
   loopback both answered all 10 in under a second.  Undo: none needed,
   the setting chooses.
2. **Stages** (open question 2): coroutines under one wait loop (162) in
   the one process per mailbox, for the listener, each held connection,
   the filer, the typed stage, the sender (each due item a thread of its
   own) and the sync cycle.  No opener pool: opening is 201's trial
   opening, cheap next to the network for a handful of keys, so opening
   and filing are one stage and there is no `opened/` folder.  Undo: the
   filer already takes `arrived/` files one at a time by rename, so a pool
   of processes taking from the same folder can be added without
   changing the folders.
3. **Hand edits to the disk home while a gatherer runs** (open question
   3): refused.  The sync compares each disk file with what it last
   loaded or wrote; one changed since is left as it is, not written over,
   and named in `state` (`problem.hand-edit`) and the running log.
   Home-wide files (the plain files at the top of the home: `config`,
   `mailboxes`, `ignore` and the like) go the other way: disk wins,
   reloaded into RAM at each sync.  Undo: one
   branch in 161's `sync_file`.
4. **A line written into a room's log by hand** (open question 4): not a
   way to send.  Sending is a file in `typed/` (`room = <tag>`, a blank
   line, the text), which the gatherer writes through 202's stage; a hand
   edit to the log is refused as in 3.  Undo: none needed.
5. **A port that cannot be claimed** (open question 5): only that
   gatherer stops.  It claims its port before anything else, names the
   port and its `mailboxes` line in `state` and the running log, makes no
   connection, and exits within 1 s.  The starter starts it again,
   waiting twice as long each time it dies within 5 s, up to 60 s, so a
   port freed later is taken without a loop that fights for it.  Undo:
   have the starter stop the home on that exit status.
6. **A connection limit** (open question 6): a setting,
   `gatherer.connection-limit`, first variant 64; a new connection past it
   closes the one held longest.  It is a bound on what one peer can make
   the gatherer hold, applied to everyone alike, not a ban on an address,
   so it is not the flood defence 203 rules out.  Referee 3, with 500
   connections trickling a byte a second: at most 64 held, a genuine
   frame on connection 501 filed in 0.35 s, about 13 MB of memory.
   Undo: the setting.
7. **Problems that belong to no room** (open question 7): `state` (one
   `problem.<name>` line each, rewritten in place) and the running log
   (at most once per sync interval each, with a count).  The viewer's
   error strip is 301's.
8. **Waiting for a frame's pieces** (open question 8): one deadline for
   the whole frame, `gatherer.frame-deadline`, first variant 10 s.  A
   peer trickling a byte a second is closed after 10 s however many bytes
   it sends; a per-read deadline would hold it forever.  Undo: the
   setting, or a per-read deadline in 162's `receive`.
9. **The RAM root** (open question 9): the setting `gatherer.ram-root`,
   first variant `/dev/shm/rao-chat`.  Each home gets
   `<home folder's name>-<12 hex of its path's SHA-256>` under it, so
   homes sharing a machine share nothing (referee 8).  Where the root
   cannot be written, `/tmp/rao-chat-ram` is used and the starter says so
   in `state` and the running log.  There is no home-making tool yet to
   write it at making; the demo and tests write the first variants.
10. **One program** (open question 11): confirmed; the gatherer is
    rao-chat's own program (LuaJIT, LuaSocket), not rmail's daemon.
11. **`due/` is a written view, not a queue.**  202's stage keeps its jobs
    in memory and its truth in each room's `delivered` file; `due/` holds
    one file per (pair, room) still owed something (room, address, port,
    how many missing, next try), rewritten after each pass and each
    attempt, so anyone can `ls` the pile.  Nothing reads it back.
12. **A crash loses nothing in RAM.**  A gatherer started again keeps the
    RAM home a previous process loaded (marked `.loaded`) instead of
    reloading from disk, and puts back what was in `working/`.  Only a
    reboot (the RAM folder gone) reloads from disk.
13. **Hellos only once the address is known.**  The stage is given
    `own_pairs` only when 212's fact exists in the home's RAM folder;
    until the starter's first confirmed lookup, the gatherer sends no
    hello, and the starter restarts every gatherer when one is confirmed
    or moves.
14. **Ports are claimed with `tcp4`/`tcp6` sockets** and `reuseaddr`, so a
    gatherer started again after a crash takes its port back at once.
15. **Referee 1 under `ram`** crashes the gatherer at the two points the
    referee names (after filing before answering, and after answering)
    and checks each message is filed once; the broken filer (answers
    first) loses one, and is caught.
16. **Not wired here:** the old port kept served after a merge (205's
    referee 7) needs the merge to leave a line naming the old port and
    the members still to call back; the gatherer for that port can then
    be kept by the starter until the line is empty.  213's housemate
    datagrams need a UDP socket in the gatherer.  `inbox/` for the viewer
    is 301's.  Each is left for its issue.

## Related documents

- `notes/vision-planning.md` section 15 ("The server's shape, the outside port, and rooms as git history")
- `notes/rmail-rubric/structure-and-defences.md` (shapes B and C)
- `notes/rmail-rubric/delivery-and-retries.md` (F2)
- `docs/phase-1-module-contract.md`
