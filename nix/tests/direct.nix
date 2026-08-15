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

    if [[ -n "''${DTRACE_TEST_VMEM_LIMIT_KIB:-}" ]]; then
      if [[ ! "$DTRACE_TEST_VMEM_LIMIT_KIB" =~ ^[1-9][0-9]*$ ]]; then
        echo "DTRACE_TEST_VMEM_LIMIT_KIB must be a positive integer" >&2
        exit 1
      fi

      ulimit -v "$DTRACE_TEST_VMEM_LIMIT_KIB"
      echo "Limited each upstream test process to $DTRACE_TEST_VMEM_LIMIT_KIB KiB of virtual memory"
    fi

    test_dir=$(mktemp -d -t dtrace-tests.XXXXXX)
    trap 'rm -rf "$test_dir"' EXIT

    cp -R ${dtracePackage.testsuite}/share/dtrace/testsuite "$test_dir/testsuite"
    chmod -R u+w "$test_dir/testsuite"
    cd "$test_dir/testsuite"

    arch=$(uname -m)
    test_timeout=41
    if [[ "$arch" == aarch64 ]]; then
      test_timeout=120
    fi
    echo "Using a $test_timeout second per-test timeout on $arch"

    export PKG_CONFIG_PATH=${dtracePackage}/lib/pkgconfig
    export TZDIR=${pkgs.tzdata}/share/zoneinfo
    export CC=${pkgs.gcc}/bin/gcc
    export NM=${pkgs.binutils}/bin/nm
    export OBJCOPY=${pkgs.binutils}/bin/objcopy
    export OBJDUMP=${pkgs.binutils}/bin/objdump
    export READELF=${pkgs.binutils}/bin/readelf

    if [[ -n "''${DTRACE_TEST_SHARD_INDEX:-}" || -n "''${DTRACE_TEST_SHARD_COUNT:-}" ]]; then
      if [[ ! "''${DTRACE_TEST_SHARD_INDEX:-}" =~ ^[0-9]+$ ]] ||
         [[ ! "''${DTRACE_TEST_SHARD_COUNT:-}" =~ ^[1-9][0-9]*$ ]] ||
         (( DTRACE_TEST_SHARD_INDEX >= DTRACE_TEST_SHARD_COUNT )); then
        echo "DTRACE_TEST_SHARD_INDEX must select a zero-based shard within DTRACE_TEST_SHARD_COUNT" >&2
        exit 1
      fi

      test_roots=()
      for suite in unittest internals stress demo smoke; do
        [[ -d "test/$suite" ]] && test_roots+=("test/$suite")
      done

      mapfile -t all_tests < <(
        find "''${test_roots[@]}" -type f \
          \( -name '*.d' -o -name '*.sh' -o -name '*.c' \) \
          -print | LC_ALL=C sort -u
      )

      shard_tests=()
      for test_index in "''${!all_tests[@]}"; do
        if (( test_index % DTRACE_TEST_SHARD_COUNT == DTRACE_TEST_SHARD_INDEX )); then
          shard_tests+=("''${all_tests[$test_index]}")
        fi
      done

      echo "DTrace upstream shard $((DTRACE_TEST_SHARD_INDEX + 1))/$DTRACE_TEST_SHARD_COUNT: ''${#shard_tests[@]} cases"
      set -- \
        --timeout="$test_timeout" \
        --skip-declared-longer=41 \
        "''${shard_tests[@]}"
    elif (( $# == 0 )); then
      set -- \
        --timeout="$test_timeout" \
        --skip-declared-longer=41 \
        --testsuites=unittest,internals,stress,demo,smoke
    fi

    test_output="$test_dir/test-output.log"
    set +e
    ./runtest.sh --use-installed "$@" 2>&1 | tee "$test_output"
    test_status=''${PIPESTATUS[0]}
    set -e

    if (( test_status != 0 )); then
      exit "$test_status"
    fi

    if grep -Eq '^[0-9]+ cases \([0-9]+ PASS, [0-9]+ FAIL, [1-9][0-9]* XPASS,' "$test_output"; then
      echo "An upstream expected failure unexpectedly passed" >&2
      exit 1
    fi
  '';
}
