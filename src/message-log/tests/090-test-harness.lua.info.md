# tests/ — message-log tests

- `098-run-tests [DIR]` — runs 091–094 against the stand-in room-folders
  and, if present, the real one; exits non-zero on any failure.  Names its
  test files one by one, so `-done` copies never run.
- `090-test-harness.lua` — `start(arg, name)` → harness with `rooms`, `log`,
  `fresh_home(settings table)` → home, `new_room(home)` → local tag (a
  group room made with `make_room`, a fresh unique token, no parent, no
  members), `message(fields)` → message with a fresh id and `from = "me"`,
  `settings(shape, mixing, check, who)` → config table (`who` =
  `log.who-may-edit`, `"anyone"` when not given), `check(bool, label)`,
  `refuses(fn, expected_text, label)`, `finish()` (prints counts, exits 1
  on failure).  Scratch homes go in
  `tmp/shared-memory/message-log/<test>-<neighbour>/`.
- `091-test-codecs.lua` — round trips of 229 texts per shape, markers, damaged records.
- `092-test-log.lua` — filing, repeats, the same id with different contents (error naming both), a repeat from another address under both `log.same-id-new-address` values, order, bell, the `from` field's accepted and refused shapes, two homes with different tags showing one order; all 12 setting combinations.
- `093-test-edits.lua` — corrections and deletions in every shape under `log.who-may-edit` = anyone and same-address; no time limit; edits kept across a rule change; edits whose message is absent.
- `094-test-mixing-and-memory.lua` — shape changes under fixed and per-record; remembered check vs outside appends (and comparing against them) and replaced files.
- `095-measure.lua [DIR] [real|stand-in] [count]` — bytes per message and timings.
- `stand-in/002-room-folders.lua` — the round-2 101 functions the log uses (`open_home`, `set_config`, `config_value`, `new_local_tag`, `make_room`, `log_path`, `room_exists`, `on_change`, `notify`), for testing alone.

Each test file is run as `luajit <file> [DIR] [real|stand-in]`.
