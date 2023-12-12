# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This project uses [_towncrier_](https://towncrier.readthedocs.io/) and the changes for the upcoming release can be found in <https://github.com/twisted/my-project/tree/main/changelog.d/>.

<!-- --8<-- [start:changelog] -->

<!-- towncrier release notes start -->

## [0.3.0](https://github.com/vlaci/pyperscan/tree/0.3.0) - 2023-12-12


### Added

- Support added for musllinux (Alpine Linux) wheels [#16](https://github.com/vlaci/pyperscan/issues/16)


### Changed

- Build separate x86_64 and aarch64 wheels for macOS [#17](https://github.com/vlaci/pyperscan/issues/17)
- Using [PDM](https://pdm.fming.dev) for project management [#19](https://github.com/vlaci/pyperscan/issues/19)


### Fixed

- Linux wheels are now built with release optimizations [#30](https://github.com/vlaci/pyperscan/issues/30)
