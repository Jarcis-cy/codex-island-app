# Android V1 Acceptance Matrix

Last updated: 2026-04-09

## Scope

This matrix tracks Android direct-connect shell v1 validation across:

- Android shell build and local UI smoke
- shared hostd/app-server harness coverage
- same-tailnet macOS and Linux host flows
- reconnect and upstream recovery behavior

## Current Outcome

- Android local build, JVM tests, and instrumentation smoke are passing on the local `codex-island-api35` emulator.
- `codex-island-hostd` integration coverage is passing for thread list, send, interrupt, approval, request-user-input, and restart recovery.
- Real same-tailnet host validation is still blocked in this repo state by two missing prerequisites:
  - Android does not yet package an Android-loadable `island-client-ffi` native library. This is tracked by `codex-island-pq3t`.
  - No configured same-tailnet macOS/Linux acceptance hosts were available in the current local environment.

## Matrix

| Area | Scenario | Environment | Status | Evidence |
| --- | --- | --- | --- | --- |
| Android shell | `assembleDebug` + JVM tests | Local macOS dev machine | Passed | `./scripts/android-test.sh` |
| Android shell | Instrumentation smoke (`MainActivity`) | `codex-island-api35` emulator | Passed | `./scripts/android-test.sh --connected` |
| Host daemon | Pair/auth token persistence | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Thread list/send/interrupt harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Approval + request_user_input harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Upstream restart recovery | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| macOS host real flow | Pair Android shell to same-tailnet macOS host | Real host not configured | Blocked | Requires real tailnet host + `codex-island-pq3t` |
| Linux host real flow | Pair Android shell to same-tailnet Linux host | Real host not configured | Blocked | Requires real tailnet host + `codex-island-pq3t` |
| Android reconnect | Foreground reconnect after host/profile restore | Real transport not wired | Blocked | Requires native FFI packaging + live transport |
| Upstream recovery | Android sees hostd/app-server restart and recovers | Real transport not wired | Blocked | Hostd harness passes, Android live validation pending |

## Notes

- The Android shell now includes host profile management, thread/chat workspace state, approval/user-input cards, and command previews, but the transport is still preview-driven until Android can load the shared native library.
- The connected Android test currently validates app install/launch and the top-level UI smoke only; it does not cover same-tailnet traffic.
- Once `codex-island-pq3t` lands, rerun this matrix on:
  - one macOS host on the same tailnet
  - one Linux host on the same tailnet
  - the existing `codex-island-api35` emulator or a real Android device

## Recommended Next Run

1. Complete `codex-island-pq3t` so Android can load the shared client runtime for real transport work.
2. Prepare one macOS host and one Linux host with reachable Tailscale addresses and running `hostd`/`codex app-server`.
3. Repeat:
   - pair start / confirm
   - thread list
   - thread start / resume
   - send / steer
   - approval allow / deny
   - request_user_input response
   - interrupt
   - hostd restart / app-server restart recovery
