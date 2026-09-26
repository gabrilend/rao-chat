# 084-log-reader.lua — log text back into records

| function | takes | gives |
|---|---|---|
| `parse(content)` | string (file bytes, starting at a record boundary) | list of records in file order, and a same-length list of integers: the 1-based byte position in `content` where each record begins; error on a last line without its newline (a write cut short), an empty line, or a damaged record |
| `parse_one(content, position)` | string, integer (1-based byte where a record begins) | the one record starting there; same errors as `parse` |
| `read_file(path)` | string path | string, whole file; error when there is no file (no such room) |
