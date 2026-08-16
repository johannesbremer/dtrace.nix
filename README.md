# dtrace.nix

DTrace, declared.

A NixOS module that brings Oracle DTrace to your system — the BPF toolchain,
the `dtrace` binary, CUSE integration, the group, and the permissions — all
wired up through one flake.

---

## Install

Add it as a flake input:

```nix
{
  inputs.dtrace = {
    url = "github:johannesbremer/dtrace.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, dtrace, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        dtrace.nixosModules.default
        { programs.dtrace.enable = true; }
      ];
    };
  };
}
```

## Configure

```nix
programs.dtrace = {
  enable = true;

  # Who can run DTrace without sudo.
  users = [ "you" ];

  # Override the package if you're tracking a fork.
  package = dtrace.packages.${pkgs.system}.oracle-dtrace;
};
```

Members of `programs.dtrace.users` receive access through the `dtrace` group
and a group-restricted setuid wrapper. DTrace provides system-wide
observability, so this is a privileged role: only add fully trusted users.
Commands started with `dtrace -c` run as the calling user, not as root.
The `/dev/dtrace/helper` device remains available to all processes so they can
register USDT providers; access to that device does not grant tracing rights.

## Requirements

- A recent Linux kernel with BPF, BTF, ftrace, tracepoint, and FUSE/CUSE
  support. Stock NixOS kernels provide these facilities. The module loads CUSE;
  a NixOS module cannot add missing options to an already-built custom kernel.
- Root access, unless the account is listed in `programs.dtrace.users`.
- `nix-darwin` support is not planned — macOS already has DTrace.

No Oracle Linux packages, UEK kernel, or out-of-tree kernel patch are used.
The flake supports `x86_64-linux` and `aarch64-linux`.

## Tests

The ordinary package check builds DTrace and a USDT consumer fixture. The
NixOS VM check then verifies the module, privileged and unprivileged tracing,
syscall tracing, and USDT registration using that prebuilt fixture.

Upstream tests are divided by intent instead of being silently omitted:

- `upstream-core-*` contains tests with no declared long timeout, or a timeout
  of at most 41 seconds.
- `upstream-long-*` contains the remaining explicitly long tests.
- `upstream-stress-*` contains Oracle's stress suite and tests explicitly
  annotated with `@@nix-coverage: stress` because their intended probe scope is
  itself resource-intensive.

CI selects an explicit accelerated or emulated execution profile. Profiles
control QEMU acceleration, timeouts, guest RAM and swap, and shard counts;
none of those policies are inferred inside the test runner from the CPU
architecture. Guests receive explicit real-memory and swap budgets instead of
constraining valid allocations with a virtual-address-space limit.

For an interactive NixOS Lima guest, rebuild either `dtrace-lima-arm` or
`dtrace-lima-x86`. Those persistent configurations contain Lima's VirtIO disk
layout. The per-system `lima-test-iso` package is instead an ephemeral image
that installs the upstream runner and enables the services and kernel modules
that its capability checks exercise. This keeps storage policy separate from
host capabilities and allows local tests to run directly in a single Lima VM.
