# 236-service-files.lua

A home's service files (issue 604): the name, the templates filled, and
whether an installed file serves a home.

    luajit src/install/236-service-files.lua <project> name <home>
    luajit src/install/236-service-files.lua <project> fill <template> <out> key=value ...
    luajit src/install/236-service-files.lua <project> check <template> key=value ...
    luajit src/install/236-service-files.lua <project> names-home <file> <home>

Keys: `service`, `user`, `log_dir`, `home`, `project`.  Each value is
put into a template in the quoting its syntax reads:

| placeholder | what |
|---|---|
| `@SERVICE@`, `@USER@`, `@LOG@` | bare: held to plain characters (a log folder of letters, digits, `.`, `_`, `-`, `/`) |
| `@HOME_COMMENT@` | the home's path, bare, on the `# rao-chat home:` line `names-home` reads |
| `@EXEC_SYSTEMD@` | run-home, the program folder and the home as three double-quoted `ExecStart=` words (`\`, `"`, `%`, `$` escaped) |
| `@EXEC_NIX@`, `@LOG_NIX@` | the same inside a nix `"..."` string |
| `@RUN_HOME_SH@`, `@PROJECT_SH@`, `@HOME_SH@`, `@LOG_SH@` | single-quoted sh words |
| `@OPENRC_COMMAND@`, `@OPENRC_ARGS@` | bare; OpenRC evals them, so only paths of letters, digits, `.`, `_`, `+`, `-`, `/` are filled, and any other refused |

A value that cannot be carried, a placeholder no value fills, or one left
after filling: nothing written (an `<out>` from before removed), exit 1,
the reason said.  Paths may hold any character but a control character.
The name is `rao-chat-` and the home's path with slashes as dashes, the
leading one dropped, any character a service name cannot hold as `_`.
