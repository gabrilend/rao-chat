# 085-duplicate-check.lua — "is this id already in the log, and what does it say?"

| function | takes | gives |
|---|---|---|
| `find(path, id, strategy)` | log path (string), id (string), `"scan"` or `"remembered"` (`log.duplicate-check`) | `true, record` (the record already filed with that id, fields as in 083) or `false`; error on an unknown strategy, a missing file, or a damaged record |
| `forget(path)` | a log path or `"all"` | — ; drops remembered records |

- **scan** reads the whole file, searches it for the id's marker, and
  decodes only the record found.  Nothing kept.  A damaged line elsewhere
  in the log goes unnoticed until the log is read.
- **remembered** keeps per log path `{offset (integer bytes read), head
  (string, first ≤64 bytes), tail (string, ≤64 bytes before offset),
  records (table id → record)}` in memory and reads only new bytes; starts
  over if the file shrank or its head/tail no longer match.  Memory grows
  with the log's text.  Every new record is decoded, so a damaged line is
  an error at the next check.
