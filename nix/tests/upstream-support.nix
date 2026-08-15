{ pkgs }:

{
  runtimeInputs = [
    pkgs.bash
    pkgs.bc
    pkgs.coreutils
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
    pkgs.openssh
    pkgs.perl
    pkgs.perf
    pkgs.pkg-config
    pkgs.procps
    pkgs.systemd
    pkgs.time
    pkgs.tzdata
    pkgs.util-linux
    pkgs.valgrind
    pkgs.vim
    pkgs.which
    pkgs.wireshark-cli
    pkgs.xfsprogs
  ];

  usrBinLinks = [
    "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    "L+ /bin/cat - - - - ${pkgs.coreutils}/bin/cat"
    "L+ /bin/date - - - - ${pkgs.coreutils}/bin/date"
    "L+ /bin/echo - - - - ${pkgs.coreutils}/bin/echo"
    "L+ /bin/kill - - - - ${pkgs.coreutils}/bin/kill"
    "L+ /bin/ls - - - - ${pkgs.coreutils}/bin/ls"
    "L+ /bin/sleep - - - - ${pkgs.coreutils}/bin/sleep"
    "L+ /bin/true - - - - ${pkgs.coreutils}/bin/true"
    "L+ /usr/bin/awk - - - - ${pkgs.gawk}/bin/awk"
    "L+ /usr/bin/bash - - - - ${pkgs.bash}/bin/bash"
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
    "L+ /usr/bin/tshark - - - - ${pkgs.wireshark-cli}/bin/tshark"
  ];
}
