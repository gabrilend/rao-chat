# 150-public-address.lua

The home's public address, looked up from outside (issue 212).
- `OPERATORS`: rmail's sources. These are OpenDNS, Cloudflare and Google,
  two resolvers each.
- `question`, `answer`, `ask`: one DNS question over UDP (LuaSocket) and
  its answer, A or TXT.
- `check`: asks the sources in order. A new address counts only when a
  different operator gives the same one. "Nobody answered" is reported
  apart from "no change".
- `new_watcher`: runs a check at `start`. After that, `tick` runs one at
  a random point between `address.recheck-earliest` and
  `address.recheck-latest`, drawn from `/dev/urandom`. The wait is
  shorter after silence or a disagreement. On a confirmed change it
  writes the fact file and calls `on_move`, which sends fresh hellos.
- `settings`, `random`.

The home starter (211) runs the watcher.
