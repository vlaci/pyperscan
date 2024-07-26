inputs:

{ lib
, callPackage
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
, util-linux
, ruff
, vendorHyperscan ? false
, vendorVectorscan ? false
, coverage ? false
}:

assert vendorHyperscan -> !vendorVectorscan;
assert vendorVectorscan -> !vendorHyperscan;

let
  inherit (lib) optional optionals optionalString;
  cppFilter = path: builtins.match ".*/hyperscan-sys/(wrapper.h|hyperscan|vectorscan).*$" path != null;
  pyFilter = path: builtins.match ".*pyi?$|.*/py.typed$|.*/pyproject.toml$|.*/README.md$|.*/LICENSE$" path != null;
  rsFilter = path: builtins.match ".*rs$|.*/Cargo.toml$|.*/Cargo.lock$" path != null;
  dirFilter = type: type == "directory";
  sourceFilter = path: type:
    (dirFilter type) || (cppFilter path) || (pyFilter path) || (rsFilter path);

  vendor = vendorHyperscan || vendorVectorscan;
  buildInputs =
    optional stdenv.isDarwin libiconv
    ++ optional vendor boost
    ++ optional (system == "x86_64-linux") hyperscan
    ++ optional (system != "x86_64-linux") vectorscan;

  src = lib.cleanSourceWith {
    src = ./.;
    filter = sourceFilter;
  };

  drv = inputs.crane-maturin.lib.${system}.buildMaturinPythonPackage {
    pname = "pyperscan"
      + optionalString vendorHyperscan "-hyperscan"
      + optionalString vendorVectorscan "-vectorscan"
      + optionalString coverage "-coverage";
    format = "pyproject";

    inherit src buildInputs;

    maturinBuildFlags =
      (optionals vendorHyperscan [ "-F hyperscan" ])
      ++ (optionals (vendorVectorscan) [ "-F vectorscan" ]);
    nativeBuildInputs = [
      rustPlatform.bindgenHook
    ];

    passthru = {
      shared = drv;
      hyperscan = drv.override { vendorHyperscan = true; };
      vectorscan = drv.override { vendorVectorscan = true; };
    };
  };
in
drv
