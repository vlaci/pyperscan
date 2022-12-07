{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    maturin.url = "github:PyO3/maturin";
    maturin.flake = false;
    rust-overlay.url = "github:oxalica/rust-overlay";
    nix-old-libc.url = "git+ssh://git@git.sr.ht/~vlaci/nix-old-libc";
    nix-old-libc.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, utils, maturin, rust-overlay, nix-old-libc }:
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

          stdenv = nix-old-libc.packages.${system}.stdenv-glibc217;
          hyperscan = pkgs.hyperscan.override { inherit stdenv; };
          python3Packages = (pkgs.python38.override { inherit stdenv; }).pkgs;
        in
        {
          packages = pkgs;
          defaultPackage = pyperscan;
          devShell =
            let
              inherit (pkgs.lib) filter hasSuffix;
              noHooks = filter (drv: !(hasSuffix "hook.sh" drv.name));
              pyperscan' = pyperscan.override { inherit python3Packages hyperscan; };

            in
            with pkgs; (mkShell.override { inherit stdenv; }) {
              nativeBuildInputs = noHooks pyperscan'.hyperscan.nativeBuildInputs;
              buildInputs = [
                glibc_multi
                just
                pre-commit
                rustToolchainDev
                pkgs.maturin
                pkgs.zig
                pkgs.rust-bin.nightly.latest.rust-analyzer
              ]
              ++ pyperscan'.hyperscan.buildInputs
              ++ (optionals (system == "x86_64-linux")
                pyperscan'.buildInputs);
              LOCALE_ARCHIVE = "${stdenv.cc.libc}/lib/locale/locale-archive";

            };
        });
}
