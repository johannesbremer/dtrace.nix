# dtrace.nix

DTrace, declared.

A NixOS module that brings Oracle DTrace to your system — the BPF toolchain,
the `dtrace` binary, CUSE integration, the group, and the permissions — all
wired up through one option.

```nix
programs.dtrace.enable = true;
```

That's it. Reboot, and `sudo dtrace -l` works.

---

## Install

Add it as a flake input:

```nix
{
  inputs.dtrace.url = "github:yourname/dtrace.nix";

  outputs = { self, nixpkgs, dtrace, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
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

## Requirements

- A recent Linux kernel with BPF, BTF, ftrace, tracepoint, and FUSE/CUSE
  support. Stock NixOS kernels provide these facilities. The module loads CUSE;
  a NixOS module cannot add missing options to an already-built custom kernel.
- Root access, unless the account is listed in `programs.dtrace.users`.
- `nix-darwin` support is not planned — macOS already has DTrace.

No Oracle Linux packages, UEK kernel, or out-of-tree kernel patch are used.
The flake supports `x86_64-linux` and `aarch64-linux`.

## Build and test

```console
$ nix build .#oracle-dtrace
$ nix flake check
```

The integration check boots NixOS and exercises root and group-authorized
tracing, a real `openat` syscall, and a compiled USDT probe. The upstream check
runs Oracle's installed regression harness across its `unittest`, `internals`,
`stress`, `demo`, and `smoke` suites in upstream's quick mode. This excludes
only cases annotated to run longer than Oracle's default 41-second timeout.
Both VM tests can fall back to QEMU TCG, which makes them runnable from Linux
VMs on macOS when KVM is unavailable.

The package carries a small compatibility patch for upstream's variable-length
USDT parser messages. It preserves the parser's seccomp confinement while
making the code work with Nixpkgs' `_FORTIFY_SOURCE=3` hardening.

Oracle DTrace is licensed under the Universal Permissive License 1.0.
