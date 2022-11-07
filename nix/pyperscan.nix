{ lib
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

  src = builtins.path { name = "pyperscan-source"; path = ../.; filter = p: t: !(t == "directory" && baseNameOf p == "target"); };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../Cargo.lock;
  };

  maturinBuildFlags = (optionals vendorHyperscan [ "-F hyperscan" ]) ++ (optionals vendorVectorscan [ "-F vectorscan" ]);

  buildInputs = if vendor then [ boost util-linux ] else [ hyperscan ];

  nativeBuildInputs =
    (with rustPlatform; [
      bindgenHook
      cargoSetupHook
      maturinBuildHook
      pkg-config
    ] ++ (optionals vendor [ cmake ragel util-linux ]));
  dontUseCmakeConfigure = true;

  checkInputs = [ python3Packages.pytest ];
  checkPhase = ''
    py.test
  '';
}
