{ pkgs, self }:

let
  upstreamTest = self.packages.${pkgs.stdenv.hostPlatform.system}.upstream-test;
  support = import ./upstream-support.nix { inherit pkgs; };
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream";
  requiredFeatures.kvm = false;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    environment.systemPackages = [ upstreamTest ];

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.useNixStoreImage = true;

    systemd.tmpfiles.rules = support.usrBinLinks;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")

    machine.succeed("dtrace-upstream-test")
  '';
}
