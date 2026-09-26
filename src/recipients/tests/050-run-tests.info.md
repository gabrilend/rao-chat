# tests/ — the recipients tests (issues 103 and 103a)

Run: `luajit src/recipients/tests/050-run-tests.lua [project folder] [stand-in | real-101 | real]`
(project folder defaults to `/home/ritz/programs/rao-chat`, neighbours to
`stand-in`; `real-101` = real room folders, stand-in tree).  Prints one `pass`/`FAIL` line per test and a final tally;
exits 1 on any failure.  Scratch homes go under
`tmp/shared-memory/recipients/run-<time>-<random>/` (RAM).

| file | what it is | outward shape |
|---|---|---|
| `044-stand-in-room-folders.lua` | a small copy of the parts of issue 101's module this module uses (round-3 contract: the `flagged` file, `mailbox_port`, `make_mailbox`, the `mailbox` bell kind) | the same function names as `002-room-folders` |
| `046-stand-in-room-tree.lua` | a small copy of issue 102's check over every declared room above, and its re-check lists | `check_member(home, tag, address, port) -> "yes"/"no"/"cannot-check", reason`; `failing_members(home, tag)`, `failing_below(home, tag)` -> list of `{room, address, port, answer, reason}` |
| `045-test-harness.lua` | wiring and helpers | returns `function(dir, neighbours) -> h`; `h.check(name, fn)`, `h.expect_error(fragment, fn)`, `h.equal(got, want, what)`, `h.keys(list of pairs) -> "a 1,b 2"`, `h.new_home(label, config table) -> home` (every module's first variant set; the direct mailbox made), `h.room(home, label, list of {address, port}, kind, parent tag) -> tag`, `h.make(home, spec) -> tag` (make_room with `mailbox_port` filled in by what the room is), `h.port() -> integer`, `h.tick() -> integer`, `h.rings() -> list of "what@tag"` since last asked; `h.rooms`, `h.recipients`, `h.ignore`, `h.pairs` are the loaded modules |
| `047-test-address-pairs.lua` | the pair shape and file lines | returns `function(h)` |
| `048-test-ignore.lua` | 103a: both levels, the member filter, every port at an address, hidden not filed, both `ignore.scope` variants | returns `function(h)` |
| `049-test-members.lua` | members from the entry, adding, a move, no minimum | returns `function(h)` |
| `052-test-withheld-and-send.lua` | withholding, the send list, two homes' own choices | returns `function(h)` |
| `053-test-leave-and-heard.lua` | confirmed leave only, speaking re-adds, last-heard, silent members | returns `function(h)` |
| `054-test-child-room.lua` | flagged members: added flagged (no / cannot-check), off the send list, approve, decline, a drop from a parent flags its children and grandchildren, a parent arriving (both mailbox variants × both `flag-after-passing` variants) | returns `function(h)` |
| `055-test-shown-as.lua` | showing a member by direct-message label; both shared-label variants | returns `function(h)` |
| `051-test-options.lua` | the options file's shape and keys | returns `function(h)` |
| `050-run-tests.lua` | the runner | a script |
