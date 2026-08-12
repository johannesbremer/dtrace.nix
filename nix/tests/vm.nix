{ pkgs, self }:

let
  dtracePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.oracle-dtrace;
  usdtProvider = pkgs.writeText "nixos-port.d" ''
    provider nixos_port {
      probe fire();
    };
  '';
  usdtSource = pkgs.writeText "nixos-port.c" ''
    #include <sys/sdt.h>

    int main(void)
    {
      DTRACE_PROBE(nixos_port, fire);
      return 0;
    }
  '';
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace";
  requiredFeatures.kvm = false;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.succeed("test -c /dev/dtrace/helper")
    machine.succeed("dtrace -V 2>&1 | grep -F 'dtrace: D 2.0.7'")
    machine.succeed("dtrace -l -n dtrace:::BEGIN")
    output = machine.succeed(
      "dtrace -q -n 'BEGIN { trace(\"nixos-dtrace-ok\"); exit(0); }'"
    )
    assert "nixos-dtrace-ok" in output

    output = machine.succeed(
      "dtrace -q -c '${pkgs.coreutils}/bin/cat /etc/os-release' "
      "-n 'syscall::openat:entry /pid == $target/ "
      "{ trace(\"nixos-syscall-ok\"); exit(0); }'"
    )
    assert "nixos-syscall-ok" in output

    machine.succeed(
      "${pkgs.stdenv.cc}/bin/cc -x c -std=gnu99 "
      "-I${dtracePackage}/lib/dtrace/include "
      "-c ${usdtSource} -o /tmp/nixos-port.o"
    )
    machine.succeed(
      "dtrace -G -s ${usdtProvider} /tmp/nixos-port.o "
      "-o /tmp/nixos-port-prov.o"
    )
    machine.succeed(
      "${pkgs.stdenv.cc}/bin/cc /tmp/nixos-port.o "
      "/tmp/nixos-port-prov.o -o /tmp/nixos-port"
    )
    output = machine.succeed(
      "dtrace -q -c /tmp/nixos-port "
      "-n 'nixos_port$target:::fire "
      "{ trace(\"nixos-usdt-ok\"); exit(0); }'"
    )
    assert "nixos-usdt-ok" in output
  '';
}
