{
  pkgs,
  self,
  shardIndex ? null,
  shardCount ? null,
}:

assert (shardIndex == null) == (shardCount == null);
assert shardIndex == null || (shardIndex >= 0 && shardIndex < shardCount);

let
  requireKvm = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  upstreamTest = self.packages.${pkgs.stdenv.hostPlatform.system}.upstream-test;
  support = import ./upstream-support.nix { inherit pkgs; };
  shardEnvironment = pkgs.lib.optionalString (shardIndex != null) (
    "DTRACE_TEST_SHARD_INDEX=${toString shardIndex} "
    + "DTRACE_TEST_SHARD_COUNT=${toString shardCount} "
  );
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream";
  requiredFeatures.kvm = requireKvm;
  globalTimeout = 105 * 60;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    environment.systemPackages = [ upstreamTest ];

    virtualisation.memorySize = 8192;
    virtualisation.cores = 4;
    virtualisation.qemu.forceAccel = pkgs.lib.mkForce requireKvm;
    virtualisation.useNixStoreImage = true;
    virtualisation.emptyDiskImages = [
      {
        size = 2048;
        driveConfig = {
          name = "swap";
          deviceExtraOpts.serial = "dtrace-swap";
        };
      }
    ];

    systemd.tmpfiles.rules = support.usrBinLinks;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")
    machine.wait_until_succeeds("test -b /dev/disk/by-id/virtio-dtrace-swap")
    machine.succeed("mkswap /dev/disk/by-id/virtio-dtrace-swap")
    machine.succeed("swapon /dev/disk/by-id/virtio-dtrace-swap")

    machine.succeed("${shardEnvironment}dtrace-upstream-test")
  '';
}
