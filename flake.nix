{
  description = "Oracle DTrace for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dtrace-src = {
      url = "github:oracle/dtrace/55ebd5f81bf2e10142585a3a43536a99f5f9b0d4";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      dtrace-src,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      overlays.default = final: _prev: {
        dtrace-bpf-binutils = final.callPackage ./nix/bpf-binutils.nix { };
        dtrace-bpf-gcc = final.callPackage ./nix/bpf-gcc.nix {
          bpf-binutils = final.dtrace-bpf-binutils;
        };
        oracle-dtrace = final.callPackage ./nix/package.nix {
          src = dtrace-src;
          bpf-binutils = final.dtrace-bpf-binutils;
          bpf-gcc = final.dtrace-bpf-gcc;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          default = pkgs.oracle-dtrace;
          inherit (pkgs) oracle-dtrace dtrace-bpf-binutils dtrace-bpf-gcc;
        }
      );

      nixosModules.default = import ./nix/module.nix { inherit self; };
      nixosModules.dtrace = self.nixosModules.default;

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          package = pkgs.oracle-dtrace;
          vm = import ./nix/tests/vm.nix {
            inherit pkgs self;
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
