{
  pkgs,
  dtracePackage,
  expectedFailures,
  skippedTests,
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

    expected_failure_count=0
    arch=$(uname -m)
    test_timeout=41
    if [[ "$arch" == aarch64 ]]; then
      test_timeout=120
    fi
    echo "Using a $test_timeout second per-test timeout on $arch"

    while IFS= read -r expected_test || [[ -n "$expected_test" ]]; do
      case "$expected_test" in
        "" | \#*) continue ;;
      esac

      if [[ ! -f "$expected_test" ]]; then
        echo "Expected-failure baseline names a missing test: $expected_test" >&2
        exit 1
      fi

      expected_base=''${expected_test%.d}
      expected_base=''${expected_base%.sh}
      expected_base=''${expected_base%.c}
      expected_marker="$expected_base.$arch.x"
      rm -f "$expected_marker"
      touch "$expected_marker"
      ((expected_failure_count += 1))
    done < ${expectedFailures}
    echo "Applied $expected_failure_count expected failures for $arch"

    skipped_test_count=0
    while IFS= read -r skipped_test || [[ -n "$skipped_test" ]]; do
      case "$skipped_test" in
        "" | \#*) continue ;;
      esac

      if [[ ! -f "$skipped_test" ]]; then
        echo "Skip baseline names a missing test: $skipped_test" >&2
        exit 1
      fi

      if grep -Fxq "$skipped_test" ${expectedFailures}; then
        echo "Test is both expected to fail and skipped: $skipped_test" >&2
        exit 1
      fi

      skipped_base=''${skipped_test%.d}
      skipped_base=''${skipped_base%.sh}
      skipped_base=''${skipped_base%.c}
      skipped_marker="$skipped_base.$arch.x"
      rm -f "$skipped_marker"
      printf '%s\n' \
        '#!/bin/sh' \
        'echo "skipped by dtrace.nix: unstable under constrained CI"' \
        'exit 2' > "$skipped_marker"
      chmod 0755 "$skipped_marker"
      echo "Explicitly skipping $skipped_test on $arch: unstable under constrained CI"
      ((skipped_test_count += 1))
    done < ${skippedTests}
    echo "Applied $skipped_test_count explicit skips for $arch"

    export PKG_CONFIG_PATH=${dtracePackage}/lib/pkgconfig
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
      echo "DTrace upstream tests unexpectedly passed; remove fixed tests from the expected-failure baseline" >&2
      exit 1
    fi
  '';
}
