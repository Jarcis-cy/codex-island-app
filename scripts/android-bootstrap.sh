#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/apps/android"
LOCAL_PROPERTIES="$ANDROID_DIR/local.properties"
STRICT=0

if [[ "${1:-}" == "--strict" ]]; then
    STRICT=1
fi

java_home_is_supported() {
    local candidate="$1"
    local version_output major_version

    [[ -x "$candidate/bin/java" ]] || return 1

    version_output="$("$candidate/bin/java" -version 2>&1 | head -n 1)"
    major_version="$(printf '%s\n' "$version_output" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
    [[ "$major_version" == "17" || "$major_version" == "21" ]]
}

find_java_home() {
    if [[ -n "${JAVA_HOME:-}" ]] && java_home_is_supported "${JAVA_HOME}"; then
        echo "$JAVA_HOME"
        return 0
    fi

    if command -v /usr/libexec/java_home >/dev/null 2>&1; then
        for version in 17 21; do
            if /usr/libexec/java_home -v "$version" >/dev/null 2>&1; then
                /usr/libexec/java_home -v "$version"
                return 0
            fi
        done
    fi

    return 1
}

find_android_sdk() {
    if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
        echo "$ANDROID_SDK_ROOT"
        return 0
    fi

    if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
        echo "$ANDROID_HOME"
        return 0
    fi

    if [[ -d "$HOME/Library/Android/sdk" ]]; then
        echo "$HOME/Library/Android/sdk"
        return 0
    fi

    return 1
}

resolve_android_sdk_root() {
    local candidate="$1"
    local linked_root

    if [[ -d "$candidate/platforms/android-35" || -d "$candidate/build-tools/35.0.0" || -d "$candidate/platform-tools" ]]; then
        echo "$candidate"
        return 0
    fi

    if [[ -L "$candidate/cmdline-tools/latest" ]] || [[ -d "$candidate/cmdline-tools/latest" ]]; then
        linked_root="$(
            python3 - "$candidate/cmdline-tools/latest" <<'PY'
import os
import sys

path = sys.argv[1]
real = os.path.realpath(path)
print(os.path.dirname(os.path.dirname(real)))
PY
        )"
        if [[ -n "$linked_root" ]]; then
            echo "$linked_root"
            return 0
        fi
    fi

    echo "$candidate"
}

find_android_ndk() {
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

    if [[ -d "$1/ndk" ]]; then
        find "$1/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1
        return 0
    fi

    return 1
}

JAVA_HOME_VALUE="$(find_java_home || true)"
if [[ -z "$JAVA_HOME_VALUE" ]]; then
    echo "missing supported JDK. Install JDK 17 or 21 and set JAVA_HOME." >&2
    exit 1
fi

ANDROID_SDK_VALUE="$(find_android_sdk || true)"
if [[ -z "$ANDROID_SDK_VALUE" ]]; then
    echo "missing Android SDK. Set ANDROID_SDK_ROOT or install Android Studio SDK components to ~/Library/Android/sdk." >&2
    exit 1
fi

ANDROID_SDK_VALUE="$(resolve_android_sdk_root "$ANDROID_SDK_VALUE")"
ANDROID_NDK_VALUE="$(find_android_ndk "$ANDROID_SDK_VALUE" || true)"

mkdir -p "$ANDROID_DIR"
printf 'sdk.dir=%s\n' "$ANDROID_SDK_VALUE" > "$LOCAL_PROPERTIES"

echo "JAVA_HOME=$JAVA_HOME_VALUE"
echo "ANDROID_SDK_ROOT=$ANDROID_SDK_VALUE"
if [[ -n "$ANDROID_NDK_VALUE" ]]; then
    echo "ANDROID_NDK_ROOT=$ANDROID_NDK_VALUE"
fi
echo "local.properties -> $LOCAL_PROPERTIES"

missing=()
[[ -d "$ANDROID_SDK_VALUE/platforms/android-35" ]] || missing+=("platforms;android-35")
[[ -d "$ANDROID_SDK_VALUE/build-tools/35.0.0" ]] || missing+=("build-tools;35.0.0")
[[ -d "$ANDROID_SDK_VALUE/platform-tools" ]] || missing+=("platform-tools")
[[ -n "$ANDROID_NDK_VALUE" ]] || missing+=("ndk;27.0.12077973")

if (( ${#missing[@]} > 0 )); then
    echo "missing SDK components: ${missing[*]}" >&2
    echo "install with sdkmanager under $ANDROID_SDK_VALUE" >&2
    if (( STRICT == 1 )); then
        exit 1
    fi
fi
