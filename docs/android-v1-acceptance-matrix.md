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
- Android now auto-packages the shared Rust FFI library during Gradle `preBuild`, and instrumentation smoke confirms the runtime loads on-device.
- `codex-island-hostd` integration coverage is passing for thread list, send, interrupt, approval, request-user-input, and restart recovery.
- Real same-tailnet host validation is still blocked because no configured same-tailnet macOS/Linux acceptance hosts were available in the current local environment.

## Matrix

| Area | Scenario | Environment | Status | Evidence |
| --- | --- | --- | --- | --- |
| Android shell | `assembleDebug` + JVM tests | Local macOS dev machine | Passed | `./scripts/android-test.sh` |
| Android shell | Instrumentation smoke (`MainActivity` + native runtime load) | `codex-island-api35` emulator | Passed | `./scripts/android-test.sh --connected` |
| Host daemon | Pair/auth token persistence | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Thread list/send/interrupt harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Approval + request_user_input harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Upstream restart recovery | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| macOS host real flow | Pair Android shell to same-tailnet macOS host | Real host not configured | Blocked | Requires configured same-tailnet macOS host |
| Linux host real flow | Pair Android shell to same-tailnet Linux host | Real host not configured | Blocked | Requires configured same-tailnet Linux host |
| Android reconnect | Foreground reconnect after host/profile restore | Real transport not wired to host yet | Blocked | Native packaging is done; live host transport validation still pending |
| Upstream recovery | Android sees hostd/app-server restart and recovers | Real transport not wired to host yet | Blocked | Hostd harness passes, Android live validation pending |

## Notes

- The Android shell now includes host profile management, thread/chat workspace state, approval/user-input cards, command previews, and Android-packaged shared native libraries.
- The connected Android test currently validates app install/launch and the top-level UI smoke only; it does not cover same-tailnet traffic.
- After Android native packaging landed, the remaining rerun target is:
  - one macOS host on the same tailnet
  - one Linux host on the same tailnet
  - the existing `codex-island-api35` emulator or a real Android device

## Recommended Next Run

1. Prepare one macOS host and one Linux host with reachable Tailscale addresses and running `hostd`/`codex app-server`.
2. Wire the Android shell's preview-driven transport path to those live hosts.
3. Repeat:
   - pair start / confirm
   - thread list
   - thread start / resume
   - send / steer
   - approval allow / deny
   - request_user_input response
   - interrupt
   - hostd restart / app-server restart recovery
