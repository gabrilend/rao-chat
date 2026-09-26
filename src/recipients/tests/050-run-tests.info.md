# tests/ — the recipients tests (issues 103 and 103a)

Run: `luajit src/recipients/tests/050-run-tests.lua [project folder] [stand-in | real-101 | real]`
(project folder defaults to `/home/ritz/programs/rao-chat`, neighbours to
`stand-in`; `real-101` = real room folders, stand-in tree).  Prints one `pass`/`FAIL` line per test and a final tally;
exits 1 on any failure.  Scratch homes go under
`tmp/shared-memory/recipients/run-<time>-<random>/` (RAM).  Files ending in
`-done` are the first model's, retired, and never run.

| file | what it is | outward shape |
|---|---|---|
| `044-stand-in-room-folders.lua` | a small copy of the parts of issue 101's module this module uses (round-2 contract) | the same function names as `002-room-folders` |
| `046-stand-in-room-tree.lua` | a small copy of issue 102's parent-membership check | `may_join(home, tag, address, port) -> bool, reason` |
| `045-test-harness.lua` | wiring and helpers | returns `function(dir, neighbours) -> h`; `h.check(name, fn)`, `h.expect_error(fragment, fn)`, `h.equal(got, want, what)`, `h.keys(list of pairs) -> "a 1,b 2"`, `h.new_home(label, config table) -> home` (every module's first variant set), `h.room(home, label, list of {address, port}, kind, parent tag) -> tag`, `h.tick() -> integer`, `h.rings() -> list of "what@tag"` since last asked; `h.rooms`, `h.recipients`, `h.ignore`, `h.pairs` are the loaded modules |
| `047-test-address-pairs.lua` | the pair shape and file lines | returns `function(h)` |
| `048-test-ignore.lua` | 103a: both levels, the member filter, every variant of its three keys | returns `function(h)` |
| `049-test-members.lua` | members from the entry, adding, a move, no minimum | returns `function(h)` |
| `052-test-withheld-and-send.lua` | withholding, the send list, two homes' own choices | returns `function(h)` |
| `053-test-leave-and-heard.lua` | confirmed leave only, speaking re-adds, last-heard, silent members | returns `function(h)` |
| `054-test-child-room.lua` | a child room refuses an address not in its parent | returns `function(h)` |
| `055-test-shown-as.lua` | showing a member by direct-message label; both shared-label variants | returns `function(h)` |
| `051-test-options.lua` | the options file's shape and keys | returns `function(h)` |
| `050-run-tests.lua` | the runner | a script |
