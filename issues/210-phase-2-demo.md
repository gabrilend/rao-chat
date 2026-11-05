# 210 — Phase 2 demo: three homes talking

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 201a, 202, 203, 204, 205, 207, 208, 209, 211, 212, 213, 214, 215, 215a, 215b

## Current Behavior

Nothing exists.  Phase 1's demo (106) builds homes on disk, runs every
listed variant of the keys its scenes are about, reads `input/` first and
writes a goodbye into `output/` last; its harness is reused here.

## Intended Behavior

`issues/completed/demos/phase-2-demo`, found by `run-phase-demo 2`, runs
three or more homes on one machine, each with its own `rao-home/` and its
own RAM root under `tmp/shared-memory/`, each gatherer of each home a real
process, and shows figures and real outputs rather than descriptions:

- a message delivered to every pair at once, with acknowledgement times,
  and a member with two pairs receiving at both;
- a member down, the pile growing in its gatherer's `due/` folder (the
  pile size read from `state`), and delivery when it returns;
- joining with a token and one pair, the call-back confirming it, and a
  direct message between two homes, sealed and filed the same way;
- two rooms with one label told apart by their tokens, and the count of
  keys tried per frame with the key-tying early stop;
- a child room flagging an outsider of its parent, cleared by approving;
- contact syncing reaching a newcomer by digest then list; an ignored
  address refused; a replayed list not re-adding a leaver;
- a token changed by hand and given out through direct messages, history
  kept;
- a genuine leave and a forged one;
- a two-faced sender caught by the cross-check, and a gap filled with the
  original id;
- the failed-decryption files after garbage is sent, with `fail2ban-regex`
  matching them;
- a signature table: messages and the signature each shows;
- each mailbox's git repository: `git log` of text copies, a hand edit
  committed and not sent, the running log's numbered files, and two homes
  sharing a local bare upstream — pull and push at start-up, a triggered
  recheck and shut-down;
- the `gatherer.acknowledge-after` switch run both ways, with the count of
  acknowledged messages lost when the RAM folder is discarded;
- phase 1's tools reused: `people/`, the tree of child rooms, the tally.

## Rubric

- **Three homes on one machine must be three homes to the network**
  (structure note section 4): each listens on **and sends from** its own
  loopback address (127.0.0.2, .3, .4 — Linux accepts all of 127.0.0.0/8),
  or every frame appears to come from one address and neither the
  call-back check nor the ignore list can be shown working.
- **Nothing shared between homes** (structure R20): logs, RAM roots,
  failed-decryption files, process ids.
- **No default ports** (structure R10): every home's config states its
  ports.
- **A demo shows real outputs** (house rule): figures read from the
  running system, not text about it.

## Where we differ

Phase 1's demo ran scenes inside one Lua program.  This demo's formation is
**the demo as an observer of running processes**: it starts homes, drives
them only through what a viewer can do (writing `typed/` files, changing
config) and what the network carries, and reads results from the RAM
folders and git — the same interface phase 3's viewers will use.

- **Gains:** the demo exercises the real process boundaries; it doubles as
  an early check of 301's viewer interface.
- **Costs:** slower and more timing-dependent than in-process scenes; each
  scene needs a wait-for-condition with a deadline, not a sleep.

## Referees

