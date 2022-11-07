set positional-arguments

help:
    @just --list --unsorted

clean:
    rm -fr -- .venv target

dev:
    python3 -m venv .venv
    . .venv/bin/activate && maturin develop -E test

check:
    cargo clippy

test *args="--":
    .venv/bin/py.test "$@"

build-shared: _build
build-static-hyperscan: (_build "-F" "hyperscan")
build-static-vectorscan: (_build "-F" "vectorscan")

_build *args="--":
    maturin build "$@"
