{ pkgs, self }:

let
  dtracePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.oracle-dtrace;
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream";
  requiredFeatures.kvm = false;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    environment.systemPackages = [
      dtracePackage.testsuite
      pkgs.bc
      pkgs.diffutils
      pkgs.file
      pkgs.findutils
      pkgs.gawk
      pkgs.gcc
      pkgs.gnugrep
      pkgs.gnumake
      pkgs.gnused
      pkgs.iproute2
      pkgs.jdk
      pkgs.netcat-openbsd
      pkgs.nfs-utils
      pkgs.perl
      pkgs.perf
      pkgs.pkg-config
      pkgs.procps
      pkgs.time
      pkgs.util-linux
      pkgs.valgrind
      pkgs.vim
      pkgs.wireshark-cli
      pkgs.xfsprogs
    ];

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.useNixStoreImage = true;

    systemd.tmpfiles.rules = [
      "L+ /usr/bin/awk - - - - ${pkgs.gawk}/bin/awk"
      "L+ /usr/bin/basename - - - - ${pkgs.coreutils}/bin/basename"
      "L+ /usr/bin/gawk - - - - ${pkgs.gawk}/bin/gawk"
      "L+ /usr/bin/gcc - - - - ${pkgs.gcc}/bin/gcc"
      "L+ /usr/bin/java - - - - ${pkgs.jdk}/bin/java"
      "L+ /usr/bin/javac - - - - ${pkgs.jdk}/bin/javac"
      "L+ /usr/bin/nm - - - - ${pkgs.binutils}/bin/nm"
      "L+ /usr/bin/nohup - - - - ${pkgs.coreutils}/bin/nohup"
      "L+ /usr/bin/objcopy - - - - ${pkgs.binutils}/bin/objcopy"
      "L+ /usr/bin/objdump - - - - ${pkgs.binutils}/bin/objdump"
      "L+ /usr/bin/perf - - - - ${pkgs.perf}/bin/perf"
      "L+ /usr/bin/perl - - - - ${pkgs.perl}/bin/perl"
      "L+ /usr/bin/readelf - - - - ${pkgs.binutils}/bin/readelf"
      "L+ /usr/bin/sed - - - - ${pkgs.gnused}/bin/sed"
      "L+ /usr/bin/sleep - - - - ${pkgs.coreutils}/bin/sleep"
      "L+ /usr/bin/time - - - - ${pkgs.time}/bin/time"
    ];
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")

    machine.succeed(
      "cp -R ${dtracePackage.testsuite}/share/dtrace/testsuite /tmp/dtrace-tests "
      "&& chmod -R u+w /tmp/dtrace-tests"
    )
    machine.succeed(
      "cd /tmp/dtrace-tests "
      "&& export PKG_CONFIG_PATH=${dtracePackage}/lib/pkgconfig "
      "CC=${pkgs.gcc}/bin/gcc NM=${pkgs.binutils}/bin/nm "
      "OBJCOPY=${pkgs.binutils}/bin/objcopy "
      "OBJDUMP=${pkgs.binutils}/bin/objdump "
      "READELF=${pkgs.binutils}/bin/readelf "
      "&& ./runtest.sh --use-installed --quiet --timeout=120 "
      "--skip-longer=41 --testsuites=unittest,internals,stress,demo,smoke"
    )
  '';
}
