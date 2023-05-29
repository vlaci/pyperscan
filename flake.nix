{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-analyzer-src.follows = "";
    };

    flake-utils.url = "github:numtide/flake-utils";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, crane, fenix, flake-utils, advisory-db, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib makeRustPlatform python3Packages;

        craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;
        cppFilter = path: _type: builtins.match ".*/hyperscan-sys/(wrapper.h|hyperscan|vectorscan).*$" path != null;

        sourceFilter = path: type:
          (cppFilter path type) || (craneLib.filterCargoSources path type);

        src = lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = sourceFilter;
        };

        buildInputs = with pkgs; [
          python3
        ] ++ lib.optional stdenv.isDarwin libiconv
        ++ lib.optional (system == "x86_64-linux") hyperscan
        ++ lib.optional (system != "x86_64-linux") vectorscan;

        rust-toolchain = fenix.packages.${system}.complete.toolchain;
        rust-toolchain-llvm-tools = fenix.packages.${system}.complete.withComponents [
          "llvm-tools"
          "cargo"
          "rustc"
        ];
        craneLibLLvmTools = craneLib.overrideToolchain rust-toolchain-llvm-tools;

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly { inherit src buildInputs; };

        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        libpyperscan = craneLib.buildPackage {
          inherit src buildInputs cargoArtifacts;
          nativeBuildInputs = with rustPlatform; [
            bindgenHook
          ];
        };

        rustPlatform = makeRustPlatform {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
        };

        rustPlatform-cov = makeRustPlatform {
          cargo = rust-toolchain-llvm-tools;
          rustc = rust-toolchain-llvm-tools;
        };

        pyFilter = path: _type: builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml|.*/README.md$|.*/LICENSE" path != null;
        testFilter = p: t: builtins.match ".*/(tests|tests/.*\.py)$" p != null;

        mkNativeBuildInputs = { rustPlatform, extra ? [ ] }: with rustPlatform; [
          bindgenHook
          cargoSetupHook
          maturinBuildHook
        ] ++ extra;

        pyperscan =
          let
            drv = pkgs.callPackage
              ({ lib
               , python3Packages
               , rustPlatform
               , hyperscan
               , vectorscan
               , boost
               , cmake
               , pkg-config
               , ragel
               , util-linux
               , vendorHyperscan ? false
               , vendorVectorscan ? false
               }:

                assert vendorHyperscan -> !vendorVectorscan;
                assert vendorVectorscan -> !vendorHyperscan;

                let
                  inherit (lib) optionals;
                  vendor = vendorHyperscan || vendorVectorscan;
                  cargo_toml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
                in
                python3Packages.buildPythonPackage
                  {
                    inherit (cargo_toml.workspace.package) version;

                    pname = "pyperscan";
                    format = "pyproject";

                    src = lib.cleanSourceWith {
                      src = craneLib.path ./.;
                      filter = p: t: (pyFilter p t) || (sourceFilter p t);
                    };

                    strictDeps = true;
                    doCheck = false;

                    cargoDeps = rustPlatform.importCargoLock {
                      lockFile = ./Cargo.lock;
                    };

                    maturinBuildFlags = (optionals vendorHyperscan [ "-F hyperscan" ]) ++ (optionals (vendorVectorscan) [ "-F vectorscan" ]);

                    buildInputs = with pkgs; [
                      python3
                    ] ++ lib.optional stdenv.isDarwin libiconv
                    ++ lib.optional vendor boost
                    ++ lib.optional (!vendor && system == "x86_64-linux") hyperscan
                    ++ lib.optional (!vendor && system != "x86_64-linux") vectorscan;

                    nativeBuildInputs = mkNativeBuildInputs {
                      inherit rustPlatform;
                      extra = optionals vendor [ cmake ragel util-linux ];
                    };

                    dontUseCmakeConfigure = true;

                    passthru = {
                      shared = drv;
                      hyperscan = drv.override { vendorHyperscan = true; };
                      vectorscan = drv.override { vendorVectorscan = true; };
                      tests.checks = with python3Packages; buildPythonPackage
                        {
                          inherit (pyperscan) version;
                          pname = "${pyperscan.pname}-tests-checks";
                          format = "other";

                          src = lib.cleanSourceWith {
                            src = ./.;
                            filter = p: t: (pyFilter p t) || (testFilter p t);
                          };

                          dontBuild = true;
                          dontInstall = true;

                          nativeCheckInputs = [
                            black
                            mypy
                            pkgs.ruff
                            pytest
                            pyperscan
                          ];

                          checkPhase = ''
                            black .
                            mypy .
                            ruff .
                          '';
                        };
                      tests.coverage =
                        let
                          pyperscan-cov = pyperscan.overridePythonAttrs (with pkgs; super: {
                            pname = "${super.pname}-coverage";
                            nativeBuildInputs = mkNativeBuildInputs {
                              rustPlatform = rustPlatform-cov;
                              extra = [
                                cargo-llvm-cov
                              ];
                            };
                            preConfigure = (super.preConfigure or "") + ''
                              source <(cargo llvm-cov show-env --export-prefix)
                            '';
                          });
                        in
                        with python3Packages; buildPythonPackage
                          {
                            inherit (pyperscan) version cargoDeps;
                            pname = "${pyperscan.pname}-tests-coverage";
                            format = "other";

                            src = lib.cleanSourceWith {
                              src = ./.;
                              filter = p: t: (sourceFilter p t) || (testFilter p t);
                            };

                            dontBuild = true;
                            dontInstall = true;

                            preCheck = ''
                              source <(cargo llvm-cov show-env --export-prefix)
                              LLVM_COV_FLAGS=$(echo -n $(find ${pyperscan-cov} -name "*.so"))
                              export LLVM_COV_FLAGS
                            '';
                            postCheck = ''
                              rm -r $out
                              cargo llvm-cov report -vv --ignore-filename-regex cargo-vendor-dir --codecov --output-path $out
                            '';

                            nativeBuildInputs =
                              (with rustPlatform-cov; [
                                cargoSetupHook
                              ]);

                            nativeCheckInputs = with pkgs; [
                              rust-toolchain-llvm-tools
                              cargo-llvm-cov
                              pyperscan-cov
                              pytestCheckHook
                            ];
                          };
                      tests.pytest = with python3Packages; buildPythonPackage
                        {
                          inherit (pyperscan) version;
                          pname = "${pyperscan.pname}-tests-pytest";
                          format = "other";

                          src = lib.cleanSourceWith {
                            src = ./.;
                            filter = p: t: (testFilter p t);
                          };

                          dontBuild = true;
                          dontInstall = true;

                          nativeCheckInputs = [
                            pyperscan
                            pytestCheckHook
                          ];
                        };
                    };

                  })
              {
                inherit rustPlatform;
              };
          in
          drv;
      in
      {
        checks =
          let
            nativeBuildInputs = with rustPlatform; [
              bindgenHook
            ];
          in
          pyperscan.passthru.tests // {
            # Build the crate as part of `nix flake check` for convenience
            inherit libpyperscan;

            # Run clippy (and deny all warnings) on the crate source,
            # again, resuing the dependency artifacts from above.
            #
            # Note that this is done as a separate derivation so that
            # we can block the CI if there are issues here, but not
            # prevent downstream consumers from building our crate by itself.
            libpyperscan-clippy = craneLib.cargoClippy {
              inherit src buildInputs nativeBuildInputs cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            };

            libpyperscan-doc = craneLib.cargoDoc {
              inherit src buildInputs nativeBuildInputs cargoArtifacts;
            };

            # Check formatting
            libpyperscan-fmt = craneLib.cargoFmt {
              inherit src;
            };

            # Audit dependencies
            libpyperscan-audit = craneLib.cargoAudit {
              inherit src advisory-db;
            };
          } // lib.optionalAttrs
            (system == "x86_64-linux")
            {
              # Check code coverage (note: this will not upload coverage anywhere)
              libpyperscan-coverage = craneLibLLvmTools.cargoLlvmCov {
                inherit src buildInputs nativeBuildInputs cargoArtifacts;
                cargoLlvmCovExtraArgs = "--ignore-filename-regex /nix/store --codecov --output-path $out";
              };
            };

        formatter = pkgs.nixpkgs-fmt;

        packages = with pkgs;
          {
            default = pyperscan;
          };

        devShells =
          let
            inherit (pkgs.lib) filter hasSuffix;
            noHooks = filter (drv: !(hasSuffix "hook.sh" drv.name));
          in
          rec {
            default = with pkgs; mkShell {
              inputsFrom = builtins.attrValues self.checks.${system};
              buildInputs = [
                just
                maturin
                pdm
                podman
                pre-commit
              ];
            };
          };
      });
}
