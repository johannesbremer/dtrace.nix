{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dtrace;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.oracle-dtrace;
in
{
  options.programs.dtrace = {
    enable = lib.mkEnableOption "Oracle DTrace for Linux";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "dtrace.packages.${pkgs.system}.oracle-dtrace";
      description = "The Oracle DTrace package to install and use for dtprobed.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users allowed to run DTrace without sudo. DTrace has system-wide
        observability and should only be granted to fully trusted users.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.dtrace.members = cfg.users;

    services.udev.extraRules = ''
      KERNEL=="dtrace/helper", MODE="0666"
    '';

    boot.kernelModules = [ "cuse" ];

    security.wrappers.dtrace = lib.mkIf (cfg.users != [ ]) {
      source = "${cfg.package}/bin/dtrace";
      owner = "root";
      group = "dtrace";
      permissions = "u+rx,g+rx,o-";
      setuid = true;
    };

    systemd.services.dtprobed = {
      description = "DTrace USDT probe creation daemon";
      documentation = [ "man:dtprobed(8)" ];
      wantedBy = [ "basic.target" ];
      before = [ "basic.target" ];
      wants = [
        "sysinit.target"
        "sockets.target"
        "paths.target"
      ];
      after = [
        "sysinit.target"
        "sockets.target"
        "paths.target"
        "systemd-udevd.service"
        "systemd-modules-load.service"
      ];
      requires = [
        "sysinit.target"
        "systemd-udevd.service"
      ];
      restartTriggers = [ cfg.package ];

      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "notify";
        ExecStart = "${cfg.package}/bin/dtprobed -F";
        Restart = "on-failure";
        RestartPreventExitStatus = "1";
        RuntimeDirectory = "dtrace";
        RuntimeDirectoryPreserve = "restart";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = false;
        PrivateNetwork = true;
        ProtectControlGroups = true;
      };
    };
  };
}
