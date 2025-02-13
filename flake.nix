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
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      crane-maturin,
      rust-overlay,
      advisory-db,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
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
          ];
        }
      );
    in
    {
      overlays.default =
        final: prev:
        let
          stdenv =
            if prev.stdenv.isDarwin then
              final.overrideLibcxx final.darwin.apple_sdk_11_0.llvmPackages_14.stdenv
            else
              prev.stdenv;
        in
        {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              pyperscan = final.callPackage (
                {
                  lib,
                  system,
                  rustPlatform,
                  boost,
                  hyperscan,
                  vectorscan,
                  vendorHyperscan ? false,
                  vendorVectorscan ? false,
                }:

                assert vendorHyperscan -> !vendorVectorscan;
                assert vendorVectorscan -> !vendorHyperscan;

                let
                  inherit (lib) optional optionalString;
                  vendor = vendorHyperscan || vendorVectorscan;
                  cmLib = crane-maturin.mkLib crane final;

                  cppFilter =
                    path: _type: builtins.match ".*/hyperscan-sys/(wrapper.h|hyperscan|vectorscan).*$" path != null;

                  pyFilter =
                    path: _type:
                    builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml|.*/README.md$|.*/LICENSE" path != null;
                  testFilter = p: t: builtins.match ".*/(tests|tests/.*\.py|examples|examples/.*\.py)$" p != null;
                  sourceFilter = path: type: (cppFilter path type) || (cmLib.filterCargoSources path type);
                  drv = cmLib.buildMaturinPackage {
                    pname =
                      "pyperscan"
                      + optionalString vendorHyperscan "-hyperscan"
                      + optionalString vendorVectorscan "-vectorscan";
                    src = lib.cleanSourceWith {
                      src = cmLib.path ./.;
                      filter = p: t: (pyFilter p t) || (sourceFilter p t);
                    };
                    testSrc = lib.cleanSourceWith {
                      src = ./.;
                      filter = p: t: (sourceFilter p t) || (testFilter p t);
                    };
                    inherit advisory-db;

                    nativeBuildInputs = with rustPlatform; [
                      bindgenHook
                    ];
                    buildInputs =
                      optional vendor boost
                      ++ optional (system == "x86_64-linux") hyperscan
                      ++ optional (system != "x86_64-linux") vectorscan;

                    passthru = {
                      shared = drv;
                      hyperscan = drv.override { vendorHyperscan = true; };
                      vectorscan = drv.override { vendorVectorscan = true; };
                    };
                  };
                in
                drv
              ) { };
            })
          ];
          vectorscan = prev.vectorscan.override { inherit stdenv; };
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

      formatter = forAllSystems (system: nixpkgsFor.${system}.nixpkgs-fmt);

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
                just
                maturin
                pdm
                podman
                pre-commit
                openssl
                boost
                cmake
                ragel
                rustPlatform.bindgenHook
                hyperscan
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
              ];
            };
        }
      );
    };
}
