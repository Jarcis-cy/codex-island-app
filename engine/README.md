# codex-island-engine

Shared Rust workspace for the cross-platform Codex Island engine.

This workspace is now the stable home for:

- engine protocol definitions
- shared client runtime and reducers
- host daemon process management
- future Kotlin / Swift FFI bindings

The current implementation is still scaffold-level, but the repository now
organizes all engine work under `engine/` instead of the old `sidecar/`
placeholder.
