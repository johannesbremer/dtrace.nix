{
  persistent ? true,
}:

{
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "dtrace-nixos-${pkgs.stdenv.hostPlatform.parsed.cpu.name}";

  services.lima.enable = true;
  services.openssh.enable = true;

  programs.dtrace.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  security.sudo.wheelNeedsPassword = false;

  boot.loader.grub = lib.mkIf persistent {
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  fileSystems = lib.mkIf persistent {
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
