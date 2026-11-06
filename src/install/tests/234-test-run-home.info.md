# 234-test-run-home.lua

Issue 603's referees: `scripts/run-home` running a home made by the
installer on 127.0.0.2 (ports 46621 and 46622), in a loopback-only
namespace (it runs itself again under `unshare -rn` when it is not in
one, since the starter checks the public address).

1. The home runs: the gatherer is running, both ports accept, the
   starter's state names it.
2. SIGTERM: exit 0 within the wait, the gatherer `stopped = asked`, no
   process of the home left, the lines say so; a stale `stop` file does
   not stop a new run (still running 2 s later); SIGHUP stops it the same
   way.  (A background command ignores SIGINT, which then cannot be
   trapped, so SIGINT is not tried here.)
3. The device server killed: exit 1, saying so; the starter stopped, its
   gatherer `stopped = asked`.
4. A second launcher exits 1 saying the home is running; the first runs on.
5. A `PATH` without git: exit 1 naming it, nothing started; a line other
   than the three refused, naming it; a folder that is no home, exit 1.

Homes and RAM under `RAO_TEST_ROOT` (or `/tmp`), removed at the end;
everything it started is stopped.  `luajit
src/install/tests/234-test-run-home.lua [project folder]`.
