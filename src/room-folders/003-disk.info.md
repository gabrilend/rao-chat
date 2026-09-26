# 003-disk.lua

Small file tools for room-folders.  Every failure is an error carrying the
path and the operating system's reason.

| function | takes | gives | what it does |
|---|---|---|---|
| `is_dir(path)` | string | bool | Whether a folder is there. |
| `is_file(path)` | string | bool | Whether a readable non-folder is there. |
| `read_all(path)` | string | string | The whole file; errors if it cannot be opened. |
| `write_atomic(path, text)` | string, string | nothing | Writes `<path>.tmp-<16 hex>` then renames it over `path`, so readers see the old or the new file, never half. |
| `make_dir(path)` | string | nothing | Makes one folder (mode 0755); errors if it exists or its parent is missing. |
| `rename(from, to)` | string, string | nothing | Moves a file or folder. |
| `list_dir(path)` | string | sorted list of string | Every entry name, hidden ones included; errors if `path` is not a folder. |
| `remove_tree(path)` | string | nothing | Removes a folder holding only plain files. |
| `shell_quote(path)` | string | string | The path in single quotes, safe to hand to a shell. |
