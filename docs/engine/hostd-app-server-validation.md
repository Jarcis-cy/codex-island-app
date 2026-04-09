# hostd 管理 `codex app-server` 的生命周期验证

本次 spike 在 `engine/crates/island-hostd` 内补了一组最小 supervisor 验证基线，目标不是完整实现 host daemon，而是先锁住后续实现必须满足的进程语义。

当前已通过 Rust 单测覆盖的行为：

- 启动契约：通过 login shell 执行 `exec codex app-server --listen stdio://`，与现有 macOS shell 侧 transport 保持一致。
- stdio 稳定性：子进程在 EOF 前未输出换行时，`stdout` / `stderr` 的残留字节仍会被完整转发，避免丢最后一条 JSONL 或诊断信息。
- cwd 语义：hostd 在 spawn 子进程时显式设置 `current_dir`，子进程实际工作目录可被验证。
- 失败模式：非零退出码和 `stderr` 输出会被保留，供上层连接状态机映射为可见错误。
- 主动停止：hostd 关闭 stdin 并终止长生命周期子进程，保证不会留下孤儿 `app-server`。

对应测试位置：

- `engine/crates/island-hostd/src/lib.rs`

对 macOS / Linux 的含义：

- 上述验证全部基于 Unix 进程模型和 `/bin/sh` / `/bin/pwd` 等基础命令，在 macOS 与 Linux 都可执行。
- 当前还没有覆盖真正的 `codex app-server` 握手，也没有覆盖 hostd 重启退避、日志轮转、环境变量白名单等更高层行为。

后续建议：

- 用真实 `codex app-server --listen stdio://` 增加一个可选集成测试，验证初始化握手和 JSONL framing。
- 将这套 supervisor 抽成 hostd 正式 runtime，统一给 macOS shell、未来 Android shell 和 host daemon 复用。
- 在 hostd 实现中补充 restart policy、stderr ring buffer 与显式 health probe。
