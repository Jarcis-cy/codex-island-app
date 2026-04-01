# codex-island-sidecar

Rust sidecar scaffold for future Codex session aggregation and IPC.

Current app behavior is still hooks-first inside the macOS process. This crate
exists so the repo has a stable place to move transcript parsing, state
aggregation, and local IPC once the Swift implementation is proven out.
