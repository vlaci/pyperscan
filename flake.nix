{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane-maturin = {
      url = "sourcehut:~vlaci/crane-maturin";
      inputs.crane.follows = "crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-analyzer-src.follows = "";
    };

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, crane-maturin, fenix, advisory-db, ... }@inputs:
    let
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlays.default ]; });

    in
    {
      overlays.default = final: prev:
        let
          stdenv = if prev.stdenv.isDarwin then final.overrideLibcxx final.darwin.apple_sdk_11_0.llvmPackages_14.stdenv else prev.stdenv;
          rustPlatform = final.makeRustPlatform { inherit stdenv; inherit (final) rustc cargo; };
        in
        {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              pyperscan = final.callPackage (import ./pyperscan.nix inputs) { inherit stdenv rustPlatform; python3 = python-final.python; };
            })
          ];
          vectorscan = prev.vectorscan.override { inherit stdenv; };
        };
      checks = forAllSystems (system:
        let
          inherit (nixpkgsFor.${system}.python3Packages) pyperscan;
        in
        pyperscan.passthru.tests);

      formatter = forAllSystems (system: nixpkgsFor.${system}.nixpkgs-fmt);

      packages = forAllSystems (system:
        let
          inherit (nixpkgsFor.${system}.python3Packages) pyperscan;
        in
        {
          inherit pyperscan;
          default = pyperscan;
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = with pkgs; mkShell {
            inputsFrom = [ python3Packages.pyperscan.crate ];
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
              (fenix.packages.${system}.complete.withComponents [
                "cargo"
                "clippy"
                "rust-src"
                "rustc"
                "rustfmt"
              ])
              fenix.packages.${system}.complete.rust-analyzer
            ];
          };
        });
    };
}
