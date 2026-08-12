{
  pkgs,
  dtracePackage,
}:

let
  support = import ./upstream-support.nix { inherit pkgs; };
in

pkgs.writeShellApplication {
  name = "dtrace-upstream-test";
  runtimeInputs = support.runtimeInputs;

  text = ''
    if (( EUID != 0 )); then
      echo "dtrace-upstream-test must run as root" >&2
      exit 1
    fi

    if ! systemctl is-active --quiet dtprobed.service; then
      echo "dtprobed.service is not running" >&2
      exit 1
    fi

    if [[ ! -c /dev/dtrace/helper ]]; then
      echo "/dev/dtrace/helper is not available" >&2
      exit 1
    fi

    test_dir=$(mktemp -d -t dtrace-tests.XXXXXX)
    trap 'rm -rf "$test_dir"' EXIT

    cp -R ${dtracePackage.testsuite}/share/dtrace/testsuite "$test_dir/testsuite"
    chmod -R u+w "$test_dir/testsuite"
    cd "$test_dir/testsuite"

    export PKG_CONFIG_PATH=${dtracePackage}/lib/pkgconfig
    export CC=${pkgs.gcc}/bin/gcc
    export NM=${pkgs.binutils}/bin/nm
    export OBJCOPY=${pkgs.binutils}/bin/objcopy
    export OBJDUMP=${pkgs.binutils}/bin/objdump
    export READELF=${pkgs.binutils}/bin/readelf

    if (( $# == 0 )); then
      set -- \
        --quiet \
        --timeout=41 \
        --skip-longer=41 \
        --testsuites=unittest,internals,stress,demo,smoke
    fi

    ./runtest.sh --use-installed "$@"
  '';
}
