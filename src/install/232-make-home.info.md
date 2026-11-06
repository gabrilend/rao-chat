# 232-make-home.lua

Makes a home, or brings one up to date, through the home's own code
(issue 602); the installer's writer.

    luajit src/install/232-make-home.lua <project> <home> --show
    luajit src/install/232-make-home.lua <project> <home> [key=value ...]

`--show` prints `config <key> = <value>` for each setting and `mailbox
<kind> <port> <tag>` for each mailbox of an existing home (nothing for no
home), and writes nothing.

Otherwise each argument is a declared setting or `direct-port=<port>`.
Everything is checked first (an undeclared name, a port out of range, a
bad `git.home-name` by 172's rule, the device port equal to a mailbox's,
the direct port equal to another mailbox's, a missing folder above the
home): one problem and nothing is written, exit 1.  Then 002's
`open_home`, and one line per step:

| line | when |
|---|---|
| `set` | a given setting was absent: added under a comment with its question |
| `changed <key> <old> -> <new>` | it held another value: 002's `set_config`, in place |
| `kept` | it already held this value (or the mailbox this port) |
| `stated` | a declared setting not in the file: the first variant of its options file, under its question and the number of variants |
| `made` / `moved` | the direct-message mailbox made on `direct-port`, or moved to it |

Every addition is read back by 002 before it counts.
