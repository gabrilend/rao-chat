# rao-chat home: @HOME_COMMENT@
# A NixOS module running this home as a service (issue 604), written by
# scripts/install-home; re-running the installer writes it again.  Import
# it from configuration.nix and run nixos-rebuild switch.  The launcher
# (scripts/run-home) finds luajit through the home's environment file, so
# re-run the installer after an upgrade moves it.  No firewall port is
# opened here: a home's ports change as rooms are made (the installer
# names them).
{ ... }:
{
  systemd.services."@SERVICE@" = {
    description = "rao-chat home @SERVICE@";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "@USER@";
      ExecStart = "@EXEC_NIX@";
      Restart = "on-failure";
      RestartSec = 5;
      KillMode = "mixed";
      TimeoutStopSec = 60;
      StandardOutput = "append:@LOG_NIX@";
      StandardError = "append:@LOG_NIX@";
    };
  };
}
