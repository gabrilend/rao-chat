# Conversation Summary: agent-a079975ce989bf247

Generated on: 2026-09-25 20:24:17
Models: claude-opus-5-5

--------------------------------------------------------------------------------

### User Request 1

You are builder 104, round 2. Read and follow
/home/ritz/programs/rao-chat/tmp/shared-memory/agent-network/BRIEF-2.txt exactly
(it points you to round 1's brief for the house rules).

Your issue:
/home/ritz/programs/rao-chat/issues/104-people-links-what-we-share-with-each-person.md.
Your folder: /home/ritz/programs/rao-chat/src/people-links/ (indexes 060–079;
options file 079-options.lua).

You depend on 101 (entries, bell — being rewritten right now; watch for
"CONTRACT: shared parts rewritten"), 102 (the tree) and 103 (members by
address). Most of your round-1 code carries over; a person is now a
direct-message room, and their rooms are the group rooms whose members include
one of that room's addresses.

--------------------------------------------------------------------------------

### Assistant Response 1

> Posting my start on the board.

> I'll use the Edit tool instead.

> Now fix 071's bell test and set neighbour config in 072.

> Now the stand-in 102 needs a snapshot too.

> Meanwhile, posting to the board and writing the .info.md files.

> Updating the remaining .info.md files.

> Now the issue's Current Behavior section.

I've sent my report to the coordinator. The people/ links are rebuilt for "a
room is a contact", and all 739 checks pass, including runs against the real
room-folders, room-tree and members modules. The issue has five unanswered
questions and four new ones, so it stays in issues/ and nothing was committed.

**How it works now:**
- Each person is a direct-message room, and their folder in people/ takes that
  room's label.
- A group room is theirs when one of its members is one of that direct message's
  address-and-port pairs.
- Their folder links to the top rooms among those: rooms whose parent in the
  tree isn't also theirs.

In your own example, the girlfriend gets two links, home and programming. Adding
her to ritz leaves just home. I had to make programming "filed under" ritz on
your own screen rather than a declared child room: a declared child only accepts
members of its parent, and she isn't in ritz.

**Speed:** my first version asked the tree module for one room's parent at a
time. Each of those calls reads the whole home, so one rebuild of people/ took
1.2 seconds at 100 rooms. It now reads the tree once per rebuild: 12 ms at 100
rooms, 39 ms at 400.

**Choices you can switch in the config file:**
- **Two top rooms with the same label shared with one person:** a short tag from
  each room's folder name (`programming~3fa9`), numbering (`programming`,
  `programming-2`), or one folder per room.
- **Labels that can't be file names** (containing `/`, or exactly `.` or `..`):
  written as `%2F`, `%2E`, `%2E%2E`, or as look-alike characters.
- **New: is the person's own direct message linked in their folder too?** Left
  out, or included.
- **Members you have no direct message with:** no folder, or a folder named by
  their address, such as `carol.example:7000`.
- **New: two direct messages with the same label:** a short tag from each
  (`alex~3fa9`), numbering, or one merged folder.

Two questions can't be switched yet. Folders for your own devices wait on device
pairing, because the home no longer keeps any list of your devices. Rebuilding
everything on every change waits on measuring a real home. The switch for split
records is removed, since rooms no longer split.

**Found while building:**
- Changing a room's token can move links, so it now triggers a rebuild; the
  issue hadn't listed it.
- Under numbering, room folder names are random, so a new room with a repeated
  label can renumber the links for older ones.
- Addresses are matched exactly as written: `GF.example` and `gf.example` count
  as two different machines.

**Still open:** people/ relies on the tree module's whole-home read, and the
shared contract doesn't list that function yet. I asked the tree builder on the
board to add it.

The four new questions are written in the issue's current-behaviour section
rather than its open-questions list, because this round's instructions only let
builders change that section. The round-1 files are kept beside the new ones
with `-done` on their names.

The issue file is at
`/home/ritz/programs/rao-chat/issues/104-people-links-what-we-share-with-each-person.md`,
and the code is in `/home/ritz/programs/rao-chat/src/people-links/`.

--------------------------------------------------------------------------------

