# 001-load-path.lua

Returns one function that lets every rao-chat module find every other one.

| function | takes | gives | what it does |
|---|---|---|---|
| (the returned function) | dir: string, the project folder | nothing | Adds `<dir>/libs/?.lua` and `<dir>/src/<each folder>/?.lua` to the front of Lua's `package.path`.  Only folders under `src/` are added, in sorted order, so a new module folder is found without editing this file. |

Usage: `dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)`, then
`require("002-room-folders")` and so on by file name without `.lua`.
