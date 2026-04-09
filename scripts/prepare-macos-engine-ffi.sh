#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
GENERATED_DIR="$ROOT_DIR/apps/macos/Generated/Engine"
OUT_DIR="${1:-}"

if [[ -z "$OUT_DIR" ]]; then
    echo "usage: $0 <frameworks-output-dir>" >&2
    exit 1
fi

cd "$ENGINE_DIR"

cargo build --release -p codex-island-client-ffi >/dev/null

LIB_PATH="$ENGINE_DIR/target/release/libcodex_island_client_ffi.dylib"
if [[ ! -f "$LIB_PATH" ]]; then
    echo "missing UniFFI dynamic library at $LIB_PATH" >&2
    exit 1
fi

mkdir -p "$GENERATED_DIR" "$OUT_DIR"

if [[ -f "$GENERATED_DIR/codex_island_clientFFI.modulemap" ]]; then
    cp "$GENERATED_DIR/codex_island_clientFFI.modulemap" "$GENERATED_DIR/module.modulemap"
fi

temp_lib="$(mktemp "${TMPDIR:-/tmp}/codex_island_client_ffi.XXXXXX.dylib")"
cp "$LIB_PATH" "$temp_lib"
install_name_tool -id "@rpath/libcodex_island_client_ffi.dylib" "$temp_lib"
cp "$temp_lib" "$OUT_DIR/libcodex_island_client_ffi.dylib"
rm -f "$temp_lib"
