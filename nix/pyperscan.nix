{ lib
, nix-filter
, python3Packages
, rustPlatform
, hyperscan
, boost
, cmake
, pkg-config
, ragel
, util-linux
, vendorHyperscan ? false
, vendorVectorscan ? false
}:

assert vendorHyperscan -> !vendorVectorscan;
assert vendorVectorscan -> !vendorHyperscan;

let
  inherit (lib) optionals;
  vendor = vendorHyperscan || vendorVectorscan;
  cargo_toml = builtins.fromTOML (builtins.readFile ../Cargo.toml);
in
python3Packages.buildPythonPackage {
  inherit (cargo_toml.workspace.package) version;

  pname = "pyperscan";
  format = "pyproject";

  src = nix-filter {
    root = ../.;
    include = [
      "Cargo.toml"
      "Cargo.lock"
      "LICENSE-APACHE"
      "LICENSE-MIT"
      "README.md"
      "pyperscan.pyi"
      "pyproject.toml"
      "rust-toolchain.toml"
      "hyperscan-sys"
      "src"
      "tests"
    ];
  };

  strictDeps = true;

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../Cargo.lock;
  };

  maturinBuildFlags = (optionals vendorHyperscan [ "-F hyperscan" ]) ++ (optionals (!vendorVectorscan) [ "--no-default-features" ]);

  buildInputs = if vendor then [ boost util-linux ] else [ hyperscan ];

  nativeBuildInputs =
    (with rustPlatform; [
      bindgenHook
      cargoSetupHook
      maturinBuildHook
      pkg-config
    ] ++ (optionals vendor [ cmake ragel util-linux ]));
  dontUseCmakeConfigure = true;

  nativeCheckInputs = [ python3Packages.pytest ];
  checkPhase = ''
    pytest
  '';
}
