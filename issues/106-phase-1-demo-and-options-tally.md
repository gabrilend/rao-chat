# 106 — Phase 1 demo, and the options tally

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101, 102, 103, 103a, 104, 105
**Module folders:** `src/phase-1-demo/`, `scripts/`,
`issues/completed/demos/` (indexes 100–119)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Both halves exist and run against the round-2 ("a room is a contact")
modules: the demo shows 9 of 9 scenes on the real 101, 102, 103, 103a,
104 and 105 (`run-phase-demo 1` exits 0), and 253 of 253 checks pass
(`luajit src/phase-1-demo/tests/118-run-tests.lua`).

- **The options tally**, `scripts/tally-options [project folder] [--walk]
  [--no-pause]`: gathering (`src/phase-1-demo/100-gather-options.lua`)
  kept apart from showing (`101-show-options.lua`), unchanged from round
  1.  It reads every live `src/<module>/<3 digits>-options.lua` and never
  a retired `-options.lua-done` (tested on a sample, and on the real
  project by comparing its count with `find`).  On 2026-09-25 it read 6
  files, 33 choices (24 waiting on the owner, 9 on some other state).
- **The demo**, `issues/completed/demos/phase-1-demo` (bash) running
  `src/phase-1-demo/106-phase-1-demo.lua`: the round-1 harness kept
  (input/ read first, every config key set to its first-listed variant
  unless `input/phase-1-demo.config` names another, each scene in its own
  scratch home under `tmp/shared-memory/phase-1-demo/`, a ran / could-not
  table with the reason, `output/phase-1-demo.goodbye` written last).  It
  now loads seven module files (002, 021, 024, 041, 042, 061, 081).  The
  scenes (`103-demo-sections.lua` builds, `104-demo-view.lua` draws):
  1. entries — `ls rooms/`, both `entry` files as written, the one
     reader's result, the lists by kind; a member without a port refused
     by `make_room`, and an entry with `port[2]` deleted by hand refused
     by `read_entry`.
  2. tokens — three suggestions for each `rooms.suggested-token-words`
     variant (6, 5, 4 words), a typed token with spaces and punctuation
     read back unchanged, a duplicate token refused, a hand token change
     with folder, label, 3 members, 5 messages and 475 log bytes the same
     before and after.
  3. tree — home/kitchen/shopping on one home and family/cooking/groceries
     on another, the three fingerprints matching, local tags differing,
     shopping's `where`; the coder (in home, not in kitchen) answered
     `not-in-parent` in shopping, the housemate `added`.
  4. members — six members, six on the send list; one withheld: six
     members, five on the send list, the `withheld` file holding it.
  5. leaving — an unconfirmed leave: nothing is called (103 keeps no
     pending-leave state; phase 2's call-back check decides), six members,
     the entry byte for byte unchanged; a confirmed leave: `removed`, five;
     the leaver speaking again: `added`, six, its `heard[6]` written.
  6. ignoring — per `ignore.hide-files` variant: the `ignore` file, levels
     none/mark/hide, the room as shown (the marked address as "(someone
     you ignore spoke)", the hidden one absent), 5 of 5 messages filed
     under `filed` and 4 of 5 under `not-filed`; both ignored addresses
     answered `ignored` when a member's list brings them into another
     room, the hidden one `added` after un-ignoring.
  7. people — one folder per direct message; the girlfriend's two
     machines give her two links (home, programming), not four; a second
     top room labelled programming under each `people.link-collision`
     variant (`programming~42d9`, `programming-2`, one folder per room).
  8. log — per `log.record-shape`: the late message placed second on
     screen, a repeat `duplicate`, the same id with new words raised as an
     error naming both, a correction filed with its original kept, the raw
     log; bytes per message over 200 one-line messages: tsv 105.5, block
     155.5, jsonl 172.5.  The same four messages on two homes in opposite
     arrival orders show in the identical order.
  9. the tally's summary.
- **Tests** (`src/phase-1-demo/tests/`): every scene built and checked on
  the real modules, then built again with every key at its last-listed
  variant; the whole demo through `run-phase-demo 1`.  Where a key a
  module reads is in no options file yet, the scenes test fills it from a
  stand-in table and prints which (on 2026-09-25: `tree.filing-loop` and
  `tree.unheld-parent-join`, which 102 had not yet listed; neither is read
  by any scene, since both are read only on their edge case).
- Round 1's scenes are kept as `103-demo-sections.lua-done`,
  `104-demo-view.lua-done`, `106-phase-1-demo.lua-done`,
  `119-options.lua-done`, `tests/115-test-demo-scenes.lua-done` (with
  their `.info.md-done`), until one commit has carried them.
- Seen while building: 102's `039-options.lua` still listed round 1's
  `tree.parent-disclosure` when the demo last ran, so the demo still set
  it in every home; it goes when 102 rewrites that file.

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
   the parent, off the send list until approved.
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
   message in each record shape.
9. **The tally's summary.**

## Suggested Implementation Steps

1. Keep the tally; check it reads the rewritten options files.
2. Keep the demo's harness (input first, config baseline, scratch homes,
   the ran/could-not table, goodbye last).
3. Replace the scenes with the nine above; drop the first model's scenes.
4. Tests: every scene on the real modules; the whole demo through
   `run-phase-demo 1`.

### Round 3 (2026-09-25)

1. Scenes for what changed: mailboxes (a top room and its child in one,
   the direct-message mailbox, a shared port reported); the tree scene
   shows a flag raised, the member off the send list, then approved; the
   ignore scene without the retired variants; the log scene in tsv only.
2. Drop scenes' use of retired keys; check the tally still reads every
   options file.
3. Delete this module's `-done` files.

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

## Related documents

- `docs/phase-1-module-contract.md`
- `run-phase-demo`
