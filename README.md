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

## Requirements

- A recent Linux kernel with BPF, BTF, ftrace, tracepoint, and FUSE/CUSE
  support. Stock NixOS kernels provide these facilities. The module loads CUSE;
  a NixOS module cannot add missing options to an already-built custom kernel.
- Root access, unless the account is listed in `programs.dtrace.users`.
- `nix-darwin` support is not planned — macOS already has DTrace.

No Oracle Linux packages, UEK kernel, or out-of-tree kernel patch are used.
The flake supports `x86_64-linux` and `aarch64-linux`.
