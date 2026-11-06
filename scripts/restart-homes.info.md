# restart-homes

Restarts the homes installed as services from this program folder, so
each runs the code it now holds (issue 605): an update (a `git pull` of
the program folder) is finished only when every home has restarted.

    scripts/restart-homes [--yes] [NAME...]
    scripts/restart-homes --check [NAME...]
    scripts/restart-homes --list
    scripts/restart-homes --add SERVICE KIND LOG HOME

The list is `<project>/installed-homes` (or `--homes-list=FILE`), ignored
by git, one line a home: `<service> <kind> <log file> <home folder>`, the
home being the rest of the line.  The installer adds the lines (`--add`
replaces a line of the same service or home, and says `listed`,
`changed` or `kept`).

| kind | installed when | restart | running when |
|---|---|---|---|
| `systemd-user` | `~/.config/systemd/user/<service>.service` | `systemctl --user restart` | `systemctl --user is-active` |
| `systemd-system`, `nixos` | `<root>/etc/systemd/system/<service>.service` | `sudo systemctl restart` | `systemctl is-active` |
| `runit` | `<root>/etc/sv/<service>/run` | `sudo sv restart` | `sv status` says `run:` |
| `openrc` | `<root>/etc/init.d/<service>` | `sudo rc-service <service> restart` | `rc-service <service> status` |

`<root>` is `--system-root` (`/`).  A home whose service is not installed
is said and skipped.  `sudo` is asked for once for the run (`--yes`: not
asked), not used when this is root; with no `sudo` here those are said
and skipped.  Each restarted service is checked running (up to 10 s).
Exit 0 when every one asked for restarted and is running (`--check`:
installed), 1 otherwise, 2 a mistaken argument.
