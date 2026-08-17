{
  pkgs,
  self,
  executionProfile,
  coverage,
  shardIndex,
  shardCount,
  testCases ? [ ],
}:

assert builtins.elem coverage [
  "core"
  "long"
  "stress"
];
assert shardIndex >= 0 && shardIndex < shardCount;

let
  upstreamTest = self.packages.${pkgs.stdenv.hostPlatform.system}.upstream-test;
  memorySize = executionProfile.memorySize.${coverage};
  swapSize = executionProfile.swapSize.${coverage};
  testEnvironment = pkgs.lib.concatStringsSep " " [
    "--setenv=DTRACE_TEST_COVERAGE=${coverage}"
    "--setenv=DTRACE_TEST_TIMEOUT=${toString executionProfile.perTestTimeout.${coverage}}"
    "--setenv=DTRACE_TEST_LONG_CUTOFF=${toString executionProfile.longTestCutoff}"
    "--setenv=DTRACE_TEST_SHARD_INDEX=${toString shardIndex}"
    "--setenv=DTRACE_TEST_SHARD_COUNT=${toString shardCount}"
  ];
  testArguments = pkgs.lib.escapeShellArgs testCases;
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream-${coverage}-${toString (shardIndex + 1)}-of-${toString shardCount}";
  inherit (executionProfile) requiredFeatures globalTimeout;

  nodes.machine = {
    imports = [
      self.nixosModules.default
      (import ./upstream-host.nix { inherit upstreamTest; })
    ];
    programs.dtrace.enable = true;

    virtualisation.memorySize = memorySize;
    virtualisation.cores = executionProfile.cores;
    virtualisation.qemu.forceAccel = pkgs.lib.mkForce executionProfile.qemuAcceleration;
    virtualisation.useNixStoreImage = true;
    virtualisation.emptyDiskImages = [
      {
        size = swapSize;
        driveConfig = {
          name = "swap";
          deviceExtraOpts.serial = "dtrace-swap";
        };
      }
    ];
  };

  testScript = ''
    import time

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("dtprobed.service")
    machine.wait_until_succeeds("test -c /dev/dtrace/helper")
    machine.wait_until_succeeds("test -b /dev/disk/by-id/virtio-dtrace-swap")
    machine.succeed("mkswap /dev/disk/by-id/virtio-dtrace-swap")
    machine.succeed("swapon /dev/disk/by-id/virtio-dtrace-swap")

    log_path = "/tmp/dtrace-upstream-test.log"
    machine.succeed(f"rm -f {log_path}")
    machine.succeed(
        "systemd-run --unit=dtrace-upstream-test --service-type=exec "
        "--slice=dtrace-test.slice "
        "--property=KillSignal=SIGKILL "
        "--property=StandardOutput=append:/tmp/dtrace-upstream-test.log "
        "--property=StandardError=append:/tmp/dtrace-upstream-test.log "
        "${testEnvironment} ${upstreamTest}/bin/dtrace-upstream-test ${testArguments}"
    )
    machine.wait_until_succeeds(f"test -e {log_path}")

    log_offset = 0
    while True:
        active_state = machine.succeed(
            "systemctl show --property=ActiveState --value dtrace-upstream-test.service"
        ).strip()
        log_size = int(machine.succeed(f"stat -c %s {log_path}").strip())
        if log_size > log_offset:
            output = machine.succeed(
                f"head -c {log_size} {log_path} | tail -c +{log_offset + 1}"
            )
            print(output, end="", flush=True)
            log_offset = log_size

        if active_state not in ("activating", "active", "deactivating"):
            break
        time.sleep(5)

    service_result = machine.succeed(
        "systemctl show --property=Result --value dtrace-upstream-test.service"
    ).strip()
    service_status = int(machine.succeed(
        "systemctl show --property=ExecMainStatus --value dtrace-upstream-test.service"
    ).strip())
    if service_result != "success" or service_status != 0:
        raise Exception(
            f"dtrace-upstream-test failed: result={service_result}, status={service_status}"
        )
  '';
}
