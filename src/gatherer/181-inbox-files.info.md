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
| `write_room(gatherer_folder, home, tag)` | …, a 32-hex room tag | how many files were written or removed |
| `write_all(gatherer_folder, home, tags)` | …, list of tags | the same, summed |

The gatherer (163) calls `write_all` at start-up and every sync cycle,
and `write_room` from its filing hook after each record filed or typed.
`RAO_INBOX_BROKEN` (`arrival-order`, `raw-text`, `hide-shown`,
`in-place`) selects the broken versions 182's referees must catch;
nothing else reads it.
