# 137-test-delivery.lua

Issue 202's referees 1-9. Each runs against the real modules and against
a deliberately broken version that it must catch. What each broken
version was caught on is printed under its check. The file also has
checks of the `delivered` file, the answer format, the decisions on open
questions 1, 2 and 7, and a measurement over 10,000 messages.

The homes are real rao-homes under `tmp/shared-memory/delivery/`, which
are removed afterwards. Between them runs a simulation (143's, shared
with 204's tests since 2026-11-05): a fake clock,
coroutines for each home's accepting, serving and sending stages, and an
in-memory relay that can delay, refuse, drop or replace frames. No socket
is opened. A broken version is made by swapping one module function for
the run.

Run: `luajit src/delivery/tests/137-test-delivery.lua [project folder]`
(about 4 s). It prints `PASS`/`FAIL` for each check and then
`counts <passed> <failed>`, and exits 0 only when nothing failed.
