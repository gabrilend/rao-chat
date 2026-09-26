# Conversation Summary: agent-ada3490f3b740073d

Generated on: 2026-09-25 20:24:05
Models: claude-opus-5-5

--------------------------------------------------------------------------------

### User Request 1

You are builder 101, round 2. Read and follow
/home/ritz/programs/rao-chat/tmp/shared-memory/agent-network/BRIEF-2.txt exactly
(it points you to round 1's brief for the house rules).

Your issue:
/home/ritz/programs/rao-chat/issues/101-room-folders-by-local-tag.md. Your
folder: /home/ritz/programs/rao-chat/src/room-folders/ (indexes 001–019;
options file 019-options.lua).

You are the foundation, and you own the contract's shared parts. Do this FIRST,
before anything else: rewrite docs/phase-1-module-contract.md's shared sections
— the note at its top, "Where each module lives" (owns column), loading, the
home folder layout (config, ignore, rooms/<local tag>/{entry, withheld, where,
log}, people/), the entry's fields in rmail's contacts format (label, token,
kind, ip[N]/port[N] always paired, parent = token fingerprint, filed-under =
local tag or empty, plus whatever you add, e.g. when each address was last heard
from — issue 103 needs that for pruning), the bell's kinds, and 101's function
table. Mark the other modules' sections "being rewritten by 1NN". Post
"CONTRACT: shared parts rewritten" on the board. Then build, making the entry
read/write, room making, token fingerprint and bell usable early and posting
each as it lands — the other five builders are waiting on them. The
readable-token suggester needs a word list: make or find one (a plain text file,
one word per line; say where it came from and its licence), kept in
/home/ritz/programs/rao-chat/assets/ or libs/.

--------------------------------------------------------------------------------

### Assistant Response 1

> Now the contract rewrite.

> Now the bell.

> Update the contract bell rows accordingly.

> Now the home-and-rooms tests.

> Now the options file. Let me see the rest of the old one for the two kept
> choices.

> Now the issue file's Current Behavior and open questions.

> Add the two contract rows and update the options info and issue count.

I sent my final report to the coordinator. The room-folders module is rebuilt
for "a room is a contact". Its issue stays open because open questions 1–7
have not been answered yet.

**The shared contract, done first.** Before any code, I rewrote the shared parts
of the module contract (`docs/phase-1-module-contract.md`) and posted that on
the builders' board. The round-1 contract is kept beside it as a `-done` copy.
The rewrite sets:
- **The home folder:** a settings file, an empty ignore list, one folder per
  room, and `people/`. There is no separate contacts file any more; a person is
  a direct-message room.
- **The room's entry file**, in rmail's contacts format: your own name for the
  room, its token, group or direct, the parent room, where you filed it, and the
  members. Each member address always carries its own port and the time it was
  last heard from, with no default port.
- **The bell kinds** that tell other modules a room has changed.
- **My module's function table.**

**What was built.** Two new source files:
- **The entry file:** turns an entry into text and back, and checks every field.
- **Tokens:**
  - the parent fingerprint, which is the token scrambled twice with SHA-256 (the
    first pass is the room's sealing key);
  - a plain SHA-256 that phase 2 can reuse for the sealing key;
  - a readable token suggester.

The front door, the rmail-format reader, the bell and the options file were
rewritten. Every old file is kept as `<name>-done`, and the test runner skips
those.

**Word list.** The suggester uses the EFF large passphrase list, copied from
KeePassXC's installed copy. It has 7,772 plain lower-case words and is licensed
CC BY 3.0 US. It is at `assets/eff-large-wordlist.txt`, and
`assets/eff-large-wordlist.about.md` records where it came from, its licence and
a checksum.

**Tests: 89 pass, 0 fail.** 77 test the module alone. The other 12 run against
the real modules of the other five builders, which had all landed, so no
stand-ins were needed. They confirm:
- the files holding each room's path of names update after a rename or a token
  change;
- a child room refuses an address that isn't in its parent room;
- last-heard times reach the entry;
- the `people/` links appear on disk;
- messages file into the log made with the room.

**How many words a suggested token should have** is the one choice the config
file switches (`rooms.suggested-token-words`: 6, 5 or 4). Anyone who records
sealed traffic, or sees a child room's invitation, can guess the token offline.
The guess rate below is an assumed figure for one GPU, not measured; I measured
about 775,000 guesses a second on one CPU core.

| words | bits | time to find it (one GPU, 5 billion guesses a second) |
|---|---|---|
| 4 | 51.7 | about 4 days |
| 5 | 64.6 | about 90 years |
| 6 | 77.5 | about 700,000 years |

My leaning is 6.

**Other open choices.** Six are built one way only and wait on you:
- **A failing listener:** the change stays and the error reaches whoever made
  it.
- **Surviving a power cut:** write-then-rename only, pending a phase 6
  measurement.
- **rmail's contacts:** direct messages live in rao-chat's own room folders, not
  rmail's contacts file.
- **A token changed by hand:** child rooms on this home follow the new token. On
  other members' homes they don't until the new token is entered there. The
  person shut out still holds each child room's own token, so every token in the
  tree would need changing.
- **Last-heard times:** they live in the entry, so the entry is rewritten each
  time a member is heard from later than before.
- **One room per token:** a second room with a token already held here is
  refused.

The two round-1 choices about unknown parents and slashes in names are retired.

**Loose ends.**
- The room-tree builder's code reads two settings (`tree.unheld-parent-join` and
  `tree.filing-loop`) that no options file lists yet. My test sets them itself,
  and I flagged it on the board.
- Nothing deletes a room folder in phase 1; leaving a room is phase 2.

--------------------------------------------------------------------------------

