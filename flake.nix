{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    maturin.url = "github:PyO3/maturin/v0.14.5";
    maturin.flake = false;
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, utils, maturin, rust-overlay }:
    utils.lib.eachDefaultSystem
      (system:
        let
          overlays = [
            rust-overlay.overlays.default
            (final: prev: {
              maturin = prev.maturin.overrideAttrs (super: {
                version = maturin.shortRev;
                src = maturin;
                cargoDeps = final.rustPlatform.importCargoLock {
                  lockFile = "${maturin}/Cargo.lock";
                };
              });
            })
          ];
          pkgs = import nixpkgs { inherit overlays system; };
          inherit (pkgs.lib) optionals;

          rust-toolchain_toml = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain;
          rustToolchain = pkgs.rust-bin.fromRustupToolchain rust-toolchain_toml;
          rustToolchainDev = rustToolchain.override {
            extensions = (rust-toolchain_toml.components or [ ]) ++ [ "rust-src" ];
          };
          pyperscan =
            let
              drv = pkgs.callPackage ./nix/pyperscan.nix {
                rustPlatform = pkgs.makeRustPlatform { cargo = rustToolchain; rustc = rustToolchain; };
              };
            in
            drv.overrideAttrs (_: {
              passthru = {
                shared = drv;
                hyperscan = drv.override { vendorHyperscan = true; };
                vectorscan = drv.override { vendorVectorscan = true; };
              };
            });
        in
        {
          packages = pkgs;
          defaultPackage = pyperscan;
          devShell =
            let
              inherit (pkgs.lib) filter hasSuffix;
              noHooks = filter (drv: !(hasSuffix "hook.sh" drv.name));
              pyperscan' = pyperscan.override { python3Packages = pkgs.python38Packages; };

            in
            with pkgs; mkShell {
              nativeBuildInputs = noHooks pyperscan'.hyperscan.nativeBuildInputs;
              buildInputs = [
                just
                pre-commit
                rustToolchainDev
                pkgs.maturin
                pkgs.rust-bin.nightly.latest.rust-analyzer
              ]
              ++ pyperscan'.hyperscan.buildInputs
              ++ (optionals (system == "x86_64-linux")
                pyperscan'.buildInputs);
            };
        });
}
