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
    mkdir -p ~/.cargo/registry
    podman run -v .:/usr/src/pyperscan -v ~/.cargo/registry:/root/.cargo/registry {{ builder_image_prefix }}-{{ target }}

_test_in_container target:
    #! /usr/bin/env bash
    set -xeuo pipefail
    cat <<"EOF" | podman run -v .:/usr/src/pyperscan -i {{ builder_image_prefix }}-{{ target }} bash -
        set -euo pipefail
        cd /usr/src/pyperscan
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH=/root/.local/bin:$PATH
        for py in cp311-cp311 cp314-cp314t cp315-cp315 cp315-cp315t; do
            export VIRTUAL_ENV=/tmp/venv-$py UV_PROJECT_ENVIRONMENT=/tmp/venv-$py
            uv sync --no-install-project --only-group test --python /opt/python/$py/bin/python
            uv pip install --no-index --no-build --find-links dist pyperscan
            $VIRTUAL_ENV/bin/pytest
        done
    EOF

ensure-foreign-emulation target:
    #! /usr/bin/env bash
    set -xeuo pipefail
    if [[ "{{ target }}" != "$(uname -m)"* ]] \
        && ! [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64  &&
        $(head -n 1 /proc/sys/fs/binfmt_misc/qemu-aarch64) == "enabled" ]]
    then
        {{ sudo }} podman run --privileged --rm tonistiigi/binfmt --install arm64
    fi

_build *args="--":
    maturin build "$@"
