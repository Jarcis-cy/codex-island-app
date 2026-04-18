#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/apps/android"
PACKAGE_NAME="com.codexisland.android"
ACTIVITY_NAME="$PACKAGE_NAME/.MainActivity"
ARTIFACT_DIR="$ROOT_DIR/build/android-release-smoke"
DEVICE_SERIAL="${ANDROID_SERIAL:-}"
BOOTSTRAP_LOG="$(mktemp -t codex-island-android-bootstrap.XXXXXX)"
STATUS="failed"
FAILURE_REASON=""
APK_PATH=""
BUILD_TOOLS_DIR=""
SMOKE_KEYSTORE=""

write_report() {
    local exit_code="$1"
    mkdir -p "$ARTIFACT_DIR"
    if [[ "$exit_code" -eq 0 ]]; then
        STATUS="passed"
    elif [[ -z "$FAILURE_REASON" ]]; then
        FAILURE_REASON="android release smoke failed"
    fi

    python3 - "$ARTIFACT_DIR" "$STATUS" "$FAILURE_REASON" "$DEVICE_SERIAL" "$APK_PATH" <<'PY'
import json
import os
import sys
import xml.sax.saxutils as saxutils

artifact_dir, status, reason, device_serial, apk_path = sys.argv[1:]
summary = {
    "suite": "android-release-smoke",
    "status": status,
    "failure_reason": reason,
    "device_serial": device_serial,
    "apk_path": apk_path,
    "artifacts": {
        "am_start": os.path.join(artifact_dir, "am-start.txt"),
        "top_activity": os.path.join(artifact_dir, "top-activity.txt"),
        "logcat": os.path.join(artifact_dir, "logcat.txt"),
        "screenshot": os.path.join(artifact_dir, "screenshot.png"),
    },
}
with open(os.path.join(artifact_dir, "summary.json"), "w", encoding="utf-8") as fh:
    json.dump(summary, fh, ensure_ascii=False, indent=2)

message = "release smoke passed" if status == "passed" else reason or "release smoke failed"
failure_xml = ""
if status != "passed":
    failure_xml = f'<failure message="{saxutils.escape(message)}"/>'
xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="android-release-smoke" tests="1" failures="{0 if status == 'passed' else 1}">
  <testcase classname="android.release" name="launch_release_apk">
    {failure_xml}
  </testcase>
</testsuite>
"""
with open(os.path.join(artifact_dir, "junit.xml"), "w", encoding="utf-8") as fh:
    fh.write(xml)
PY
}
trap 'rc=$?; write_report "$rc"; rm -f "$BOOTSTRAP_LOG"; exit "$rc"' EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            DEVICE_SERIAL="$2"
            shift 2
            ;;
        --artifact-dir)
            ARTIFACT_DIR="$2"
            shift 2
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 1
            ;;
    esac
done

"$ROOT_DIR/scripts/android-bootstrap.sh" --strict >"$BOOTSTRAP_LOG"

JAVA_HOME_VALUE="$(grep '^JAVA_HOME=' "$BOOTSTRAP_LOG" | cut -d= -f2-)"
ANDROID_SDK_VALUE="$(grep '^ANDROID_SDK_ROOT=' "$BOOTSTRAP_LOG" | cut -d= -f2-)"

export JAVA_HOME="$JAVA_HOME_VALUE"
export ANDROID_SDK_ROOT="$ANDROID_SDK_VALUE"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

BUILD_TOOLS_DIR="$(find "$ANDROID_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
if [[ -z "$BUILD_TOOLS_DIR" || ! -d "$BUILD_TOOLS_DIR" ]]; then
    FAILURE_REASON="Android build-tools directory not found under $ANDROID_SDK_ROOT/build-tools"
    exit 1
fi

mkdir -p "$ARTIFACT_DIR"

ensure_smoke_keystore() {
    local candidate="${ANDROID_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"
    if [[ -f "$candidate" ]]; then
        SMOKE_KEYSTORE="$candidate"
        return 0
    fi

    SMOKE_KEYSTORE="$ARTIFACT_DIR/debug-smoke.keystore"
    keytool -genkeypair \
        -keystore "$SMOKE_KEYSTORE" \
        -storepass android \
        -keypass android \
        -alias androiddebugkey \
        -dname "CN=Android Debug,O=Android,C=US" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        >/dev/null 2>&1
}

sign_release_apk_for_smoke() {
    local unsigned_apk="$1"
    local signed_apk="$ARTIFACT_DIR/$(basename "${unsigned_apk%.apk}")-smoke-signed.apk"

    ensure_smoke_keystore
    "$BUILD_TOOLS_DIR/apksigner" sign \
        --ks "$SMOKE_KEYSTORE" \
        --ks-key-alias androiddebugkey \
        --ks-pass pass:android \
        --key-pass pass:android \
        --out "$signed_apk" \
        "$unsigned_apk"
    APK_PATH="$signed_apk"
}

adb_selector=()
if [[ -n "$DEVICE_SERIAL" ]]; then
    adb_selector=(-s "$DEVICE_SERIAL")
fi

adb_cmd() {
    adb "${adb_selector[@]}" "$@"
}

if [[ -z "$DEVICE_SERIAL" ]]; then
    mapfile -t detected_devices < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    if (( ${#detected_devices[@]} == 0 )); then
        FAILURE_REASON="no attached Android device for release smoke"
        exit 1
    fi
    DEVICE_SERIAL="${detected_devices[0]}"
    adb_selector=(-s "$DEVICE_SERIAL")
fi

pushd "$ANDROID_DIR" >/dev/null
./gradlew --no-daemon :app:assembleRelease
popd >/dev/null

APK_PATH="$(find "$ANDROID_DIR/app/build/outputs/apk/release" -name "*release*.apk" | head -n 1)"
if [[ -z "$APK_PATH" || ! -f "$APK_PATH" ]]; then
    FAILURE_REASON="release APK not found after assembleRelease"
    exit 1
fi

if [[ "$APK_PATH" == *"-unsigned.apk" ]]; then
    sign_release_apk_for_smoke "$APK_PATH"
fi

adb_cmd wait-for-device
adb_cmd logcat -c || true
adb_cmd install -r "$APK_PATH"
adb_cmd shell am force-stop "$PACKAGE_NAME" || true
adb_cmd shell am start -W -n "$ACTIVITY_NAME" >"$ARTIFACT_DIR/am-start.txt"
sleep 2

top_activity="$(adb_cmd shell dumpsys activity activities | grep -m1 "$PACKAGE_NAME" || true)"
printf '%s\n' "$top_activity" >"$ARTIFACT_DIR/top-activity.txt"
if [[ "$top_activity" != *"$PACKAGE_NAME"* ]]; then
    FAILURE_REASON="release APK did not become the active foreground activity"
    exit 1
fi

adb_cmd exec-out screencap -p >"$ARTIFACT_DIR/screenshot.png" || true
adb_cmd logcat -d >"$ARTIFACT_DIR/logcat.txt" || true
