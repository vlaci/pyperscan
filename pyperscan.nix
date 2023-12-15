inputs:

{ lib
, stdenv
, makeRustPlatform
, rustPlatform
, cargo
, rustc
, maturin
, cargo-llvm-cov
, system
, libiconv
, boost
, hyperscan
, vectorscan
, python3
, ruff
, vendorHyperscan ? false
, vendorVectorscan ? false
, coverage ? false
, pyperscan
}:

assert vendorHyperscan -> !vendorVectorscan;
assert vendorVectorscan -> !vendorHyperscan;

let
  inherit (lib) optional optionals optionalString;
  craneLib = inputs.crane.lib.${system};

  cppFilter = path: _type: builtins.match ".*/hyperscan-sys/(wrapper.h|hyperscan|vectorscan).*$" path != null;

  pyFilter = path: _type: builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml|.*/README.md$|.*/LICENSE" path != null;
  testFilter = p: t: builtins.match ".*/(tests|tests/.*\.py|examples|examples/.*\.py)$" p != null;
  sourceFilter = path: type:
    (cppFilter path type) || (craneLib.filterCargoSources path type);

  vendor = vendorHyperscan || vendorVectorscan;
  buildInputs = [
    python3
  ] ++ optional stdenv.isDarwin libiconv
  ++ optional vendor boost
  ++ optional (system == "x86_64-linux") hyperscan
  ++ optional (system != "x86_64-linux") vectorscan;

  src = lib.cleanSourceWith {
    src = craneLib.path ./.;
    filter = p: t: (pyFilter p t) || (sourceFilter p t);
  };
  commonArgs = {
    inherit src buildInputs;

    # python package  build will recompile PyO3 when built with maturin
    # as there are different build features are used for the extension module
    # and the standalone dylib which is used for tests and benchmarks
    doNotLinkInheritedArtifacts = true;
  };

  # Build *just* the cargo dependencies, so we can reuse
  # all of that work (e.g. via cachix) when running in CI
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  # Build the actual crate itself, reusing the dependency
  # artifacts from above.
  libpyperscan = craneLib.buildPackage (commonArgs // {
    inherit cargoArtifacts;
    nativeBuildInputs = with rustPlatform; [
      bindgenHook
    ];
  });

  cargo_toml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

  drv = python3.pkgs.buildPythonPackage {
    pname = "pyperscan"
      + optionalString vendorHyperscan "-hyperscan"
      + optionalString vendorVectorscan "-vectorscan"
      + optionalString coverage "-coverage";
    format = "pyproject";


    inherit src buildInputs;
    inherit (cargo_toml.workspace.package) version;

    # python package  build will recompile PyO3 when built with maturin
    # as there are different build features are used for the extension module
    # and the standalone dylib which is used for tests and benchmarks
    doNotLinkInheritedArtifacts = true;
    dontUseCmakeConfigure = true;

    strictDeps = true;
    doCheck = false;

    cargoDeps = rustPlatform.importCargoLock {
      lockFile = ./Cargo.lock;
    };

    maturinBuildFlags =
      (optionals vendorHyperscan [ "-F hyperscan" ])
      ++ (optionals (vendorVectorscan) [ "-F vectorscan" ]);

    nativeBuildInputs = with rustPlatform; [
      cargoSetupHook
      (maturinBuildHook.override { pkgsHostTarget = { inherit maturin cargo rustc; }; })
    ] ++ optional (vendor && stdenv.isLinux) util-linux
    ++ optional (!stdenv.isDarwin) bindgenHook # HACK: bindgen segfaults on Darwin with LLVM from nixpkgs
    ++ optional coverage cargo-llvm-cov;

    preConfigure = optionalString coverage ''
      source <(cargo llvm-cov show-env --export-prefix)
    '';

    passthru = {
      inherit cargoArtifacts craneLib commonArgs libpyperscan;
      shared = drv;
      hyperscan = drv.override { vendorHyperscan = true; };
      vectorscan = drv.override { vendorVectorscan = true; };

      tests = import ./tests.nix {
        inherit lib stdenv system makeRustPlatform rustPlatform pyFilter testFilter cargo-llvm-cov python3 ruff pyperscan;
        inherit (inputs) fenix;
      };
    };
  };
in
drv
