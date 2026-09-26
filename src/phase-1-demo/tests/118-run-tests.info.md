# tests/ — the phase-1-demo checks

Run: `luajit src/phase-1-demo/tests/118-run-tests.lua [project folder]`.
Prints one line per test file with its number of checks, then
"passed N   failed N   crashed files N"; exits 1 on any failure or crash.

| file | checks |
|---|---|
| `110-check-kit.lua` | the shared kit: `check(claim, holds, detail)`, `check_error(claim, action, expected_text)`, `contains_line(lines, text)` |
| `111-test-gather.lua` | gathering on `samples/`: the good project, an empty one, four broken ones (bad waits_on, missing findings, duplicate id, invalid Lua), and the decoy two folders deep |
| `112-test-show.lua` | the summary table and the walk, driven by a pretend person |
| `113-test-tally-script.lua` | `scripts/tally-options` run from `/` on the real project: flags, unknown flag, walk with ended input |
| `114-test-demo-probes.lua` | the measuring tools on a folder made in the test |
| `115-test-demo-scenes.lua` | every scene on the REAL modules with a stand-in list of variants, checking the demo's figures |
| `116-test-demo-run.lua` | the demo end to end, and through `run-phase-demo 1`: input first, goodbye last, exit status, every scene ran |

Scratch space: `tmp/shared-memory/phase-1-demo-tests/`.
