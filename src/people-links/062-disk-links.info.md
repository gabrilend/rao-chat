# 062-disk-links.lua

The disk operations plain Lua lacks, done through LuaJIT's foreign-function
interface (direct calls into the system C library): symbolic links, single
folders, and folder listings.  No shell is involved, so odd characters in
names are safe.  Loaded with `require("062-disk-links")`.  Needs no other
module.  Assumes Linux on x86_64 (the layout of a folder entry and the error
numbers are that platform's; glibc and musl agree).

Every failure raises an error carrying the system's own reason text.

## Outward functions

| function | takes | gives | purpose |
|---|---|---|---|
| `is_link(path)` | string | bool | Whether `path` is itself a symbolic link (a link pointing nowhere counts).  Errors on faults other than "not a link" / "nothing there". |
| `read_link(path)` | string | string | The target text stored in the link, exactly as written.  Errors if `path` is not a link. |
| `make_link(target, path)` | string, string | nothing | Makes a link at `path` holding `target` (relative stays relative).  Errors if anything is already at `path`. |
| `remove_link(path)` | string | nothing | Removes a link.  Refuses (errors) if `path` is not a link, so it can never delete a file. |
| `is_dir(path)` | string | bool | Whether `path` opens as a folder (a link to a folder counts). |
| `exists(path)` | string | bool | Whether anything is at `path`, dangling links included. |
| `make_dir(path)` | string | nothing | Makes one folder (not its parents); a real folder already there is fine; anything else there is an error. |
| `remove_dir_if_empty(path)` | string | bool | Removes the folder if empty (true); leaves it if it holds anything (false). |
| `list_dir(path)` | string | list of string | Names in the folder, without `.` and `..`, sorted byte-wise.  Errors if it is not a folder. |
