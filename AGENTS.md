# Repository Guidelines

## 沟通要求
本仓库的代理、维护者与协作者在与用户沟通时统一使用中文。提交说明、评审意见、执行反馈和补充说明优先使用中文；引用命令、路径、类型名和代码标识符时保留原文。

## 项目结构与模块划分
`CodexIsland/` 是主应用目录。`App/` 放应用入口与窗口生命周期，`Core/` 放状态、几何与设置等核心逻辑，`Events/` 处理事件监听，`Models/` 定义数据模型，`Services/` 按能力拆分为 `Chat/`、`Hooks/`、`Session/`、`Tmux/`、`Update/`、`Window/` 等模块。界面代码位于 `UI/Views` 和 `UI/Components`，窗口封装在 `UI/Window`。资源文件在 `Assets.xcassets/`、`Resources/` 与 `Info.plist`，发布脚本在 `scripts/`。

## 构建、测试与开发命令
日常开发可直接用 Xcode，也可执行：

```bash
xcodebuild -scheme CodexIsland -configuration Debug build
```

发布构建使用 `./scripts/build.sh`，产物输出到 `build/export/Codex Island.app`。首次配置 Sparkle 密钥使用 `./scripts/generate-keys.sh`。打包、签名、公证、生成 appcast 以及可选 GitHub Release 使用 `./scripts/create-release.sh`。

当前仓库未提交独立测试 Target；如果补充测试，优先使用：

```bash
xcodebuild test -scheme CodexIsland -destination 'platform=macOS'
```

## 代码风格与命名规范
遵循现有 Swift 风格：4 空格缩进，类型名使用 `PascalCase`，属性和方法使用 `camelCase`。扩展文件保持聚焦，命名参考 `Ext+NSScreen.swift`。较长文件可用 `// MARK:` 分段，但不要滥用。UI 状态尽量留在 SwiftUI 视图模型或协调器中，进程、Socket、tmux、文件系统等平台能力集中放在 `Services/`。

## 测试要求
由于当前缺少自动化测试，所有行为变更都需要手工验证。至少覆盖 hooks 安装、会话识别、notch 展开/收起、权限审批流程，以及涉及多屏时的屏幕切换行为。新增测试文件建议使用 `XxxTests.swift` 命名，例如 `SessionStoreTests.swift`。

## 提交与 Pull Request 要求
提交信息沿用现有仓库风格，使用简短、明确的祈使句，例如 `Reorganize settings menu items`。一次提交只解决一个问题。PR 需要说明用户可见影响，关联 issue；若改动 notch、菜单或窗口表现，附截图或短录屏。涉及 Sparkle、签名、hooks、版本号的改动要单独说明风险和发布影响。

代理在完成一个独立功能改动后，默认需要执行一次构建验证，优先使用：

```bash
xcodebuild -scheme CodexIsland -configuration Debug build
```

构建通过后再进行 `git commit` 和 `git push`。如果构建失败，需先说明失败原因并继续修复，除非用户明确要求跳过构建或仅提交未通过构建的中间状态。

## 安全与配置提示
禁止提交 `.sparkle-keys/`、公证凭据或本地 keychain 配置。修改 `Services/Hooks/` 或 `Resources/codex-island-state.py` 时要格外谨慎，这些内容会直接影响用户本地 Codex hooks 的安装与运行。
