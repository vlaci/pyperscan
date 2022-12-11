{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    filter.url = "github:numtide/nix-filter";
    maturin.url = "github:PyO3/maturin/v0.14.5";
    maturin.flake = false;
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, utils, filter, maturin, rust-overlay }:
    let
      rust-toolchain_toml = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain;

      overlays = [
        rust-overlay.overlays.default
        filter.overlays.default
        (final: prev: {
          maturin = prev.maturin.overrideAttrs (super: {
            version = maturin.shortRev;
            src = maturin;
            cargoDeps = final.rustPlatform.importCargoLock {
              lockFile = "${maturin}/Cargo.lock";
            };
          });

          rustToolchain = final.rust-bin.fromRustupToolchain rust-toolchain_toml;
          rustToolchainDev = final.rustToolchain.override {
            extensions = (rust-toolchain_toml.components or [ ]) ++ [ "rust-src" ];
          };

          pyperscan =
            let
              drv = final.callPackage ./nix/pyperscan.nix {
                rustPlatform = final.makeRustPlatform { cargo = final.rustToolchain; rustc = final.rustToolchain; };
              };
            in
            drv.overrideAttrs (_: {
              passthru = {
                shared = drv;
                hyperscan = drv.override { vendorHyperscan = true; };
                vectorscan = drv.override { vendorVectorscan = true; };
              };
            });
        })
      ];
    in
    utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit overlays system; };
        in
        {
          packages = with pkgs; {
            default = pyperscan;
          };

          devShells =
            let
              inherit (pkgs.lib) filter hasSuffix;
              noHooks = filter (drv: !(hasSuffix "hook.sh" drv.name));
              pyperscan' = pkgs.pyperscan.override { python3Packages = pkgs.python38Packages; };
            in
            rec {
              default =
                with pkgs; mkShell {
                  nativeBuildInputs = noHooks pyperscan'.hyperscan.nativeBuildInputs;
                  buildInputs = [
                    just
                    maturin
                    pre-commit
                    rust-bin.nightly.latest.rust-analyzer
                    rustToolchainDev
                  ]
                  ++ pyperscan'.hyperscan.buildInputs
                  ++ (pkgs.lib.optionals (system == "x86_64-linux")
                    pyperscan'.buildInputs);
                };
            };

        });
}
