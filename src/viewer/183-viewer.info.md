# 183-viewer.lua

The reference viewer (issue 301, step 3): a text viewer on the home
machine that reads and writes only the home's RAM folder, the reference
the Android app and the web page are measured against.

    luajit src/viewer/183-viewer.lua <home RAM folder> <command> [...]

| command | does |
|---|---|
| `tree` | every room, joined from each gatherer's `inbox/.tree` by tag; children by label then tag (102's order); `[n flagged]` and `[n waiting]` from `.room` |
| `room <room>` | the room's heading (path, kind, members, flagged, waiting), each pair's pile, and every message in the folder's name order: written time, `from:`, edited / marked, the body, `-- <signature>`; a deleted message shows `(deleted)` |
| `write <room> [--signature <name>] <text...>` | a `typed/` file in the room's own gatherer: `room:`, `written:` (this clock), a blank line, the text and the signature on its own last line; the text from stdin when none is given; a signature 169's rule would not read back as itself is refused |
| `follow <room> [--for <seconds>]` | the room's messages, then each new or changed file as it appears (polled once a second) |
| `problems` | each gatherer's `problem.*` lines from its `state` |

`<room>` is a local tag, a unique start of one, or the path of labels
`.room` gives.  It never reads the disk home or a room's log, applies no
edits, works out no signature or tree placement (the gatherers wrote
those), has no command that removes an inbox file, and writes only
through 161's `put`.  As a module it gives `gatherers`, `read_fields`,
`rooms`, `find_room`, `tree_text`, `room_text`, `typed_text`, `write`,
`problems_text` and `follow`.

`RAO_VIEWER_BROKEN` (`own-order`, `in-place`) selects the broken versions
184's referees must catch; nothing else reads it.
