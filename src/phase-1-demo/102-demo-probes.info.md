# 102-demo-probes.lua

The demo's measuring tools: they read what is really on disk and time
steps.  Nothing here knows about rooms.  Loaded with
`require("102-demo-probes")`.  Every failure is an error; nothing returns an
empty answer in place of a missing file.

## Outward functions

| function | takes | gives | purpose |
|---|---|---|---|
| `now()` | — | number (seconds, float) | Monotonic clock reading (LuaJIT ffi `clock_gettime`); only differences mean anything. |
| `run(command)` | string | string (stdout and stderr together), bool (exited 0) | Runs a shell command. |
| `must_run(command)` | string | string | As `run`, but a non-zero exit is an error carrying the output. |
| `lines(text)` | string | list of string | Splits on line breaks; a final line break adds no empty line. |
| `files_with_sizes(dir)` | string | list of string `"path  N bytes"` | Every regular file under `dir`, sorted (`find -printf '%P  %s bytes'`). |
| `links_with_targets(dir)` | string | list of string `"path -> target"` | Every symbolic link under `dir` with its stored target, sorted. |
| `entries(dir)` | string | list of string | Names directly inside `dir`, sorted (`ls -1`). |
| `link_resolves(path)` | string | bool | Whether the link leads to something that exists. |
| `read_text(path)` / `write_text(path, text)` | string (, string) | string / — | Whole-file read and write; a missing file is an error. |
| `bytes(path)` | string | integer | File size in bytes. |
| `fresh_dir(scratch_root, path)` | string, string | string (`path`) | Empties and recreates `path`; refuses any path not strictly inside `scratch_root`. |

Paths holding a single quote are refused by the functions that pass paths
to the shell.
