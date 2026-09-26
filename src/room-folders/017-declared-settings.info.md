# 017-declared-settings.lua

Knows every setting name any module reads, so a `config` line naming
anything else is an error naming the line (round 4).  Each module lists
its names in one file `src/<module>/<3 digits>-settings.lua` (one folder
deep, never in `tests/`) that returns a plain list of strings.  This file
finds those lists by listing every folder under the `src/` it was loaded
from, once per running program — so the answer never depends on which
modules a program loaded.  Load with `require("017-declared-settings")`;
other modules go through `002-room-folders` (`read_config`, `set_config`,
`config_value`, `declared_settings`).

- A **declarations table** is name (string) → `{ module = string (the folder name under src/), file = string (path of its settings file) }`.
- A **config line** is `{ key = string, value = string, number = integer (line number from 1) }`, as `004-rmail-formats.parse_config_lines` gives.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `gather_declarations(src_dir)` | string (a `src/` folder) | declarations table | Reads every module's settings file.  Errors (naming the file) on: a file that does not load, does not return a list, has non-1..n keys or gaps, holds an item that is not a setting name, lists a name twice; a name declared by two modules (naming both); two settings files in one module. |
| `read_declaration_file(path)` | string | list of strings | One module's list, checked as above. |
| `check_config_lines(lines, where, declared)` | list of config line, string (file path), declarations table or nil (nil = this program's) | nothing | Errors at the first line whose key nobody declares: `<where> line N: '<key>' is not a setting any module reads ... — remove or correct the line: <key> = <value>`. |
| `check_name(name, doing)` | string, string (the caller's name for the message) | nothing | Errors when no module declares `name`. |
| `declared_settings()` | — | declarations table (a copy) | This program's declarations. |
| `this_src_dir()` | — | string | The `src/` folder this file was loaded from; errors when Lua cannot say (code not loaded from a file). |
| `DECLARATION_FILE_PATTERN` | — | string | Lua pattern for a settings file's name: `^%d%d%d%-settings%.lua$`. |
