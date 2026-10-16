#!/bin/bash
# Milestone 2: build xodus-cli (Minecraft sign-in + download) for macOS.
#
#   bash scripts/build-xodus-macos.sh
#
# Native arm64 on Apple Silicon (it's a downloader, not game code, so no Rosetta).
# Output: $MCB_WORK/dist/xodus-cli
# Env: MCB_WORK (default ~/MCBedrockForMac-work), MCB_SKIP_BREW=1.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${MCB_WORK:-$HOME/MCBedrockForMac-work}"
SRC="$WORK/xodus-src"
DIST="$WORK/dist"

# shellcheck source=../third_party/xodus.env
. "$REPO/third_party/xodus.env"

echo "== Host: $(sw_vers -productVersion) $(uname -m)"
if [ "${MCB_SKIP_BREW:-0}" != "1" ]; then
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
    brew install protobuf cmake
fi
command -v rustup >/dev/null || { echo "!! needs rustup (https://rustup.rs)" >&2; exit 1; }
rustup toolchain install stable --profile minimal >/dev/null
echo "rust: $(rustc +stable --version)"

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$XODUS_COMMIT" ]; then
    echo "== Fetching xodus $XODUS_COMMIT"
    rm -rf "$SRC"
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$XODUS_REPO"
    git -C "$SRC" fetch -q --depth 1 origin "$XODUS_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
fi
git -C "$SRC" checkout -q -- .
for p in "$REPO"/patches/xodus/*.patch; do
    echo "== Applying $(basename "$p")"
    git -C "$SRC" apply "$p"
done

echo "== Building xodus-cli"
cargo +stable build --release --locked --manifest-path "$SRC/Cargo.toml" -p xodus-cli

mkdir -p "$DIST"
cp "$SRC/target/release/xodus-cli" "$DIST/xodus-cli"
echo "== Built $DIST/xodus-cli ($(file -b "$DIST/xodus-cli"))"
"$DIST/xodus-cli" --version 2>/dev/null || true
"$DIST/xodus-cli" --help
