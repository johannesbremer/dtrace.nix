{ pkgs, self }:

let
  dtracePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.oracle-dtrace;
  usdtFixture = dtracePackage.tests.usdt-fixture;
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace";
  requiredFeatures.kvm = false;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace = {
      enable = true;
      users = [ "tracer" ];
    };

    users.users = {
      tracer.isNormalUser = true;
      outsider.isNormalUser = true;
    };

    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    virtualisation.useNixStoreImage = true;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")
    machine.wait_until_succeeds("test $(stat -c %a /dev/dtrace/helper) = 666")
    before = machine.succeed(
      "systemctl show --property=Before --value dtprobed.service"
    ).split()
    assert "basic.target" in before
    machine.succeed("test $(stat -c %U:%G:%a /run/wrappers/bin/dtrace) = root:dtrace:4550")
    machine.succeed("id -nG tracer | grep -qw dtrace")
    machine.fail("runuser -u outsider -- /run/wrappers/bin/dtrace -l")
    machine.succeed("dtrace -V 2>&1 | grep -F 'dtrace: D ${dtracePackage.version}'")
    machine.succeed("dtrace -l -n dtrace:::BEGIN")
    output = machine.succeed(
      "dtrace -q -n 'BEGIN { trace(\"nixos-dtrace-ok\"); exit(0); }'"
    )
    assert "nixos-dtrace-ok" in output

    output = machine.succeed(
      "runuser -u tracer -- /run/wrappers/bin/dtrace -q "
      "-n 'BEGIN { trace(\"nixos-unprivileged-ok\"); exit(0); }'"
    )
    assert "nixos-unprivileged-ok" in output

    tracer_uid = machine.succeed("id -u tracer").strip()
    output = machine.succeed(
      "runuser -u tracer -- /run/wrappers/bin/dtrace -q "
      "-c '${pkgs.coreutils}/bin/id -u' "
      "-n 'syscall::exit_group:entry /pid == $target/ { exit(0); }'"
    )
    assert tracer_uid in output

    output = machine.succeed(
      "dtrace -q -c '${pkgs.coreutils}/bin/cat /etc/os-release' "
      "-n 'syscall::openat:entry /pid == $target/ "
      "{ trace(\"nixos-syscall-ok\"); exit(0); }'"
    )
    assert "nixos-syscall-ok" in output

    output = machine.succeed(
      "dtrace -q -c ${usdtFixture}/bin/nixos-port "
      "-n 'nixos_port$target:::fire "
      "{ trace(\"nixos-usdt-ok\"); exit(0); }'"
    )
    assert "nixos-usdt-ok" in output

    machine.succeed(
      "systemd-run --unit=nixos-port-outsider --property=User=outsider "
      "${usdtFixture}/bin/nixos-port wait"
    )
    machine.wait_for_unit("nixos-port-outsider.service")
    outsider_pid = machine.succeed(
      "systemctl show --property=MainPID --value nixos-port-outsider.service"
    ).strip()
    machine.wait_until_succeeds(
      f"dtrace -l -p {outsider_pid} -n 'nixos_port$target:::fire'"
    )
    output = machine.succeed(
      f"dtrace -q -p {outsider_pid} "
      "-n 'nixos_port$target:::fire "
      "{ trace(\"nixos-unprivileged-usdt-ok\"); exit(0); }'"
    )
    assert "nixos-unprivileged-usdt-ok" in output
    machine.succeed("systemctl stop nixos-port-outsider.service")
  '';
}
