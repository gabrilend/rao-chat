# 231-test-what-a-home-needs.lua

Issue 601's referees: the check (230) run as a program, as the installer
runs it.

1. On this machine every required thing is found, each line naming what
   it reported (LuaJIT's version, LuaSocket's, OpenSSL's, git's), exit 0.
2. `LUA_PATH` and `LUA_CPATH` that find nothing: LuaSocket MISSING,
   naming `libs/`, exit 1.
3. `RAO_NEEDS_BROKEN=crypto`: libcrypto MISSING, exit 1, the rest found.
4. A `PATH` holding only `luajit`: git, flock and the usual tools MISSING,
   Node and unshare absent, exit 1.
5. `--quiet`: nothing on a whole machine, only missing lines otherwise;
   an unknown argument refused with exit 2.

Needs no network; writes one link under `RAO_TEST_ROOT` (or `/tmp`) and
removes it.  `luajit src/install/tests/231-test-what-a-home-needs.lua
[project folder]`; prints PASS/FAIL and "counts".
