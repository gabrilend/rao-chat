# 233-test-install-home.lua

Issue 602's referees: `scripts/install-home` run as a person runs it,
with a scratch `HOME` and scratch homes (under `RAO_TEST_ROOT`, or
`/tmp`), removed at the end.

1. `--silent` with every value: a home 002 opens, every declared setting
   in it, the asked ones as given, the rest first variants under their
   questions; the direct-message mailbox on its port; the environment file.
2. `--silent` missing `--device-port` or `--home`: exit 1 naming the flag,
   no home; an unknown flag, exit 2.
3. Equal ports refused; with a stand-in `ss` on the `PATH` listing every
   port from 50000 to 64000, a listening port refused under `--silent`
   and, asked, Enter takes two different free suggestions; input that
   ends is no answer.
4. The same answers again change no byte; a hand comment and a hand
   change survive; a new device port is `changed`, a new direct port
   `moved`.
5. The scratch `HOME` stays empty; the program folder's `git status` is
   unchanged.
6. `RAO_NEEDS_BROKEN=crypto`: exit 1, libcrypto named, no home.
7. A home path holding a space, `&`, `|` and `\` is made and named.

Needs no network.  `luajit src/install/tests/233-test-install-home.lua
[project folder]`; prints PASS/FAIL and "counts".
