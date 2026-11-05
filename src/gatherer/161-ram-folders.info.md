# 161-ram-folders.lua

The RAM side of a home (issue 211).  Each home gets its own folder under
`gatherer.ram-root`, named after the home folder plus 12 hex of its
path's SHA-256, so homes sharing a machine share nothing.  Under it are
one folder per mailbox with the queues `arrived/`, `answers/`, `typed/`
and `due/`, a `working/` folder, `home/` (the RAM copy of the mailbox's
rooms), `state` and `running-log`.

- `put` writes `.name.tmp` and renames, so no reader sees half a file.
- `take` renames a file into `working/`, so two takers never share one;
  `return_working` puts back what a crashed gatherer was holding.
- `load` copies the rooms in at a fresh boot.  A RAM home a previous
  process loaded (`.loaded`) is kept, so a gatherer crash loses nothing.
- `sync` writes only what changed, refuses to write over a file someone
  changed on disk by hand (named in state), and reloads changed
  home-wide files.  `sync_file(record, path, true)` and `force_to_disk`
  fsync the file and its folder before returning.
- `choose_root` falls back to `/tmp/rao-chat-ram` when the setting's
  folder cannot be written, and says why.
