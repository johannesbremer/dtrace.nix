{
  lib,
  modulesPath,
  pkgs,
  self,
  ...
}:

let
  support = import ../tests/upstream-support.nix { inherit pkgs; };
in

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "dtrace-nixos-x86";

  services.lima.enable = true;
  services.openssh.enable = true;

  programs.dtrace.enable = true;

  environment.systemPackages = [ self.packages.x86_64-linux.upstream-test ];
  systemd.tmpfiles.rules = support.usrBinLinks;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  security.sudo.wheelNeedsPassword = false;

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader.grub = {
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  fileSystems = {
    "/boot" = {
      device = lib.mkForce "/dev/vda1";
      fsType = "vfat";
    };
    "/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
      options = [
        "noatime"
        "nodiratime"
        "discard"
      ];
    };
  };

  system.stateVersion = "25.11";
}
