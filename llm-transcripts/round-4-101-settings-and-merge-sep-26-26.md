# Conversation Summary: agent-a560202d9b396f02c

Generated on: 2026-09-26 13:00:56
Models: claude-opus-5-5

--------------------------------------------------------------------------------

### User Request 1

You are builder 101, round 4. Read and follow
/home/ritz/programs/rao-chat/tmp/shared-memory/agent-network/BRIEF-4.txt
exactly.

Your issue: /home/ritz/programs/rao-chat/issues/101-room-folders-by-local-tag.md
(its "### Round 4" list). Your folder:
/home/ritz/programs/rao-chat/src/room-folders/ (indexes 001–019).

First: the setting-name declaration mechanism (every module declares the config
names it reads; opening a home whose config holds an undeclared name is an error
naming the line). Design it so a module's declaration is a plain list the module
owns, and so the demo and every module's tests can still build homes. Document
it in the contract's shared part and post "CONTRACT: declared settings" on the
board before anything else. Then: own-mailbox fixed (retire the waiting-mailbox
variant and its setting, reusing its move code for the merge), and the merge
into the parent's mailbox with `mailboxes.merge-when-parent-arrives` = automatic
(listed first) or ask. Run 104's and 106's tests after your changes and report.

--------------------------------------------------------------------------------

### Assistant Response 1

> Now 004: add `parse_config_lines`.

> Update the kit's info row, then 011 and 010.

> Now post USABLE, then fix 013.

> Now the .info.md files.

Report sent to the coordinator. Issue 101's round-4 list is done, and
room-folders' tests pass 141 of 141. The issue stays in progress because one new
open question needs the owner's answer.

- **Settings must be declared:** each module now lists the config names it reads
  in its own small file, `src/<module>/<index>-settings.lua`. A config line that
  no module lists is refused, and the error gives the line number. I posted the
  declared-settings contract on the board before any other work. Every module
  that reads a setting has since added its list; the demo reads none.
- **Own mailbox fixed:** a child room whose parent isn't held here always gets
  its own mailbox and port. The shared waiting mailbox and its setting are gone.
- **Merging into the parent's mailbox:** the setting
  `mailboxes.merge-when-parent-arrives` controls this. `automatic` moves the
  rooms as soon as the parent arrives. `ask` only lists the merge until the
  person says yes.
- **104's and 106's tests:** people-links passes 798 of 798. The phase-1 demo
  tests pass 300 of 300, including the full demo run. The other three modules'
  tests also pass.

Things the owner should look at:
- **New open question:** under `ask` there is no "no". A declined merge stays
  listed until a yes or a hand move. Should a "no" be remembered instead?
- **My own call:** a room still waiting in its own mailbox that is given a held
  parent by hand merges under the setting. Rooms already settled in a mailbox
  keep it, as before.
- **Tally listing:** the merge setting still appears in the options tally as a
  question for the owner, because the demo reads its two values from there. It's
  actually answered.

I also updated the shared contract document and rewrote the issue's
current-behaviour section. Nothing was deleted, and nothing is blocked.

--------------------------------------------------------------------------------

