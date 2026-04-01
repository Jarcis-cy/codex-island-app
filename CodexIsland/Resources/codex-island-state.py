#!/usr/bin/env python3
"""
Codex Island hook helper.

- Receives Codex hooks payloads on stdin.
- Normalizes them for Codex Island.app via Unix socket.
- Uses transcript_path as the durable source of truth for later reconciliation.
"""

import json
import os
import socket
import sys
from datetime import datetime

SOCKET_PATH = "/tmp/codex-island.sock"
DEBUG_LOG_PATH = os.path.expanduser("~/.codex/hooks/codex-island-debug.jsonl")


def append_debug(record):
    try:
        with open(DEBUG_LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def get_tty():
    parent_pid = os.getppid()
    try:
        import subprocess

        result = subprocess.run(
            ["ps", "-p", str(parent_pid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=1,
        )
        tty = result.stdout.strip()
        if tty and tty not in {"??", "-"}:
            return tty if tty.startswith("/dev/") else f"/dev/{tty}"
    except Exception:
        pass

    try:
        return os.ttyname(sys.stdin.fileno())
    except OSError:
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except OSError:
        pass
    return None


def send_event(state):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        sock.close()
        return True
    except OSError as error:
        append_debug({
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "stage": "socket_error",
            "error": str(error),
            "state": state,
        })
        return False


def normalize_tool_input(payload):
    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        return tool_name, tool_input

    command = None
    if isinstance(tool_input, dict):
        command = tool_input.get("command")

    if payload.get("tool_input", {}).get("command"):
        command = payload["tool_input"]["command"]

    if command is None and payload.get("tool_input"):
        command = payload["tool_input"].get("command")

    if command is None and payload.get("command"):
        command = payload.get("command")

    if command is not None:
        return tool_name, {"command": command}

    return tool_name, {}


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    event = payload.get("hook_event_name", "")
    session_id = payload.get("session_id", "unknown")
    cwd = payload.get("cwd", "")
    transcript_path = payload.get("transcript_path")
    turn_id = payload.get("turn_id")
    tool_name, tool_input = normalize_tool_input(payload)

    state = {
        "provider": "codex",
        "session_id": session_id,
        "cwd": cwd,
        "transcript_path": transcript_path,
        "turn_id": turn_id,
        "event": event,
        "pid": os.getppid(),
        "tty": get_tty(),
        "terminal_name": os.environ.get("TERM_PROGRAM") or os.environ.get("TERM"),
    }

    if event == "SessionStart":
        state["status"] = "waiting_for_input"
    elif event == "UserPromptSubmit":
        state["status"] = "processing"
    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        state["tool_use_id"] = payload.get("tool_use_id")
    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        state["tool_use_id"] = payload.get("tool_use_id")
    elif event == "Stop":
        state["status"] = "waiting_for_input"
    else:
        state["status"] = "notification"

    sent = send_event(state)
    append_debug({
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "stage": "hook_received",
        "event": event,
        "sent": sent,
        "payload": payload,
        "state": state,
        "env": {
            "TERM_PROGRAM": os.environ.get("TERM_PROGRAM"),
            "TERM": os.environ.get("TERM"),
            "TMUX": os.environ.get("TMUX"),
        }
    })


if __name__ == "__main__":
    main()
