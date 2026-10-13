{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane-maturin.url = "github:vlaci/crane-maturin";
    shell-hooks.url = "github:vlaci/nix-shell-hooks";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      crane-maturin,
      advisory-db,
      git-hooks,
      treefmt-nix,
      shell-hooks,
      rust-overlay,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
            rust-overlay.overlays.default
            shell-hooks.overlays.default
          ];
        }
      );

      rustToolchainFor = forAllSystems (
        system:
        nixpkgsFor.${system}.rust-bin.selectLatestNightlyWith (
          toolchain:
          toolchain.default.override {
            extensions = [
              "cargo"
              "clippy"
              "miri"
              "rust-src"
              "rustc"
              "rustfmt"
            ];
          }
        )
      );

      treefmtFor = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgsFor.${system} {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            ruff-format.enable = true;
            rustfmt = {
              enable = true;
              package = rustToolchainFor.${system};
              edition = "2021";
            };
            prettier = {
              enable = true;
              excludes = [
                "CHANGELOG.md"
                "docs/**"
                "flake.lock"
              ];
            };
          };
        }
      );

      pre-commit-check = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          rust = rustToolchainFor.${system};
        in
        git-hooks.lib.${system}.run {
          src = ./.;
          package = pkgs.prek;
          hooks = {
            check-added-large-files.enable = true;
            end-of-file-fixer = {
              enable = true;
              excludes = [ "CHANGELOG\\.md" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              excludes = [ ".*\\.md" ];
            };
            check-yaml.enable = true;
            check-toml.enable = true;
            check-github-workflows = {
              enable = true;
              name = "check-github-workflows";
              entry = "${pkgs.check-jsonschema}/bin/check-jsonschema --builtin-schema vendor.github-workflows";
              files = "^\\.github/workflows/.*\\.ya?ml$";
            };
            renovate-config-validator = {
              enable = true;
              name = "renovate-config-validator";
              entry = "${pkgs.renovate}/bin/renovate-config-validator --strict";
              files = "^renovate\\.json$";
            };
            treefmt = {
              enable = true;
              package = treefmtFor.${system}.config.build.wrapper;
            };
            statix.enable = true;
            deadnix.enable = true;
            pyupgrade = {
              enable = true;
              args = [ "--py311-plus" ];
            };
            ruff.enable = true;
            mypy = {
              enable = true;
              package = pkgs.python3.withPackages (ps: [
                ps.mypy
                ps.pytest
              ]);
            };
            cargo-check = {
              enable = true;
              package = rust;
              entry = ''${rust}/bin/cargo --config "build.rustc='${rust}/bin/rustc'" check'';
            };
            clippy = {
              enable = true;
              settings.denyWarnings = true;
              packageOverrides.cargo = rust;
              packageOverrides.clippy = rust;
            };
          };
        }
      );
    in
    {
      overlays.default =
        final: prev:
        let
          inherit (final) lib;
          cmLib = crane-maturin.mkLib crane final;

          cppFilter = path: _type: builtins.match ".*/hyperscan-sys/(wrapper.h|vectorscan).*$" path != null;
          pyFilter =
            path: _type:
            builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml|.*/README.md$|.*/LICENSE" path != null;
          sourceFilter = path: type: (cppFilter path type) || (cmLib.filterCargoSources path type);
          testFilter = p: _t: builtins.match ".*/(tests|tests/.*\.py|examples|examples/.*\.py)$" p != null;

        in
        {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: _python-prev: {
              pyperscan =
                let
                  # vendored = statically build the bundled vectorscan submodule; otherwise link nixpkgs vectorscan
                  drvFor =
                    vendored:
                    cmLib.buildMaturinPackage {
                      pname = "pyperscan" + lib.optionalString vendored "-vectorscan";
                      src = lib.cleanSourceWith {
                        src = cmLib.path ./.;
                        filter = p: t: (pyFilter p t) || (sourceFilter p t);
                      };
                      testSrc = lib.cleanSourceWith {
                        src = ./.;
                        filter = p: t: (sourceFilter p t) || (testFilter p t);
                      };
                      inherit advisory-db;
                      inherit (python-final) python;

                      nativeBuildInputs = [
                        final.rustPlatform.bindgenHook
                      ]
                      ++ lib.optionals vendored [
                        final.cmake
                        final.ragel
                        final.util-linux # `rev`, used by vectorscan's fat-runtime build_wrapper.sh
                      ];
                      # cmake is only used by the build script, not as a setup hook
                      dontUseCmakeConfigure = true;
                      buildInputs = if vendored then [ final.boost ] else [ final.vectorscan ];
                      maturinBuildFlags = lib.optionals vendored [
                        "-F"
                        "vectorscan"
                      ];

                      passthru = {
                        shared = drvFor false;
                        vectorscan = drvFor true;
                      };
                    };
                in
                drvFor false;
            })
          ];
        };
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          inherit (pkgs.python3Packages) pyperscan;
          pytestWith = python: python.pkgs.pyperscan.passthru.tests.pytest;
        in
        builtins.removeAttrs pyperscan.passthru.tests [
          "test"
          "test-coverage"
        ]
        // {
          pytest-py314t = pytestWith pkgs.python314FreeThreading;
          pytest-py315t = pytestWith pkgs.python315FreeThreading;
        }
      );

      packages = forAllSystems (
        system:
        let
          inherit (nixpkgsFor.${system}.python3Packages) pyperscan;
        in
        {
          inherit pyperscan;
          default = pyperscan;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            inherit (pre-commit-check.${system}) shellHook;
            buildInputs =
              with pkgs;
              [
                python314
                python314Packages.uvVenvShellHook
                python314Packages.maturinImportShellHook
                just
                maturin
                nodejs
                uv
                podman
                openssl
                boost
                cmake
                ragel
                rustPlatform.bindgenHook
                vectorscan
                rustToolchainFor.${system}
              ]
              ++ pre-commit-check.${system}.enabledPackages
              ++ lib.optionals stdenv.hostPlatform.isLinux [ python314Packages.autoPatchelfVenvShellHook ];
            dontAddPythonPath = true;
            uvExtraArgs = [
              "--group"
              "docs"
              "--group"
              "test"
            ];
            libraries = with pkgs; [
              stdenv.cc.cc.lib
              file
            ];
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          inherit (pre-commit-check.${system}.config) package configFile;
        in
        pkgs.runCommand "pre-commit-run"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta.mainProgram = "pre-commit-run";
          }
          ''
            clang=${pkgs.clang}/nix-support
            makeWrapper ${pkgs.lib.getExe package} $out/bin/pre-commit-run \
              --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  rustToolchainFor.${system}
                  pkgs.stdenv.cc
                  pkgs.python3
                ]
              } \
              --set LIBCLANG_PATH ${pkgs.lib.getLib pkgs.libclang}/lib \
              --set BINDGEN_EXTRA_CLANG_ARGS "$(< $clang/cc-cflags) $(< $clang/libc-cflags) -isystem ${pkgs.lib.getDev pkgs.vectorscan}/include" \
              --add-flags "run --all-files --config ${configFile}"
          ''
      );
    };
}
