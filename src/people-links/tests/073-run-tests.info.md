# tests/073-run-tests.lua

Runs every people-links test file (066–072, 075), each as its own program,
in up to three modes: `stand-in` always; `real-101` once the real 101 has
`read_entry`; `real` once the real 102 also has `snapshot`.  Prints one line
per file and mode, totals per mode and overall.  Never runs `-done` files.

Usage: `luajit src/people-links/tests/073-run-tests.lua [DIR]` — `DIR` is the
project folder (default `/home/ritz/programs/rao-chat`).  Exit status 0 when
every check passed, 1 otherwise; a test that crashes before printing its
result counts as one failure.
