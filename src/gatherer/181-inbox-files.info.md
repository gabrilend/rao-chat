# 181-inbox-files.lua

The viewer's inbox (issue 301, step 1): one file per message in each
gatherer's RAM folder, `inbox/<room local tag>/<written>-<id>`, in
rmail's inbox-file shape — `id:`, `room:`, `from:` (`me`, the address and
port, or 103's `shown_as` label), `written:`, `arrived:`, `signature:`
(169's rule), `edited:`, `deleted:`, `ignored:` (`none` or `mark`), a
blank line, the body (signature line taken off, edits applied by 105's
`read_ordered`).  Sorted by name, a room's folder is the room's order.
A deleted message keeps its file (`deleted: yes`, empty body); a `hide`
address's has none, and one written before the hide is removed.  Every
file is written through 161's `put` (temporary name, then rename) and
only when its text changes; a removed file is written again.

| function | takes | gives |
|---|---|---|
| `folder(gatherer_folder)` | the gatherer's RAM folder | its `inbox/` folder |
| `file_name(view)` | a 105 view | `"<written>-<id>"`; error on an id outside 105's alphabet or a written time that is not whole |
| `file_text(home, tag, view)` | home, room tag, view | the file's text, or nil for a `hide` address |
| `room_text(home, disk_home, tag, places)` | RAM home, disk home or nil, tag, 102's placements or nil | the text of `.room` |
| `tree_text(home, disk_home, tags)` | …, this mailbox's tags | the text of `.tree` |
| `write_room(gatherer_folder, home, tag, disk_home, places)` | …, a 32-hex room tag | how many files were written or removed, `.room` included |
| `write_facts(gatherer_folder, home, disk_home, tags, with_tree)` | … | `.room` of each room (and `.tree`), where changed |
| `write_all(gatherer_folder, home, tags, disk_home)` | …, list of tags | every room's files and `.room`, and `.tree`, summed |

Beside the messages, each room's `.room` (`label:`, `kind:`, `parent:`
(the tag it shows under, or `none`), `path:` (102's path of labels),
`members:`, `flagged:` (103's members awaiting review), and one `pile:
<address> <port> <missing> <oldest written>` line per pair still owed
something, or `pile: none`), and the mailbox's `inbox/.tree` (one line
per room: `<tag> <parent tag or none> <kind> <label>`, 102's order).  The
parent and path come from 102's `placements` on the disk home, which
holds every room of the home, so a viewer joining several gatherers'
trees places nothing itself.

The gatherer (163) calls `write_all` at start-up and every sync cycle,
`write_room` from its filing hook after each record filed or typed, and
`write_facts` after each sender pass and attempt (the pile moves then).
`RAO_INBOX_BROKEN` (`arrival-order`, `raw-text`, `hide-shown`,
`in-place`, `ram-tree`, `stale-pile`) selects the broken versions 182's
referees must catch; nothing else reads it.