The demo is itself graded by the issues' referees; its own check is that
every scene reports a figure read from a running home, and that a scene
that cannot run says why (as 106's could-not reports do).

## Suggested Implementation Steps

1. Starting homes on their own loopback addresses and stated ports; the
   RAM roots under `tmp/shared-memory/`.
2. One scene per behaviour above, each waiting on conditions with
   deadlines.
3. The bash wrapper in `issues/completed/demos/`.

## Blockers that are not the owner's

- Needs every other phase 2 issue.

## Open questions

1. **Ports**: fixed ports written into each demo home's config, or free
   ones asked of the system and then written in?  (Rubric question 36.)
2. **Loopback addresses** 127.0.0.2, .3, .4 per home: confirm.  (Rubric
   question 36.)
3. **fail2ban in the demo**: required (the scene stops with a reason if
   `fail2ban-regex` is missing) or the scene skipped with a notice?

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/phase-2-demo/` (158 the program, 159 the scenes, 160 the
referee) with the wrapper `issues/completed/demos/phase-2-demo`, which
`run-phase-demo 2` finds.  Run where this was built: 10 of 15 scenes ran
in full, 2 ran with a part missing, 3 wait on an issue, none failed (exit
status 2).  160 passes 47 of 47 checks, including two broken versions.

1. **Ports** (open question 1): fixed, one per home, written in each
   home's own mailboxes file (A 7602, B 7603, C 7604; the direct
   mailboxes 7612, 7613, 7616).  The same numbers every run make the
   output comparable between runs, and in the demo's own network
   namespace nothing else holds them.  Undo: when 211's gatherers listen
   for real, ask the system for free ports and write those in; only the
   helpers that make homes change.
2. **Loopback addresses** (open question 2): confirmed, 127.0.0.2, .3 and
   .4, each home listening on and sending from its own (.5 for C's second
   pair, .6 for a joiner).  One limit found: 207 never puts a loopback
   pair in a member list, so between loopback homes a newcomer is reached
   only by call-back, never by a list.  The child and syncing scenes
   therefore use 198.51.100.2, .3, .4 (documentation addresses, never
   routed) for their homes, and the syncing scene first prints the
   loopback homes' list coming out empty.  When 211 makes the homes real
   processes, the same addresses can be added to the namespace's own
   loopback device (`ip addr add 198.51.100.2/32 dev lo` inside
   `unshare -rn`), which touches no real network.  Making 207 list
   loopback pairs for the demo was not done: it would weaken a rule to
   make a demo pass.  Undo: change the addresses in 159.
3. **fail2ban** (open question 3): neither a stop nor a silent skip.  The
   scene runs `fail2ban-regex` with the shipped filter when it is
   installed.  When it is not (as where this was built), the scene still
   shows the files and the filter's failregex applied by the same Python
   stand-in 140's referee uses, prints "PART NOT RUN" naming
   `fail2ban-regex`, and the demo exits 2, not 0.  Undo: make the gap a
   failure in 158 (one line).
4. **In-process until 211** ("Where we differ"): the gatherer process is
   211's and is not built, so there is no process to start or watch.  The
   stages run as threads of the demo program in 143's simulated world (a
   clock of its own and an in-memory relay that records who connected
   from where), on real rao-homes on disk, each with its own RAM folder.
   Times printed are that clock's and say so.  Undo: when 211 lands,
   replace the home-making helpers with starting gatherers and waiting on
   their RAM folders; each scene's figures stay the same.
5. **What is not built is said, not shown:** the signature table (214),
   the git repositories (215, 215a, 215b) and the
   `gatherer.acknowledge-after` switch (211) print "WAITS" with the issue;
   the down scene's pile in the gatherer's `due/` folder is named as a
   part not run (211).  Nothing is faked.
6. **Exit status:** 0 when every scene ran in full, 1 when any scene
   could not run, 2 when none failed but some wait or miss a part.  The
   goodbye in `output/` carries the same four counts.
7. **Its own network namespace:** the wrapper runs the program under
   `unshare -rn` when the system allows it, and otherwise says so on
   stderr and runs it anyway; the demo opens no sockets either way.
8. **The test world is 143's**, the one the delivery tests use, with its
   scratch folder `tmp/shared-memory/phase-2-demo/`, cleared at the start
   of each run and left afterwards for looking at.
9. **Two rooms with one label share a mailbox:** the keys scene makes a
   room and four children (two labelled "kitchen"), so all five keys are
   in one keyring on one port, and each frame stops at a different key
   (1 to 5 tried).  Five top rooms would each start a mailbox on the
   shared port, which phase 1 warns about.
10. **The referee (160)** runs the demo through `run-phase-demo 2` and
    checks a figure from each scene, the waiting scenes' issues, and the
    counts against the exit status.  It catches a scene made to fail
    (`RAO_PHASE2_DEMO_BREAK`, which only the referee sets) and a project
    copy missing 156.

## Related documents

- `run-phase-demo`; issue 106 (phase 1's demo, whose harness it reuses)
- `notes/rmail-rubric/structure-and-defences.md` (section 4, "Three homes
  on one machine")
