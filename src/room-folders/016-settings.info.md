# 016-settings.lua

Plain data: room-folders' declaration of the config names it reads (read
by `017-declared-settings`; a `config` line naming anything no module
declares is an error).  Returns a list of strings:

- `mailboxes.merge-when-parent-arrives` — `automatic` | `ask`; read by
  `002-room-folders` only when a child room's own mailbox can merge into
  its newly arrived parent's.

Retired and no longer listed: `mailboxes.unheld-parent` (round 4),
`rooms.suggested-token-words` (round 3).
