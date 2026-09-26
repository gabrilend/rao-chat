# tests/064-stand-in-room-folders.lua

A small stand-in for 101's `002-room-folders`, used by the tests in
`stand-in` mode.  Offers the part of the round-2 contract people-links and
its tests use: `open_home`, `read_config`, `set_config`, `config_value`,
`new_local_tag`, `token_fingerprint` (64 hex, not SHA-256), `make_room`,
`read_entry`, `write_label`, `write_members`, `write_heard`, `write_parent`,
`write_filed_under`, `change_token` (re-points held children first, as the
contract says), `list_rooms`, `find_by_fingerprint`, `room_exists`,
`room_dir`, `on_change`, `notify`; and, since round 3, mailboxes:
`make_mailbox` (the direct kind only; rings `mailbox` with `""`),
`direct_mailbox`, `write_mailbox_port` (rings `mailbox` with `""`),
`write_mailbox` (rings `mailbox` with the room's tag), and `make_room`'s
`mailbox_port` rule (integer exactly when the room starts a new mailbox;
a parent not held here always gets a mailbox of its own (round 4), and is
never merged into the parent's when it arrives (the real 101 does, under
`mailboxes.merge-when-parent-arrives`; mailboxes move no link).  Config
accepts any name here; the real 101 refuses names no module declares).  Entries carry `mailbox`; `make_room` also makes
an empty `flagged`.  Entries are stored as Lua tables, not
rmail's format; nothing is refused (no loop, repeated-token or address
checks).
