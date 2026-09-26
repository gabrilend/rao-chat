# 086-edits.lua — corrections and deletions (always allowed, by anyone)

| function | takes | gives |
|---|---|---|
| `check(records, edit)` | the room's records (list, file order), the edit record (kind correction/deletion) | — ; error when the target is missing, not a plain message, or already deleted.  Nothing about who sent it is checked (owner: anyone may edit) |
| `apply(records)` | records in file order | list of views `{id, from, written, arrived, text, edited=bool, deleted=bool, changed_from=string}`, messages only, file order; latest correction/deletion by (written, id) wins; deleted → text `""`, still listed (showing it as a gap or hiding it is the client's setting); `changed_from` is the address of the edit applied, `""` when none |

Every edit in the file is applied when reading.  An edit whose message is
not in the file is left out of the view (its message may still be on its
way, phase 2).
