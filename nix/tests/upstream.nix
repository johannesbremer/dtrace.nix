{
  pkgs,
  self,
  shardIndex ? null,
  shardCount ? null,
}:

assert (shardIndex == null) == (shardCount == null);
assert shardIndex == null || (shardIndex >= 0 && shardIndex < shardCount);

let
  upstreamTest = self.packages.${pkgs.stdenv.hostPlatform.system}.upstream-test;
  support = import ./upstream-support.nix { inherit pkgs; };
  shardEnvironment = pkgs.lib.optionalString (shardIndex != null) (
    "DTRACE_TEST_SHARD_INDEX=${toString shardIndex} "
    + "DTRACE_TEST_SHARD_COUNT=${toString shardCount} "
  );
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream";
  requiredFeatures.kvm = false;
  globalTimeout = 105 * 60;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    environment.systemPackages = [ upstreamTest ];

    virtualisation.memorySize = 6144;
    virtualisation.cores = 4;
    virtualisation.useNixStoreImage = true;

    systemd.tmpfiles.rules = support.usrBinLinks;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")

    machine.succeed("${shardEnvironment}dtrace-upstream-test")
  '';
}
