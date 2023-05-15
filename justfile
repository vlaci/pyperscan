set positional-arguments

sudo := `command -v sudo || command -v doas`
builder_image_prefix := "ghcr.io/vlaci/pyperscan-builder"

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
    .venv/bin/pytest "$@"

build-shared: _build
build-static-hyperscan: (_build "-F" "hyperscan")
build-static-vectorscan: (_build "-F" "vectorscan")

wheel target: (ensure-foreign-emulation target) (_build_container target) (_build_in_container target) (_test_in_container target)

_build_container target:
    #! /usr/bin/env bash
    set -xeuo pipefail
    containerfile=Containerfile.{{ target }}
    cache_tag=$(< $containerfile openssl sha256 -binary |  openssl sha256 -r | cut -d " " -f 1)
    image={{ builder_image_prefix }}-{{ target }}
    if ! podman pull $image:$cache_tag; then
        podman pull $image:latest || true
        podman build -t $image:$cache_tag -f $containerfile
    fi
    podman tag $image:$cache_tag $image:latest

_build_in_container target:
    podman run -v .:/usr/src/pyperscan -v ~/.cargo/registry:/root/.cargo/registry {{ builder_image_prefix }}-{{ target }}

_test_in_container target:
    #! /usr/bin/env bash
    set -xeuo pipefail
    cat <<"EOF" | podman run -v .:/usr/src/pyperscan -i {{ builder_image_prefix }}-{{ target }} bash -
        cd /usr/src/pyperscan
        ARCH=$(echo "{{ target }}" | cut -d- -f1)
        whl=(dist/pyperscan-*$ARCH*.whl)
        curl -sSL https://raw.githubusercontent.com/pdm-project/pdm/main/install-pdm.py | python3.10 -
        export PATH=/root/.local/bin:$PATH
        pdm sync -d --no-self -G test
        pdm run python -m ensurepip
        pdm run python -m pip install $whl
        pdm run pytest
    EOF

ensure-foreign-emulation target:
    #! /usr/bin/env bash
    set -xeuo pipefail
    if [[ "{{ target }}" == aarch64-* ]] \
        && ! [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64  &&
        $(head -n 1 /proc/sys/fs/binfmt_misc/qemu-aarch64) == "enabled" ]]
    then
        {{ sudo }} podman run --privileged --rm tonistiigi/binfmt --install arm64
    fi

_build *args="--":
    maturin build "$@"
