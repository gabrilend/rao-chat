# rao-chat - Table of Contents

Every document in docs/ and notes/ belongs somewhere in this tree. Source code
and issue files do not; they have their own indexes.

## Vision
- notes/vision-planning.md - the planning document: what rao-chat is (private
  chat in rooms nested like folders, each with its own recipients, between
  people who each run a home server), how rooms are kept on disk, how the
  Android app and web client reach their server, what it borrows from rmail
  and from double-diaper-dungeon's conversation pages, proposed phases, and
  the open questions still to answer.

## Documentation
- docs/table-of-contents.md - this file.

## Phases
Phases group related functionality, not calendar time. It is normal for the
last issue completed in a project to belong to phase 1.

Proposed in notes/vision-planning.md (section 12); to be confirmed when the
roadmap is written:

1. Rooms on the home server - room folders, the tree, recipient lists, the
   people/ links, the message log and ids.
2. Server-to-server delivery - rmail's networking, sending at once,
   acknowledgements, retries, duplicates ignored, late messages placed in
   order.
3. Clients' connection - pairing, catching up, live pushing, several
   devices at once, the locked-screen check-in.
4. The web client.
5. The Android app.
6. Installation and running as a service.
7. The rmail link - a button in each app that opens the other.

## Project files
- LICENSE - the GNU Affero General Public License, version 3 or later.
- .file-index-counter - the highest reading-order index used by any file in
  the project, so a new file can take the next number without a search.
- run-phase-demo - asks which completed phase to demonstrate, then runs it.
