# 241-nixos.nix

A template of issue 604, filled by `src/install/236-service-files.lua` (its placeholders are listed there).  A NixOS module: `systemd.services."<service>"` with the same settings as the systemd system service, written to `<home>/service/<service>.nix` and imported from `configuration.nix` by a person.  It opens no firewall port (a home's ports change as rooms are made).

Every template starts with `# rao-chat home: <home>` (the line the installer reads to refuse a name already serving another home), runs `<project>/scripts/run-home <project> <home>` (603), appends its output to `<log folder>/<service>.log`, and restarts it when it fails.  The systemd ones are `KillMode=mixed` with `TimeoutStopSec=60`: the stop signal goes to the launcher alone, which stops the home's programs itself.
