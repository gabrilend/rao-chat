# 230-what-a-home-needs.lua

What a home needs on this machine, found or named (issue 601):
`luajit src/install/230-what-a-home-needs.lua [project folder] [--quiet]`.
It loads each thing as the home's programs load it and prints one line
for each: `found` with the version it reported, `MISSING` (required), or
`absent` (needed only by the tools it names).  It fetches and builds
nothing.

| need | checked by | required |
|---|---|---|
| LuaJIT | `jit.version`, `ffi`, `bit` (the check runs on it) | yes |
| LuaSocket | `require("socket")`, the project's `libs/` first (001); its version and where `socket.core` is; a note when it was found through `LUA_CPATH` | yes |
| libcrypto | `ffi.load("crypto")`, `OpenSSL_version`, SHA-256 of `abc` against its known digest, `EVP_aes_256_gcm` | yes |
| git | `git --version` | yes |
| flock | on the path (603's lock) | yes |
| setsid | on the path (603 starts the home's programs with it) | yes |
| tools | `find sort ls mkdir rm mv cp touch chmod stat kill sleep` runnable by the shell | yes |
| RAM folder | `/dev/shm` written to | no |
| ss/netstat | on the path (602's port check) | no |
| Node 22+ | `node --version` | no (web referees, phase 4 demo) |
| unshare | on the path | no (referees, demos) |

Exit status 0 when every required thing is found, 1 otherwise, 2 for a
mistaken argument.  `--quiet` prints only lines not `found`.
`RAO_NEEDS_BROKEN=crypto` (a library that cannot load in place of
libcrypto) is the referees' broken version.
