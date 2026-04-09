#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
ANDROID_DIR="$ROOT_DIR/apps/android"
APP_DIR="$ANDROID_DIR/app"
OUT_DIR="$APP_DIR/build/generated/jniLibs/main"
API_LEVEL=28
ABIS=("arm64-v8a" "x86_64")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --api-level)
            API_LEVEL="$2"
            shift 2
            ;;
        --abis)
            IFS=',' read -r -a ABIS <<<"$2"
            shift 2
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 1
            ;;
    esac
done

resolve_sdk_root() {
    if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
        echo "$ANDROID_SDK_ROOT"
        return 0
    fi

    if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
        echo "$ANDROID_HOME"
        return 0
    fi

    local local_properties="$ANDROID_DIR/local.properties"
    if [[ -f "$local_properties" ]]; then
        local sdk_dir
        sdk_dir="$(sed -n 's/^sdk\.dir=//p' "$local_properties" | tail -n 1)"
        if [[ -n "$sdk_dir" && -d "$sdk_dir" ]]; then
            echo "$sdk_dir"
            return 0
        fi
    fi

    if [[ -d "$HOME/Library/Android/sdk" ]]; then
        echo "$HOME/Library/Android/sdk"
        return 0
    fi

    return 1
}

resolve_ndk_root() {
    if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT}" ]]; then
        echo "$ANDROID_NDK_ROOT"
        return 0
    fi

    if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
        echo "$ANDROID_NDK_HOME"
        return 0
    fi

    if [[ -n "${NDK_HOME:-}" && -d "${NDK_HOME}" ]]; then
        echo "$NDK_HOME"
        return 0
    fi

    local sdk_root="$1"
    local newest_ndk
    newest_ndk="$(
        find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1
    )"
    if [[ -n "$newest_ndk" && -d "$newest_ndk" ]]; then
        echo "$newest_ndk"
        return 0
    fi

    return 1
}

resolve_ndk_prebuilt_bin() {
    local ndk_root="$1"
    local prebuilt_dir
    prebuilt_dir="$(
        find "$ndk_root/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d | head -n 1
    )"
    if [[ -z "$prebuilt_dir" ]]; then
        return 1
    fi
    echo "$prebuilt_dir/bin"
}

build_for_abi() {
    local abi="$1"
    local target linker output_subdir output_lib target_env_suffix

    case "$abi" in
        arm64-v8a)
            target="aarch64-linux-android"
            linker="$NDK_BIN_DIR/aarch64-linux-android${API_LEVEL}-clang"
            ;;
        x86_64)
            target="x86_64-linux-android"
            linker="$NDK_BIN_DIR/x86_64-linux-android${API_LEVEL}-clang"
            ;;
        *)
            echo "unsupported ABI: $abi" >&2
            exit 1
            ;;
    esac

    target_env_suffix="${target//-/_}"

    if [[ ! -x "$linker" ]]; then
        echo "missing Android linker for $abi: $linker" >&2
        exit 1
    fi

    output_subdir="$OUT_DIR/$abi"
    mkdir -p "$output_subdir"

    echo "building codex-island-client-ffi for $abi ($target)"
    (
        export "CC_${target_env_suffix}=$linker"
        export "AR_${target_env_suffix}=$NDK_BIN_DIR/llvm-ar"
        export "CARGO_TARGET_${target_env_suffix^^}_LINKER=$linker"
        cd "$ENGINE_DIR"
        cargo build -p codex-island-client-ffi --release --target "$target"
    )

    output_lib="$ENGINE_DIR/target/$target/release/libcodex_island_client_ffi.so"
    if [[ ! -f "$output_lib" ]]; then
        echo "missing Android shared library for $abi at $output_lib" >&2
        exit 1
    fi

    cp "$output_lib" "$output_subdir/libcodex_island_client_ffi.so"
}

SDK_ROOT="$(resolve_sdk_root || true)"
if [[ -z "$SDK_ROOT" ]]; then
    echo "missing Android SDK root. Run ./scripts/android-bootstrap.sh first." >&2
    exit 1
fi

NDK_ROOT="$(resolve_ndk_root "$SDK_ROOT" || true)"
if [[ -z "$NDK_ROOT" ]]; then
    echo "missing Android NDK. Install one with sdkmanager, for example:" >&2
    echo "  sdkmanager 'ndk;27.0.12077973'" >&2
    exit 1
fi

NDK_BIN_DIR="$(resolve_ndk_prebuilt_bin "$NDK_ROOT" || true)"
if [[ -z "$NDK_BIN_DIR" || ! -d "$NDK_BIN_DIR" ]]; then
    echo "failed to locate Android NDK LLVM toolchain under $NDK_ROOT" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
for abi in "${ABIS[@]}"; do
    build_for_abi "$abi"
done

echo "Android FFI libraries written to $OUT_DIR"
