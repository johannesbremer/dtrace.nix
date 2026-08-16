{
  pkgs,
  dtracePackage,
  testsuite,
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

    test_timeout="''${DTRACE_TEST_TIMEOUT:-41}"
    long_cutoff="''${DTRACE_TEST_LONG_CUTOFF:-41}"
    coverage="''${DTRACE_TEST_COVERAGE:-core}"

    if [[ ! "$test_timeout" =~ ^[1-9][0-9]*$ ]]; then
      echo "DTRACE_TEST_TIMEOUT must be a positive integer" >&2
      exit 1
    fi
    if [[ ! "$long_cutoff" =~ ^[1-9][0-9]*$ ]]; then
      echo "DTRACE_TEST_LONG_CUTOFF must be a positive integer" >&2
      exit 1
    fi

    test_dir=$(mktemp -d -t dtrace-tests.XXXXXX)
    cleanup() {
      status=$?
      trap - EXIT
      if (( status != 0 )); then
        while IFS= read -r summary; do
          echo "===== $summary =====" >&2
          cat "$summary" >&2
        done < <(find "$test_dir/testsuite/test/log" -name runtest.sum -type f 2>/dev/null | LC_ALL=C sort)
      fi
      rm -rf "$test_dir"
      exit "$status"
    }
    trap cleanup EXIT

    cp -R ${testsuite} "$test_dir/testsuite"
    chmod -R u+w "$test_dir/testsuite"
    cd "$test_dir/testsuite"

    echo "Using execution policy: coverage=$coverage, per-test-timeout=$test_timeout, long-cutoff=$long_cutoff"

    export PKG_CONFIG_PATH=${dtracePackage}/lib/pkgconfig
    export TZDIR=${pkgs.tzdata}/share/zoneinfo
    export CC=${pkgs.stdenv.cc}/bin/cc
    export NM=${pkgs.binutils}/bin/nm
    export OBJCOPY=${pkgs.binutils}/bin/objcopy
    export OBJDUMP=${pkgs.binutils}/bin/objdump
    export READELF=${pkgs.binutils}/bin/readelf

    if (( $# == 0 )); then
      case "$coverage" in
        core|long|stress|expensive|all) ;;
        *)
          echo "DTRACE_TEST_COVERAGE must be core, long, stress, expensive, or all" >&2
          exit 1
          ;;
      esac

      test_roots=()
      for suite in unittest internals demo smoke stress expensive; do
        [[ -d "test/$suite" ]] && test_roots+=("test/$suite")
      done

      mapfile -t candidates < <(
        find "''${test_roots[@]}" -type f \
          \( -name '*.d' -o -name '*.sh' -o -name '*.c' \) \
          -print | LC_ALL=C sort -u
      )

      selected_tests=()
      for test_case in "''${candidates[@]}"; do
        declared_timeout=$(sed -nE 's/.*@@timeout:[[:space:]]*([0-9]+).*/\1/p' "$test_case" | head -n1)
        declared_coverage=$(sed -nE 's/.*@@nix-coverage:[[:space:]]*([a-z]+).*/\1/p' "$test_case" | head -n1)

        if [[ -n "$declared_coverage" ]]; then
          case "$declared_coverage" in
            core|long|stress|expensive) ;;
            *)
              echo "$test_case declares invalid Nix coverage: $declared_coverage" >&2
              exit 1
              ;;
          esac
          test_coverage=$declared_coverage
        else
          case "$test_case" in
            test/stress/*) test_coverage=stress ;;
            test/expensive/*) test_coverage=expensive ;;
            *)
              test_coverage=core
              if [[ -n "$declared_timeout" ]] && (( declared_timeout > long_cutoff )); then
                test_coverage=long
              fi
              ;;
          esac
        fi

        case "$coverage" in
          all)
            selected_tests+=("$test_case")
            ;;
          "$test_coverage")
            selected_tests+=("$test_case")
            ;;
        esac
      done

      if [[ -n "''${DTRACE_TEST_SHARD_INDEX:-}" || -n "''${DTRACE_TEST_SHARD_COUNT:-}" ]]; then
        if [[ ! "''${DTRACE_TEST_SHARD_INDEX:-}" =~ ^[0-9]+$ ]] ||
           [[ ! "''${DTRACE_TEST_SHARD_COUNT:-}" =~ ^[1-9][0-9]*$ ]] ||
           (( DTRACE_TEST_SHARD_INDEX >= DTRACE_TEST_SHARD_COUNT )); then
          echo "DTRACE_TEST_SHARD_INDEX must select a zero-based shard within DTRACE_TEST_SHARD_COUNT" >&2
          exit 1
        fi

        shard_tests=()
        for test_index in "''${!selected_tests[@]}"; do
          if (( test_index % DTRACE_TEST_SHARD_COUNT == DTRACE_TEST_SHARD_INDEX )); then
            shard_tests+=("''${selected_tests[$test_index]}")
          fi
        done
        selected_tests=("''${shard_tests[@]}")
        echo "DTrace $coverage shard $((DTRACE_TEST_SHARD_INDEX + 1))/$DTRACE_TEST_SHARD_COUNT: ''${#selected_tests[@]} cases"
      else
        echo "DTrace $coverage coverage: ''${#selected_tests[@]} cases"
      fi

      if (( ''${#selected_tests[@]} == 0 )); then
        echo "The selected coverage and shard contain no tests" >&2
        exit 1
      fi

      set -- --timeout="$test_timeout" "''${selected_tests[@]}"
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
