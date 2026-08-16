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
      executionProfiles = import ./nix/tests/execution-profiles.nix;
      ciExecutionProfiles = {
        x86_64-linux = executionProfiles.accelerated;
        aarch64-linux = executionProfiles.emulated;
      };
      upstreamCoverages = [
        "core"
        "long"
        "stress"
      ];
      mkCiTestMatrix = system: {
        include = nixpkgs.lib.concatMap (
          coverage:
          let
            shardCount = ciExecutionProfiles.${system}.shardCounts.${coverage};
          in
          map (shardIndex: {
            inherit coverage;
            shard = shardIndex + 1;
            shards = shardCount;
          }) (nixpkgs.lib.range 0 (shardCount - 1))
        ) upstreamCoverages;
      };
      mkLimaConfiguration =
        {
          system,
          upstreamTesting ? false,
          persistent ? true,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self; };
          modules = [
            nixos-lima.nixosModules.lima
            self.nixosModules.default
            (import ./nix/hosts/lima.nix { inherit persistent; })
          ]
          ++ nixpkgs.lib.optional upstreamTesting (
            import ./nix/tests/upstream-host.nix {
              upstreamTest = self.packages.${system}.upstream-test;
            }
          );
        };
    in
    {
      overlays.default = final: _prev: {
        dtrace-bpf-binutils = final.callPackage ./nix/bpf-binutils.nix { };
        dtrace-bpf-gcc = final.callPackage ./nix/bpf-gcc.nix {
          bpf-binutils = final.dtrace-bpf-binutils;
        };
        oracle-dtrace =
          let
            package =
              (final.callPackage ./nix/package.nix {
                src = dtrace-src;
                bpf-binutils = final.dtrace-bpf-binutils;
                bpf-gcc = final.dtrace-bpf-gcc;
              }).overrideAttrs
                (oldAttrs: {
                  passthru = (oldAttrs.passthru or { }) // {
                    tests = (oldAttrs.passthru.tests or { }) // {
                      usdt-fixture = final.callPackage ./nix/tests/usdt-fixture.nix {
                        dtracePackage = package;
                      };
                    };
                  };
                });
          in
          package;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          dtracePackage = pkgs.oracle-dtrace;
          testsuite = import ./nix/tests/testsuite.nix {
            inherit pkgs dtracePackage;
          };
          upstreamTest = import ./nix/tests/direct.nix {
            inherit pkgs dtracePackage testsuite;
          };
          limaTestConfiguration = mkLimaConfiguration {
            inherit system;
            upstreamTesting = true;
            persistent = false;
          };
        in
        {
          default = dtracePackage;
          inherit (pkgs) oracle-dtrace dtrace-bpf-binutils dtrace-bpf-gcc;
          lima-test-iso = limaTestConfiguration.config.system.build.images.iso;
          upstream-test = upstreamTest;
          upstream-testsuite = testsuite;
          upstream-test-closure = pkgs.linkFarm "oracle-dtrace-upstream-test-closure" [
            {
              name = "dtrace";
              path = dtracePackage;
            }
            {
              name = "runner";
              path = upstreamTest;
            }
            {
              name = "testsuite";
              path = testsuite;
            }
            {
              name = "usdt-fixture";
              path = dtracePackage.tests.usdt-fixture;
            }
          ];
        }
      );

      apps = forAllSystems (system: {
        upstream-test = {
          type = "app";
          program = "${self.packages.${system}.upstream-test}/bin/dtrace-upstream-test";
          meta.description = "Run an explicitly selected Oracle DTrace upstream coverage class";
        };
      });

      lib.ciTestMatrix = forAllSystems mkCiTestMatrix;

      nixosModules.default = import ./nix/module.nix { inherit self; };
      nixosModules.dtrace = self.nixosModules.default;

      nixosConfigurations = {
        dtrace-lima-arm = mkLimaConfiguration { system = "aarch64-linux"; };
        dtrace-lima-x86 = mkLimaConfiguration { system = "x86_64-linux"; };
      };

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          executionProfile = ciExecutionProfiles.${system};
          mkCoverageShards =
            coverage:
            let
              shardCount = executionProfile.shardCounts.${coverage};
            in
            builtins.listToAttrs (
              map (shardIndex: {
                name = "upstream-${coverage}-${toString (shardIndex + 1)}";
                value = import ./nix/tests/upstream.nix {
                  inherit
                    pkgs
                    self
                    executionProfile
                    coverage
                    shardIndex
                    shardCount
                    ;
                };
              }) (nixpkgs.lib.range 0 (shardCount - 1))
            );
          upstreamShards = nixpkgs.lib.foldl' (
            acc: coverage: acc // mkCoverageShards coverage
          ) { } upstreamCoverages;
        in
        {
          package = pkgs.oracle-dtrace;
          package-usdt-fixture = pkgs.oracle-dtrace.tests.usdt-fixture;
          vm = import ./nix/tests/vm.nix {
            inherit pkgs self;
          };
        }
        // upstreamShards
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
