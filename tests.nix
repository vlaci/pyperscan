{ lib
, stdenv
, system
, fenix
, makeRustPlatform
, rustPlatform
, pyFilter
, testFilter
, cargo-llvm-cov
, python3
, pyperscan
, ruff
}:

{
  checks = with python3.pkgs; buildPythonPackage {
    inherit (pyperscan) version;
    pname = "${pyperscan.pname}-tests-checks";
    format = "other";

    src = lib.cleanSourceWith {
      src = ./.;
      filter = p: t: (pyFilter p t) || (testFilter p t);
    };

    dontBuild = true;
    dontInstall = true;

    nativeCheckInputs = [
      mypy
      ruff
      pyperscan
    ];

    checkPhase = ''
      #mypy .
      ruff .
    '';
  };

  coverage =
    let
      rust-toolchain-llvm-tools = fenix.packages.${system}.complete.withComponents [
        "llvm-tools-preview"
        "cargo"
        "rustc"
      ];
      rustPlatform-cov = makeRustPlatform {
        inherit stdenv;
        cargo = rust-toolchain-llvm-tools;
        rustc = rust-toolchain-llvm-tools;
      };
      pyperscan-cov = pyperscan.override { coverage = true; rustPlatform = rustPlatform-cov; rustc = rust-toolchain-llvm-tools; cargo = rust-toolchain-llvm-tools; };
    in
    with python3.pkgs; buildPythonPackage {

      inherit (pyperscan-cov) version cargoDeps;
      pname = "${pyperscan-cov.pname}-tests-pytest";
      format = "other";

      src = lib.cleanSourceWith {
        src = ./.;
        filter = p: t: (pyFilter p t) || (testFilter p t) || builtins.match "Cargo.(toml|lock)" != null;

      };

      dontBuild = true;
      dontInstall = true;

      nativeCheckInputs = with python3.pkgs; [
        cargo-llvm-cov
        pytestCheckHook
        pyperscan-cov
        rust-toolchain-llvm-tools
      ];

      nativeBuildInputs = with rustPlatform-cov; [
        cargoSetupHook
      ];

      preConfigure = ''
        source <(cargo llvm-cov show-env --export-prefix)
        LLVM_COV_FLAGS=$(python -c 'import pyperscan; print(pyperscan._pyperscan.__file__, end="")')
        export LLVM_COV_FLAGS
      '';

      postCheck = ''
        rm -r $out
        cargo llvm-cov report -vv --ignore-filename-regex cargo-vendor-dir --codecov --output-path $out
      '';
    };
  pytest = python3.pkgs.buildPythonPackage
    {
      inherit (pyperscan) version;
      pname = "${pyperscan.pname}-tests-pytest";
      format = "other";

      src = lib.cleanSourceWith {
        src = ./.;
        filter = p: t: (testFilter p t);
      };

      dontBuild = true;
      dontInstall = true;

      nativeCheckInputs = with python3.pkgs; [
        pyperscan
        pytestCheckHook
      ];
    };
}
