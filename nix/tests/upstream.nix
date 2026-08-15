{
  pkgs,
  self,
  shardIndex ? null,
  shardCount ? null,
}:

assert (shardIndex == null) == (shardCount == null);
assert shardIndex == null || (shardIndex >= 0 && shardIndex < shardCount);

let
  requireKvm = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  upstreamTest = self.packages.${pkgs.stdenv.hostPlatform.system}.upstream-test;
  support = import ./upstream-support.nix { inherit pkgs; };
  shardEnvironment = pkgs.lib.optionalString (shardIndex != null) (
    "--setenv=DTRACE_TEST_SHARD_INDEX=${toString shardIndex} "
    + "--setenv=DTRACE_TEST_SHARD_COUNT=${toString shardCount} "
  );
  testEnvironment =
    shardEnvironment + "--setenv=DTRACE_TEST_VMEM_LIMIT_KIB=${toString (4 * 1024 * 1024)} ";
in

pkgs.testers.runNixOSTest {
  name = "oracle-dtrace-upstream";
  requiredFeatures.kvm = requireKvm;
  globalTimeout = 105 * 60;

  nodes.machine = {
    imports = [ self.nixosModules.default ];
    programs.dtrace.enable = true;

    boot.kernelModules = [ "tun" ];
    services.nfs.server.enable = true;
    services.openssh.enable = true;

    environment.systemPackages = [ upstreamTest ];

    virtualisation.memorySize = 8192;
    virtualisation.cores = 4;
    virtualisation.qemu.forceAccel = pkgs.lib.mkForce requireKvm;
    virtualisation.useNixStoreImage = true;
    virtualisation.emptyDiskImages = [
      {
        size = 8192;
        driveConfig = {
          name = "swap";
          deviceExtraOpts.serial = "dtrace-swap";
        };
      }
    ];

    systemd.tmpfiles.rules = support.usrBinLinks;
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
        "--property=KillSignal=SIGKILL "
        "--property=StandardOutput=append:/tmp/dtrace-upstream-test.log "
        "--property=StandardError=append:/tmp/dtrace-upstream-test.log "
        "${testEnvironment}${upstreamTest}/bin/dtrace-upstream-test"
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
