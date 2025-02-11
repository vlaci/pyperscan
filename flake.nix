{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

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
      rust-overlay,
      advisory-db,
      ...
    }@inputs:
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
          rustPlatform = final.makeRustPlatform {
            inherit stdenv;
            inherit (final) rustc cargo;
          };
        in
        {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              pyperscan = final.callPackage (import ./pyperscan.nix inputs) {
                inherit stdenv rustPlatform;
                python3 = python-final.python;
              };
            })
          ];
          vectorscan = prev.vectorscan.override { inherit stdenv; };
        };
      checks = forAllSystems (
        system:
        let
          inherit (nixpkgsFor.${system}) rustPlatform;
          inherit (nixpkgsFor.${system}.python3Packages) pyperscan;
          nativeBuildInputs = with rustPlatform; [
            bindgenHook
          ];
          inherit (pyperscan)
            cargoArtifacts
            craneLib
            commonArgs
            libpyperscan
            src
            ;
        in
        pyperscan.passthru.tests
        // {
          # Build the crate as part of `nix flake check` for convenience
          inherit libpyperscan;

          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          libpyperscan-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit nativeBuildInputs cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          libpyperscan-doc = craneLib.cargoDoc (
            commonArgs
            // {
              inherit nativeBuildInputs cargoArtifacts;
            }
          );

          # Check formatting
          libpyperscan-fmt = craneLib.cargoFmt {
            inherit src;
          };

          # Audit dependencies
          libpyperscan-audit = craneLib.cargoAudit {
            inherit src advisory-db;
          };
        }
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
