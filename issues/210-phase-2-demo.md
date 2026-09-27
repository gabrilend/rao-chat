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

## Related documents

- `run-phase-demo`; issue 106 (phase 1's demo, whose harness it reuses)
- `notes/rmail-rubric/structure-and-defences.md` (section 4, "Three homes
  on one machine")
