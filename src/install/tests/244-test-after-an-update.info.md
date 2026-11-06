# 244-test-after-an-update.lua

Issue 605's referees, through the stand-in service managers (242, with
`whoami` playing a user who is not root), a scratch `HOME`, system root
and list, in a loopback-only namespace (it runs itself again under
`unshare -rn`).

1. The list: two homes set up as services listed (service, kind, log,
   home), a third not; installing again adds no line and says `kept`;
   `<project>/installed-homes` is ignored by git; `--list`.
2. Restart: a systemd user home and a runit home, each with its own
   command (`sudo` for runit's only), each checked running, exit 0; the
   user service's home answers on its ports.
3. `sudo` asked once; "no" skips the runit home and says so, exit 1;
   `--yes` asks nothing; a `PATH` with no `sudo` is said, nothing
   restarted that needs it.
4. Not installed: `--check` says it, exit 1; a restart skips it, running
   nothing.
5. Logs: the service's log shown, by service or by home folder, and
   followed (a line written later appears); `--running` marks
   `[starter]` and `[gatherer <mailbox>]` lines; two listed homes and no
   argument: listed and asked, the chosen one's log alone; input that
   ends, exit 1.
6. The installer's last question: not asked while a listed home is not
   installed (that one named); under `--silent` nothing restarted unless
   `--restart-homes`; with it (and `--yes`) every listed home restarted.
