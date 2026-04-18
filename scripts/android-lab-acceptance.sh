#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/build/android-lab-acceptance"
RUN_CONNECTED=1
DEVICE_SERIAL="${ANDROID_SERIAL:-}"
REMOTE_REPO_PATH="${ANDROID_LAB_REMOTE_REPO_PATH:-}"
MAC_HOST_SSH="${ANDROID_LAB_MAC_HOST_SSH:-}"
MAC_HOST_BIND="${ANDROID_LAB_MAC_HOST_BIND:-}"
LINUX_HOST_SSH="${ANDROID_LAB_LINUX_HOST_SSH:-}"
LINUX_HOST_BIND="${ANDROID_LAB_LINUX_HOST_BIND:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --artifact-dir)
            ARTIFACT_DIR="$2"
            shift 2
            ;;
        --skip-connected)
            RUN_CONNECTED=0
            shift
            ;;
        --device)
            DEVICE_SERIAL="$2"
            shift 2
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 1
            ;;
    esac
done

mkdir -p "$ARTIFACT_DIR"

start_remote_hostd() {
    local label="$1"
    local ssh_target="$2"
    local bind_addr="$3"
    if [[ -z "$ssh_target" || -z "$bind_addr" || -z "$REMOTE_REPO_PATH" ]]; then
        return 0
    fi

    ssh "$ssh_target" "cd '$REMOTE_REPO_PATH' && nohup ./scripts/run-hostd-acceptance.sh --bind '$bind_addr' > /tmp/codex-island-${label}-hostd.log 2>&1 & echo \$! > /tmp/codex-island-${label}-hostd.pid"
    ssh "$ssh_target" "cat /tmp/codex-island-${label}-hostd.pid"
}

collect_remote_logs() {
    local label="$1"
    local ssh_target="$2"
    if [[ -z "$ssh_target" ]]; then
        return 0
    fi

    ssh "$ssh_target" "test -f /tmp/codex-island-${label}-hostd.log && cat /tmp/codex-island-${label}-hostd.log || true" \
        >"$ARTIFACT_DIR/${label}-hostd.log" || true
}

stop_remote_hostd() {
    local label="$1"
    local ssh_target="$2"
    if [[ -z "$ssh_target" ]]; then
        return 0
    fi

    ssh "$ssh_target" "if test -f /tmp/codex-island-${label}-hostd.pid; then kill \$(cat /tmp/codex-island-${label}-hostd.pid) 2>/dev/null || true; rm -f /tmp/codex-island-${label}-hostd.pid; fi"
}

trap 'collect_remote_logs mac "$MAC_HOST_SSH"; collect_remote_logs linux "$LINUX_HOST_SSH"; stop_remote_hostd mac "$MAC_HOST_SSH"; stop_remote_hostd linux "$LINUX_HOST_SSH"' EXIT

start_remote_hostd mac "$MAC_HOST_SSH" "$MAC_HOST_BIND" >/dev/null
start_remote_hostd linux "$LINUX_HOST_SSH" "$LINUX_HOST_BIND" >/dev/null

if (( RUN_CONNECTED == 1 )); then
    "$ROOT_DIR/scripts/android-test.sh" --connected | tee "$ARTIFACT_DIR/android-test.log"
else
    "$ROOT_DIR/scripts/android-test.sh" | tee "$ARTIFACT_DIR/android-test.log"
fi

release_cmd=("$ROOT_DIR/scripts/android-release-smoke.sh" "--artifact-dir" "$ARTIFACT_DIR/release-smoke")
if [[ -n "$DEVICE_SERIAL" ]]; then
    release_cmd+=("--device" "$DEVICE_SERIAL")
fi
"${release_cmd[@]}"

python3 - "$ARTIFACT_DIR" "$MAC_HOST_SSH" "$MAC_HOST_BIND" "$LINUX_HOST_SSH" "$LINUX_HOST_BIND" <<'PY'
import json
import os
import sys

artifact_dir, mac_ssh, mac_bind, linux_ssh, linux_bind = sys.argv[1:]
summary = {
    "suite": "android-lab-acceptance",
    "status": "passed",
    "artifacts": {
        "android_test_log": os.path.join(artifact_dir, "android-test.log"),
        "release_smoke_summary": os.path.join(artifact_dir, "release-smoke", "summary.json"),
        "mac_hostd_log": os.path.join(artifact_dir, "mac-hostd.log"),
        "linux_hostd_log": os.path.join(artifact_dir, "linux-hostd.log"),
    },
    "remote_hosts": {
        "macos": {"ssh": mac_ssh, "bind": mac_bind},
        "linux": {"ssh": linux_ssh, "bind": linux_bind},
    },
}
with open(os.path.join(artifact_dir, "summary.json"), "w", encoding="utf-8") as fh:
    json.dump(summary, fh, ensure_ascii=False, indent=2)
PY
