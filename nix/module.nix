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
      defaultText = lib.literalExpression "dtrace-nix.packages.${pkgs.system}.oracle-dtrace";
      description = "The Oracle DTrace package to install and use for dtprobed.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.udev.packages = [ cfg.package ];

    boot.kernelModules = [ "cuse" ];

    systemd.services.dtprobed = {
      description = "DTrace USDT probe creation daemon";
      documentation = [ "man:dtprobed(8)" ];
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-udevd.service"
        "systemd-modules-load.service"
      ];
      requires = [ "systemd-udevd.service" ];
      restartTriggers = [ cfg.package ];

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
