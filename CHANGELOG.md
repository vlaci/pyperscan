# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- --8<-- [start:changelog] -->

## Unreleased

### Added

- Free-threaded (no-GIL) CPython 3.14t support. `Pattern` and scanner objects can be passed between threads

### Changed

- Dropped the Intel Hyperscan backend (the `hyperscan` Cargo feature, `just build-static-hyperscan` and the `hyperscan` Nix package)
- Switched to uv project manager from PDM [#43](https://github.com/vlaci/pyperscan/issues/43)
- Updated codebase to support PyO3 0.23 [#39](https://github.com/vlaci/pyperscan/issues/39)

## [0.3.0](https://github.com/vlaci/pyperscan/tree/0.3.0) - 2023-12-12


### Added

- Support added for musllinux (Alpine Linux) wheels [#16](https://github.com/vlaci/pyperscan/issues/16)


### Changed

- Build separate x86_64 and aarch64 wheels for macOS [#17](https://github.com/vlaci/pyperscan/issues/17)
- Using [PDM](https://pdm.fming.dev) for project management [#19](https://github.com/vlaci/pyperscan/issues/19)


### Fixed

- Linux wheels are now built with release optimizations [#30](https://github.com/vlaci/pyperscan/issues/30)
