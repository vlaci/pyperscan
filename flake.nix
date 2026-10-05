{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";
    crane-maturin.url = "github:vlaci/crane-maturin";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    shell-hooks.url = "github:vlaci/nix-shell-hooks";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      crane-maturin,
      rust-overlay,
      advisory-db,
      shell-hooks,
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
    in
    {
      overlays.default = final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (python-final: python-prev: {
            pyperscan = final.callPackage (
              {
                lib,
                rustPlatform,
                boost,
                cmake,
                ragel,
                util-linux,
                vectorscan,
              }:

              let
                inherit (lib) optionalString;
                cmLib = crane-maturin.mkLib crane final;

                cppFilter = path: _type: builtins.match ".*/hyperscan-sys/(wrapper.h|vectorscan).*$" path != null;

                pyFilter =
                  path: _type:
                  builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml|.*/README.md$|.*/LICENSE" path != null;
                testFilter = p: t: builtins.match ".*/(tests|tests/.*\.py|examples|examples/.*\.py)$" p != null;
                sourceFilter = path: type: (cppFilter path type) || (cmLib.filterCargoSources path type);
                # vendored = statically build the bundled vectorscan submodule; otherwise link nixpkgs vectorscan
                drvFor =
                  vendored:
                  cmLib.buildMaturinPackage {
                    pname = "pyperscan" + optionalString vendored "-vectorscan";
                    src = lib.cleanSourceWith {
                      src = cmLib.path ./.;
                      filter = p: t: (pyFilter p t) || (sourceFilter p t);
                    };
                    testSrc = lib.cleanSourceWith {
                      src = ./.;
                      filter = p: t: (sourceFilter p t) || (testFilter p t);
                    };
                    inherit advisory-db;

                    nativeBuildInputs = [
                      rustPlatform.bindgenHook
                    ]
                    ++ lib.optionals vendored [
                      cmake
                      ragel
                      util-linux # `rev`, used by vectorscan's fat-runtime build_wrapper.sh
                    ];
                    # cmake is only used by the build script, not as a setup hook
                    dontUseCmakeConfigure = true;
                    buildInputs = if vendored then [ boost ] else [ vectorscan ];
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
              drvFor false
            ) { };
          })
        ];
      };
      checks = forAllSystems (
        system:
        let
          inherit (nixpkgsFor.${system}.python3Packages) pyperscan;
        in
        builtins.removeAttrs pyperscan.passthru.tests [
          "test"
          "test-coverage"
        ]
      );

      formatter = forAllSystems (system: nixpkgsFor.${system}.nixfmt);

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
          default =
            with pkgs;
            mkShell {
              buildInputs = [
                python314
                python314Packages.uvVenvShellHook
                python314Packages.maturinImportShellHook
                just
                maturin
                nodejs
                uv
                podman
                pre-commit
                openssl
                boost
                cmake
                ragel
                rustPlatform.bindgenHook
                vectorscan
                (rust-bin.selectLatestNightlyWith (
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
                ))
              ]
              ++ lib.optionals stdenv.hostPlatform.isLinux [ python314Packages.autoPatchelfVenvShellHook ];
              # nix python deps leak onto PYTHONPATH and shadow the uv-managed venv
              shellHook = "unset PYTHONPATH";
              uvExtraArgs = [
                "--group"
                "docs"
                "--group"
                "test"
              ];
              libraries = [
                stdenv.cc.cc.lib
                file
              ];
            };
        }
      );
    };
}
