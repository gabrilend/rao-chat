# 084-log-reader.lua — log text back into records

| function | takes | gives |
|---|---|---|
| `parse(content, mixing, shape)` | string (file bytes, starting at a record boundary), `"fixed"` or `"per-record"`, configured shape name | list of records in file order, and a same-length list of the shape each was found in; error on a record cut short, an empty line where a record should begin, a damaged record, or (fixed) a record in another shape |
| `parse(...)` third result | — | list of integers: the 1-based byte position in `content` where each record begins |
| `parse_one(content, position, mixing, shape)` | string, integer (1-based byte where a record begins), mixing, shape | the one record starting there; same errors as `parse` |
| `read_file(path)` | string path | string, whole file; error when there is no file (no such room) |
| `picker(mixing)` | `log.shape-mixing` value | internal shape-choosing function; error on an unknown value |
