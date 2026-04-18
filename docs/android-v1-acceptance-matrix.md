# Android V1 Acceptance Matrix

Last updated: 2026-04-16

## Scope

This matrix tracks Android direct-connect shell v1 validation across:

- Android shell build and local UI smoke
- shared hostd/app-server harness coverage
- reachable macOS and Linux host flows
- reconnect and upstream recovery behavior
- release APK install-and-launch smoke on a physical device

## Current Outcome

- Android local build, JVM tests, and instrumentation smoke are passing on the local `codex-island-api35` emulator.
- Android instrumentation now covers SSH mode switching, SSH key generation, thread actions, approval handling, and request-user-input UI flows using an injected test runtime.
- Android now auto-packages the shared Rust FFI library during Gradle `preBuild`, and instrumentation smoke confirms the runtime loads on-device.
- Android release smoke now has a dedicated script that builds `assembleRelease`, installs the APK on a connected device, launches it, and captures logs and artifacts.
- Android live websocket transport is wired for pair, thread list/start/resume, send/steer, approval response, request-user-input response, interrupt, and reconnect state handling.
- `codex-island-hostd` integration coverage is passing for pair/auth, thread list, send, interrupt, approval, request-user-input, restart recovery, and a real `codex app-server --listen stdio://` initialize-plus-follow-up handshake.
- Real reachable macOS/Linux validation is still blocked only by the absence of configured acceptance hosts in the current local environment.

## Matrix

| Area | Scenario | Environment | Status | Evidence |
| --- | --- | --- | --- | --- |
| Android shell | `assembleDebug` + JVM tests | Local macOS dev machine | Passed | `./scripts/android-test.sh` |
| Android shell | Instrumentation UI workflows (`MainActivity`, SSH mode, approvals, request-user-input) | `codex-island-api35` emulator | Passed | `./scripts/android-test.sh --connected` |
| Android shell | Release install/launch smoke | Connected Android device | Ready | `./scripts/android-release-smoke.sh` |
| Host daemon | Pair/auth token persistence | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Thread list/send/interrupt harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Approval + request_user_input harness | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Upstream restart recovery | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| Host daemon | Real `codex app-server` initialize + JSONL follow-up | Rust unit/integration tests | Passed | `cargo test -p codex-island-hostd` |
| macOS host real flow | Pair Android shell to reachable macOS host | Real host not configured | Blocked | Requires configured macOS acceptance host |
| Linux host real flow | Pair Android shell to reachable Linux host | Real host not configured | Blocked | Requires configured Linux acceptance host |
| Android reconnect | Foreground reconnect after host/profile restore | Real host not configured | Blocked | Android live transport is wired; pending real host rerun |
| Upstream recovery | Android sees hostd/app-server restart and recovers | Real host not configured | Blocked | Hostd harness passes; pending Android live host rerun |

## Notes

- The Android shell now includes host profile management, thread/chat workspace state, approval/user-input cards, command previews, and Android-packaged shared native libraries.
- The connected Android test now validates the main user-facing UI workflows against an injected runtime, but it still does not prove real host traffic.
- Use `./scripts/android-release-smoke.sh` to validate release build, device install, launch, log capture, and screenshot collection on a real Android device.
- Use `./scripts/run-hostd-acceptance.sh --bind <reachable-host>:7331` on a macOS or Linux host to start a real hostd endpoint for Android acceptance runs.
- Use `./scripts/android-lab-acceptance.sh` as the layered local acceptance entry point; it combines connected Android tests, release smoke, and optional remote hostd lifecycle/log collection.
- After Android native packaging landed, the remaining rerun target is:
  - one reachable macOS host
  - one reachable Linux host
  - the existing `codex-island-api35` emulator or a real Android device

## Recommended Next Run

1. Run `.github/workflows/android-preflight.yml` or locally execute `./scripts/android-test.sh --connected`.
2. Connect a physical Android device and run `./scripts/android-release-smoke.sh`.
3. On each macOS/Linux acceptance host, run `./scripts/run-hostd-acceptance.sh --bind <reachable-host>:7331`, or set the corresponding `ANDROID_LAB_*` variables and use `./scripts/android-lab-acceptance.sh`.
4. Repeat:
   - pair start / confirm
   - thread list
   - thread start / resume
   - send / steer
   - approval allow / deny
   - request_user_input response
   - interrupt
   - hostd restart / app-server restart recovery
