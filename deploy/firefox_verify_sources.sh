#!/usr/bin/env bash

# Rebuilds the Firefox package from its source archive the way an AMO reviewer does, in an environment that
# holds nothing but the archive, and fails when a shipped file differs from the package being submitted.

set -euo pipefail

SOURCES=$(realpath "$1")
PACKAGE=$(realpath "$2")
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir "$WORK_DIR/src" "$WORK_DIR/home" "$WORK_DIR/submitted" "$WORK_DIR/rebuilt"
tar -xzf "$SOURCES" -C "$WORK_DIR/src"

(
  cd "$WORK_DIR/src"
  env -i HOME="$WORK_DIR/home" PATH="$PATH" bash -c 'npm ci --no-audit --no-fund && npm run extension-firefox:package'
) > "$WORK_DIR/build.log" 2>&1 || {
  tail -50 "$WORK_DIR/build.log"
  exit 1
}

unzip -q "$PACKAGE" -d "$WORK_DIR/submitted"
unzip -q "$WORK_DIR/src/MyWallet-firefox.zip" -d "$WORK_DIR/rebuilt"

# `build.txt` records when the build ran, and the bundler names the assets referenced from the sources
# embedded in `.map` files at random, so neither matches between two builds of one tree.
diff -rq -x build.txt -x '*.map' "$WORK_DIR/submitted" "$WORK_DIR/rebuilt"
