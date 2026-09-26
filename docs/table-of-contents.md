# rao-chat - Table of Contents

Every document in docs/ and notes/ belongs somewhere in this tree. Source code
and issue files do not; they have their own indexes.

## Vision
- notes/vision-planning.md - the planning document: what rao-chat is (private
  chat in rooms nested like folders, each with its own recipients, between
  people who each run a home server), how rooms are kept on disk, how the
  Android app and web client reach their server, what it borrows from rmail
  and from double-diaper-dungeon's conversation pages, proposed phases, and
  the open questions still to answer.  Sections 1–4 describe the adopted
  model, where a room is a contact: a label of your own, a random
  plain-text token its members share, and every member's address paired
  with its own port; a direct message is a room with one other person;
  child rooms only hold members of their parent; each person keeps their
  own withheld and ignore lists.  Section 14 keeps the conversation about
  the second model (a room is its name), including the threat model;
  section 15 keeps the conversation that produced the adopted one.
  Appendix A keeps the first model, which phase 1 was first built to;
  Appendix B keeps the second.

## Documentation
- docs/table-of-contents.md - this file.
- docs/phase-1-module-contract.md - how phase 1's five room modules and its
  demo plug together: where each lives, the functions each offers, the
  change bell they listen on, the undecided choices each builds every
  variant of, and the options tally that lists those choices for review.

## Phases
Phases group related functionality, not calendar time. It is normal for the
last issue completed in a project to belong to phase 1.

Proposed in notes/vision-planning.md (section 12); to be confirmed when the
roadmap is written:

1. Rooms on the home server - room folders by local tag, each with a
   contact-style entry (label, token, paired addresses, parent); group
   rooms and direct messages alike; the tree of child rooms; withheld
   lists; the ignore list; the people/ links; the message log and ids.
2. Server-to-server delivery - sealing with the room's token, sending at
   once with acknowledgement and retries, the failed-decryption log, the
   call-back check, the hello (which is also joining), contact syncing,
   leaving, and periodic cross-checking.
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
