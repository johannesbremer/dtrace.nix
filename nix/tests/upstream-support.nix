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
    pkgs.stdenv.cc
    pkgs.gnugrep
    pkgs.gnumake
    pkgs.gnused
    pkgs.iproute2
    pkgs.iputils
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
    pkgs.xxd
  ];
}
