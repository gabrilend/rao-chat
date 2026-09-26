# tests/ — message-log tests

- `098-run-tests [DIR]` — runs 091–094 against the stand-in room-folders
  and, if present, the real one; exits non-zero on any failure.  Names its
  test files one by one.
- `090-test-harness.lua` — `start(arg, name)` → harness with `rooms`, `log`,
  `fresh_home(settings table)` → home, `new_room(home)` → local tag (a
  top-level group room made with `make_room`, a fresh unique token, no
  parent, no members, its own mailbox on port 20000 + n), `message(fields)`
  → message with a fresh id and `from = "me"`, `settings(check)` → config
  table holding only `log.duplicate-check`, `CHECKS` = `{"scan",
  "remembered"}`, `check(bool, label)`,
  `refuses(fn, expected_text, label)`, `finish()` (prints counts, exits 1
  on failure).  Scratch homes go in
  `tmp/shared-memory/message-log/<test>-<neighbour>/`.
- `091-test-codecs.lua` — tsv round trips of 229 texts, markers, damaged records, lines in the retired block/jsonl shapes refused.
- `092-test-log.lua` — filing, repeats, the same id with different contents (error naming both), a repeat from another address answered duplicate with no key set, the exact line on disk, order, bell, the `from` field's accepted and refused shapes, two homes with different tags showing one order; under both duplicate checks; only `log.duplicate-check` is needed in config.
- `093-test-edits.lua` — corrections and deletions under both duplicate checks; anyone may edit; no time limit; a deleted message stays in the view; a leftover `log.who-may-edit` is ignored; edits whose message is absent.
- `094-test-memory.lua` — remembered check vs outside appends (and comparing against them) and replaced files; ids quoted in text; a block-shaped line left in a log (remembered refuses when filing, scan does not look; reading refuses under both).
- `095-measure.lua [DIR] [real|stand-in] [count]` — bytes per message and timings.
- `stand-in/002-room-folders.lua` — the 101 functions the log uses (`open_home`, `set_config`, `config_value`, `new_local_tag`, `make_room` (insists on round 3's `mailbox_port`), `log_path`, `room_exists`, `on_change`, `notify`), for testing alone.

Each test file is run as `luajit <file> [DIR] [real|stand-in]`.
