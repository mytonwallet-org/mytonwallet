#!/usr/bin/env bash

# Builds `tlottie-simd.wasm` and `tlottie-scalar.wasm` of `src/lib/tlottie` from the pinned commit of
# https://github.com/dkaraush/tlottie. The committed files are the x86_64 Linux output: rustc on an arm64 Mac
# emits different modules of the same size.

set -euo pipefail

TLOTTIE_COMMIT=c461cd5c295b1abb9b4e8cd62bd875d9b4d676e3
RUST_TOOLCHAIN=1.96.0

OUTPUT_DIR="$(cd "${1:-src/lib/tlottie}" && pwd)"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --target wasm32-unknown-unknown

git clone --quiet https://github.com/dkaraush/tlottie.git "$WORK_DIR/tlottie"
git -C "$WORK_DIR/tlottie" checkout --quiet "$TLOTTIE_COMMIT"

build() {
  local name=$1 rustflags=$2

  (
    cd "$WORK_DIR/tlottie"
    RUSTFLAGS="$rustflags" cargo "+$RUST_TOOLCHAIN" build \
      --target wasm32-unknown-unknown \
      --target-dir "target-$name" \
      --profile release-size \
      --no-default-features \
      --features wasm \
      --lib \
      --locked
  )

  cp "$WORK_DIR/tlottie/target-$name/wasm32-unknown-unknown/release-size/tlottie.wasm" "$OUTPUT_DIR/tlottie-$name.wasm"
}

build simd "-C target-feature=+simd128"
build scalar ""
