# 106 — Phase 1 demo, and the options tally

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101, 102, 103, 103a, 104, 105
**Module folders:** `src/phase-1-demo/`, `scripts/`,
`issues/completed/demos/` (indexes 100–119)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Both halves exist and run against the round-3 modules (mailboxes, flags
instead of refusals, answered choices fixed).  On 2026-09-25, after 104's
bell listener was fixed to accept 101's new bell kind `mailbox`, the demo
showed 10 of 10 scenes on the real 101, 102, 103, 103a, 104 and 105
(`run-phase-demo 1` exits 0), and 281 of 281 checks pass
(`luajit src/phase-1-demo/tests/118-run-tests.lua`).  No stand-in config
keys were needed: every key a module reads is in some options file.

- **The options tally**, `scripts/tally-options [project folder] [--walk]
  [--no-pause]`: gathering (`src/phase-1-demo/100-gather-options.lua`)
  kept apart from showing (`101-show-options.lua`).  It reads every live
  `src/<module>/<3 digits>-options.lua` and never a retired
  `-options.lua-done` (checked on a sample, and on the real project by
  comparing its count with `find`: 6 files).  On 2026-09-25 (round 3) it
  read 31 choices, 24 waiting on the owner and 7 on some other state.
- **The demo**, `issues/completed/demos/phase-1-demo` (bash) running
  `src/phase-1-demo/106-phase-1-demo.lua`: input/ read first; every
  config key set to its first-listed variant unless
  `input/phase-1-demo.config` names another (11 keys on 2026-09-25, down
  from 16 as answered choices left the options files); each scene in its
  own scratch home under `tmp/shared-memory/phase-1-demo/`; a ran /
  could-not table with the reason; `output/phase-1-demo.goodbye` written
  last.  All seven module files (002, 021, 024, 041, 042, 061, 081) are
  loaded before the first scene, so every bell listener hears every home
  and a fault in any listener shows in every scene it touches.  (While
  104's listener refused bell kind `mailbox`, the demo briefly loaded 104
  only for the people scene; that was dropped once 104 was fixed, since it
  hid how the modules work together.)
  Every home the demo makes gets its direct-message mailbox at birth (port
  7700); top rooms take tree-mailbox ports from 7701 up; a waiting
  mailbox, when needed, is on 7799.  The scenes (`103-demo-sections.lua`
  builds, `104-demo-view.lua` draws):
  1. entries — `ls rooms/`, every file with its size (entry, flagged,
     log, where, withheld), both entries as written (now with `mailbox`),
     the one reader's result, lists by kind; a member without a port
     refused by `make_room`, an entry with `port[2]` deleted by hand
     refused by `read_entry`.
  2. tokens — three six-word suggestions (words counted from the token,
     ~78 bits each), a typed token read back unchanged, a duplicate token
     refused, a hand token change with folder, label, 3 members, 5
     messages and 475 log bytes the same before and after.
  3. tree — home/kitchen/shopping and family/cooking/groceries matched by
     fingerprint; 102's `check_member`: coder `no` in shopping (not a
     member of kitchen), housemate `yes`; adding the coder answers
     `added-flagged`: 4 members, 3 on the send list, `flagged` holding
     `203.0.113.30 7003 no`; approved: 4 of 4, the line now `approved`.
     The girlfriend's first machine leaves home (confirmed): nothing
     removes it below; it is flagged `no` in kitchen (3 members, 2 sent)
     and in shopping (grandchild).  Kitchen declines it: flag line gone,
     `withheld` holds it.  A room whose parent home B does not hold:
     `cannot-check`, both members flagged, 0 of 2 on the send list.
  4. mailboxes — home, kitchen, shopping in one tree mailbox (port 7701),
     both direct messages in the direct mailbox (7700), programming in its
     own (7702); the `mailboxes` file as written; a frame on 7700 tried
     against 2 keys, on 7701 against 3.  A top room "games" made on 7702
     too: `shared_ports` finds 1 port named by 2 mailboxes, one read of
     the file gives 1 report, 7702 tries 2 keys.  A room "attic" whose
     parent "loft" is not held, per `mailboxes.unheld-parent`:
     `own-mailbox` puts it in a tree mailbox of its own and it stays there
     when loft arrives; `waiting-mailbox` puts it in the waiting mailbox
     (7799) and it moves into loft's mailbox when loft arrives.
  5. members — six members, six sent; one withheld: six members, five
     sent, the `withheld` file holding it.
  6. leaving — an unconfirmed leave changes nothing (entry byte for byte);
     a confirmed leave: `removed`, five; speaking again: `added`, six,
     `heard[6]` written.
  7. ignoring — one address at `mark`, one at `hide`: 5 delivered, 4
     filed (the hidden one's message is dropped); the marked one shown as
     "(someone you ignore spoke)"; the hidden address on another port is
     hidden too and not filed; both answered `ignored` when a member's
     list brings them into another room; the hidden one `added` after
     un-ignoring.
  8. people — `ls people/` gives one folder per direct message (coder,
     girlfriend, housemate); the girlfriend's two machines give her two
     links (home, programming); a second top room labelled programming
     under each `people.link-collision` variant: `programming~074b` beside
     `programming~a99a` (suffix-id), `programming` beside `programming-2`
     (numbered), one folder per room tag (id-folder, links one level
     deeper).  About 1.25 s, the slowest scene (four homes, 104 rebuilding
     all of people/ on every ring).
  9. log — tab-separated, the one shape: the late message placed second,
     a repeat `duplicate`, the same id with new words raised as an error
     naming both, a correction filed with its original kept, the raw log;
     105.5 bytes per message over 200 one-line messages; the same four
     messages on two homes in opposite arrival orders shown identically.
  10. the tally's summary: 31 choices, 24 waiting on the owner, 7 on some
     other state.
- **Tests** (`src/phase-1-demo/tests/`): every scene built and checked on
  the real modules, then built again with every key at its last-listed
  variant; the whole demo through `run-phase-demo 1`.  The people scene is
  checked in full on both baselines, with expectations worked out from
  the options actually set: under `people.direct-message-link = include`
  each person's folder holds one more link (their own direct message: the
  girlfriend 3 instead of 2, the coder 4 instead of 3), and under
  `people.link-collision = id-folder` every link must read
  `<person>/<tag>/<name> -> ../../../rooms/<tag>` with the middle folder
  equal to the target's tag (otherwise `<person>/<name> ->
  ../../rooms/<tag>`).  These variants first ran on 2026-09-25 once 104
  was fixed; the earlier checks assumed leave-out and one level.  (A slip
  in the test itself also surfaced then: the "first-listed" people pass
  had been run on the last-listed settings.)
- Round 1's and round 2's scene files (`-done`) are deleted; git history
  holds them.  (The sample `tests/samples/good-src/alpha/019-options.lua-done`
  stays: it is the fixture proving the tally never reads a `-done` file.)
- Removed from the scenes with their answered choices: the token
  word-count variants (`rooms.suggested-token-words`), the
  `ignore.hide-files` variants (filed / not-filed), the `log.record-shape`
  variants (block, jsonl and their bytes-per-message comparison), and 102's
  `may_join` / 103's `not-in-parent` refusal.

## Intended Behavior

**The options tally** is unchanged.

**The phase 1 demo** shows the room-as-contact model with figures and real
outputs, not descriptions.  Scenes, each in its own scratch home:

1. **Rooms are entries.**  A direct message and a group room side by side:
   the flat `rooms/` listing, each `entry` printed as written (label,
   token, kind, paired addresses), and the same code reading both.  An
   unpaired address refused.
2. **Tokens.**  Suggested readable tokens; a typed one accepted; a token
   changed by hand, with the log's message count unchanged before and
   after.
3. **The tree.**  `home`, a child `home/kitchen`, a grandchild; drawn as
   text; the same tree on a second home with different labels, matched by
   fingerprint; an address flagged in a child room because it is not in
   every room above, off the send list until approved; a leaver flagged
   below; a parent not held: "cannot-check".
3a. **Mailboxes.**  A top room and its children in one mailbox, direct
   messages in the one direct mailbox, the `mailboxes` file, which keys a
   frame on each port is tried against; two mailboxes on one port,
   allowed and reported; a room whose parent is not held, per variant.
4. **Members and withheld.**  A room of six: every member on the send list;
   one withheld; the send list shrinking by one while the member list does
   not.
5. **Leaving.**  A forged leave changes nothing; a confirmed leave removes
   the address; speaking again re-adds it.
6. **Ignoring.**  One address at `mark`, one at `hide`; the room view with
   "someone you ignore spoke"; an ignored address brought back by another
   member's list refused.
7. **people/.**  Per direct-message contact; two rooms with the same label
   under each collision mode.
8. **The log.**  A late message placed in order; a repeat answered
   `duplicate`; the same id with different contents raised as an error; an
   edit with its original kept; ordering identical on two homes; bytes per
   message.
9. **The tally's summary.**

## Suggested Implementation Steps

1. Keep the tally; check it reads the rewritten options files.
2. Keep the demo's harness (input first, config baseline, scratch homes,
   the ran/could-not table, goodbye last).
3. Replace the scenes with the ten above; drop the earlier designs' scenes.
4. Tests: every scene on the real modules; the whole demo through
   `run-phase-demo 1`.

### Round 4 (2026-09-25)

1. The mailboxes scene shows a child with its own mailbox, then merged
   into its parent's mailbox after the parent arrives (both `ask` and
   `automatic`), and an unknown config line refused.
2. The demo's config baseline sets only declared names.

## Blockers that are not the owner's

- Needs 101–105 and 103a rewritten.  Scenes whose module is not ready are
  reported as could-not-run with the reason, as now.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. **The demo's baseline** (`demo-baseline`, waits on the owner): when a
   scene shows one choice's variants, the other choices are set to the
   first variant each builder listed, overridable from
   `input/phase-1-demo.config`.  The first-listed variant is often not the
   builder's leaning.  Keep first-listed, or add a machine-readable leaning
   to every options file and use it?

## Earlier designs

- **First model (built 2026-09-25):** eight scenes — rooms by id, `people/`
  before and after the girlfriend joined `ritz`, name collisions, a
  reader's trees under both disclosure modes, the log in each shape, edits
  under each rule, a room of six split into two rooms of five, and the
  tally.

- **Round 2 (built 2026-09-25):** nine scenes of "a room is a contact"
  before mailboxes and flags: token suggestions per word count (6, 5, 4),
  the parent-membership rule as a refusal (`not-in-parent`), ignoring per
  `ignore.hide-files` (5 of 5 filed / 4 of 5), and the log in three record
  shapes (tsv 105.5, block 155.5, jsonl 172.5 bytes per message).

## Related documents

- `docs/phase-1-module-contract.md`
- `run-phase-demo`
