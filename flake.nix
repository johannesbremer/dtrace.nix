{
  description = "Oracle DTrace for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-lima = {
      url = "github:nixos-lima/nixos-lima/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dtrace-src = {
      url = "github:oracle/dtrace/55ebd5f81bf2e10142585a3a43536a99f5f9b0d4";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-lima,
      dtrace-src,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        }
      );
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
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.oracle-dtrace;
          inherit (pkgs) oracle-dtrace dtrace-bpf-binutils dtrace-bpf-gcc;
          upstream-test = import ./nix/tests/direct.nix {
            inherit pkgs;
            dtracePackage = pkgs.oracle-dtrace;
            expectedFailures =
              if system == "aarch64-linux" then
                ./nix/tests/expected-failures/aarch64-linux.txt
              else
                ./nix/tests/expected-failures/x86_64-linux.txt;
          };
        }
      );

      apps = forAllSystems (system: {
        upstream-test = {
          type = "app";
          program = "${self.packages.${system}.upstream-test}/bin/dtrace-upstream-test";
          meta.description = "Run Oracle DTrace's upstream Linux test suite";
        };
      });

      nixosModules.default = import ./nix/module.nix { inherit self; };
      nixosModules.dtrace = self.nixosModules.default;

      nixosConfigurations.dtrace-lima-x86 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit self; };
        modules = [
          nixos-lima.nixosModules.lima
          self.nixosModules.default
          ./nix/hosts/lima-x86.nix
        ];
      };

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          upstreamShardCount = if system == "x86_64-linux" then 4 else 16;
          upstreamShards = builtins.listToAttrs (
            map (shardIndex: {
              name = "upstream-${toString (shardIndex + 1)}";
              value = import ./nix/tests/upstream.nix {
                inherit pkgs self shardIndex;
                shardCount = upstreamShardCount;
              };
            }) (nixpkgs.lib.range 0 (upstreamShardCount - 1))
          );
        in
        {
          package = pkgs.oracle-dtrace;
          upstream = import ./nix/tests/upstream.nix {
            inherit pkgs self;
          };
          vm = import ./nix/tests/vm.nix {
            inherit pkgs self;
          };
        }
        // upstreamShards
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
