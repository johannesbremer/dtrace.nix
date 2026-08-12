# Oracle DTrace for NixOS

This flake packages the upstream Linux DTrace implementation and provides a
NixOS module for its `dtprobed` USDT daemon. It builds the required bare-metal
eBPF GCC and Binutils toolchain as part of the Nix dependency graph; no Oracle
Linux packages or patched kernel are used.

The package is pinned to upstream DTrace 2.0.7-4 and is supported on
`x86_64-linux` and `aarch64-linux`.

## Use on NixOS

Add the repository to your flake inputs and import the module:

```nix
{
  inputs.dtrace-nix.url = "github:YOUR-ORG/dtrace-nix";

  outputs = { nixpkgs, dtrace-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [
        dtrace-nix.nixosModules.default
        {
          programs.dtrace.enable = true;
        }
      ];
    };
  };
}
```

After rebuilding, run DTrace as root:

```console
$ sudo dtrace -l
$ sudo dtrace -n 'syscall::openat:entry { @[execname] = count(); }'
```

The module installs `dtrace`, loads CUSE, installs the upstream udev rule for
`/dev/dtrace/helper`, and runs `dtprobed` for USDT registration.

To override the package while keeping the module integration:

```nix
programs.dtrace.package = dtrace-nix.packages.${pkgs.system}.oracle-dtrace;
```

## Build and test

```console
$ nix build .#oracle-dtrace
$ nix flake check
```

`nix flake check` builds the package and boots a NixOS VM. The VM test waits for
`dtprobed`, checks the CUSE helper device, executes a `BEGIN` clause, traces a
real `openat` syscall, then compiles, registers, and fires a USDT probe. The test
disables the KVM requirement so it can run under QEMU TCG in a Linux VM on an
Apple Silicon macOS host, although native KVM is substantially faster.

The derivations are Linux-only. From macOS, use a Linux remote builder or run
the commands in a Linux VM with the repository mounted into it.

## Kernel requirements

DTrace uses upstream Linux BPF facilities. A recent stock NixOS kernel has the
required BPF, BTF, kprobe, tracepoint, and FUSE support; an Oracle UEK kernel or
out-of-tree kernel patch is not required. Custom kernels must provide those
facilities. DTrace currently requires root privileges upstream.

The package carries a small compatibility patch for upstream's variable-length
USDT parser messages. It preserves the parser's seccomp confinement while
making the code work with Nixpkgs' `_FORTIFY_SOURCE=3` hardening.

## Why a flake?

The flake locks Nixpkgs and the exact upstream DTrace revision, exposes the
package and NixOS module through stable output names, and makes the Linux VM
integration test reproducible from macOS and Linux development hosts.

The upstream project is licensed under the Universal Permissive License 1.0.
