# 246-phase-6-scenes.lua

The scenes of the phase 6 demo (issue 606), loaded by 245.  One world:
two homes made by `scripts/install-home` (`--silent`), A on 127.0.0.2
and B on 127.0.0.3, each set up as a systemd user service; the
service-manager commands are 242's stand-ins on a scratch `PATH`, `HOME`
a scratch folder, the logs and the list of homes (605) scratch too.  The
stand-in `systemctl` runs each unit's `ExecStart` as written, in a bare
environment.

| scene | shows |
|---|---|
| `needs` | 230's lines for this machine (601) |
| `install` | both installs; A's asked and two stated config lines with their comments; A's unit; the list |
| `again` | both installed again: every file of both homes, the units and the list byte for byte the same |
| `room` | one room between them (002's `make_room`, 041's `add_member`: a stand-in, no viewer makes rooms), and the demo's timing set with 232 as a hand edit |
| `services` | `systemctl --user start` for each: active, the launcher's bare environment, its log lines, the starter, device server and two gatherers running, the ports answering |
| `talk` | a phone paired with A (189, 190) writes with 183; A files it and B's room log and RAM inbox hold it |
| `update` | `restart-homes --yes`: both restarted, each a new launcher; B types, A has it, the phone catches up after |
| `stop` | `systemctl --user stop` for each: status 0, the launcher's last line, every gatherer `stopped = asked`, nothing left, the ports closed |

Each scene raises an error when what it shows did not happen.  Printed
paths name the demo's folder `<demo>` and the program folder
`<project>`.  `finish` stops each service still running, kills anything
else under the demo's folder (found through `/proc`), and removes it.
