# 贡献指南 (Contributing Guide)

感谢你对 **DropNest** 感兴趣并愿意参与贡献！🪺

本指南将帮助你快速搭建开发环境、了解项目约定，并顺利提交你的改动。

> 在开始之前，请先阅读我们的 [行为准则 (Code of Conduct)](CODE_OF_CONDUCT.md)。参与本项目即表示你同意遵守其中的条款。

---

## 目录

- [如何贡献](#如何贡献)
- [开发环境](#开发环境)
- [获取源码](#获取源码)
- [构建与运行](#构建与运行)
- [项目结构速览](#项目结构速览)
- [代码规范](#代码规范)
- [提交信息规范](#提交信息规范)
- [分支与 Pull Request 流程](#分支与-pull-request-流程)
- [报告问题](#报告问题)
- [许可证说明](#许可证说明)

---

## 如何贡献

DropNest 欢迎以下几类贡献：

- 🐛 **报告 Bug**：在使用中发现异常，请通过 [Issue 模板](.github/ISSUE_TEMPLATE/bug_report.yml) 提交。
- 💡 **提出功能建议**：欢迎在 [功能建议模板](.github/ISSUE_TEMPLATE/feature_request.yml) 中描述你的想法。
- 🔧 **提交代码**：修复 Bug、实现功能、优化性能、改进文档。
- 📝 **完善文档**：修正错别字、补充使用说明、翻译。

> 💡 **小建议**：在动手写代码前，建议先在 Issue 或 Discussion 中讨论你的方案，尤其是较大的功能改动，避免重复劳动或方向偏差。

---

## 开发环境

| 项目 | 要求 |
| --- | --- |
| 操作系统 | macOS 14 Sonoma 或更高 |
| 开发工具 | Xcode 15+（需支持 Swift 严格并发与 SPM） |
| 命令行工具 | Xcode Command Line Tools（`xcode-select --install`） |
| 芯片 | Apple Silicon 或 Intel Mac 均可 |
| 构建方式 | Xcode 图形界面或 `xcodebuild` 命令行 |

> 仓库目前**未包含共享 Scheme**。首次请先通过 Xcode 打开 `DropNest.xcodeproj` 以生成本地 Scheme；之后也可用 `-target DropNest` 直接构建。

---

## 获取源码

```bash
# Fork 本仓库到你的 GitHub 账号后，克隆你的 Fork
git clone https://github.com/<你的用户名>/DropNest.git
cd DropNest

# 添加上游仓库（便于同步最新改动）
git remote add upstream https://github.com/LuckyOneTwoThree/DropNest.git

# 拉取最新代码
git fetch upstream
git merge upstream/main
```

---

## 构建与运行

### 用 Xcode（推荐）

1. 双击打开 `DropNest.xcodeproj`。
2. 顶部工具栏选择 **DropNest** 作为 Target / Scheme，运行目标选 `My Mac`。
3. 按 **⌘R** 运行；或 **⌘B** 仅构建。
4. 首次构建时 Xcode 会自动解析 SPM 依赖（见 README「技术栈与依赖」）。

### 用命令行

```bash
xcodebuild \
  -project DropNest.xcodeproj \
  -scheme DropNest \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

---

## 项目结构速览

源码主目录为 `App/`：

```
App/
├── DropNestApp.swift          # 应用入口 + AppDelegate
├── ContentView.swift          # 刘海整体布局
├── NotchViewCoordinator.swift # 刘海视图协调器
├── components/
│   ├── Notch/                 # 刘海窗口、形状、头部、频谱
│   ├── Shelf/                 # 文件架 + 悬浮暂存巢群（Models/Services/ViewModels/Views + FloatingNestManager）
│   ├── Clipboard/             # 剪贴板历史（Models/Services/ViewModels/Views）
│   ├── HUD/                   # 系统 HUD（InlineHUD/OpenNotchHUD/SystemEventIndicator）
│   ├── Battery/               # 电池指示视图
│   └── Settings/              # 8 分页设置界面
├── managers/                  # Volume/Brightness/Battery/Music/NotchSpace
├── MediaControllers/          # NowPlayingController（mediaremote-adapter 封装）
├── observers/                 # DragDetector / MediaKeyInterceptor / ShakeGestureDetector
├── XPCHelperClient/           # XPC 客户端（async/await 封装）
├── models/                    # Constants、NotchViewModel、BatteryStatusViewModel
├── sizing/ extensions/ helpers/ enums/
```

> 详细的目录说明见 [README.md](README.md#目录结构)。

---

## 代码规范

为保持代码库可读性与一致性，请遵循以下约定：

### Swift 风格

- **命名**：类型用 `UpperCamelCase`，函数 / 变量 / 属性用 `lowerCamelCase`；布尔属性以 `is` / `has` / `should` 等开头（如 `isExpanded`）。
- **并发**：项目启用了 `SWIFT_STRICT_CONCURRENCY = targeted`，新增代码请使用 `@MainActor`、async/await 与 `Sendable`，避免遗留的回调式并发。
- **文件组织**：按现有模块划分（`Models` / `Services` / `ViewModels` / `Views`），新功能尽量放在对应子目录下。
- **可选工具**：如本地已安装 [SwiftLint](https://github.com/realm/SwiftLint)，提交前请运行它；仓库暂未强制集成 CI 检查，但保持风格统一有助于 Review。

### 视图与架构

- UI 优先使用 **SwiftUI**；涉及刘海窗口、拖拽检测等原生能力时使用 AppKit / SkyLight 桥接，并集中在 `components/Notch` 与 `observers`。
- 状态管理沿用现有 `ObservableObject` / `@Published` + `Defaults` 偏好存储模式，新增设置项请在 `models/Constants.swift` 与 `components/Settings` 中补齐。

### 注释与文档

- 公共类型、关键方法建议用英文或中文写简短注释，说明「为什么」而非「做什么」。
- 涉及 macOS 私有 API / 沙盒权限的改动，请在 PR 描述中说明影响。

---

## 提交信息规范

本项目采用 **[Conventional Commits](https://www.conventionalcommits.org/)** 风格，便于自动生成变更日志与审阅：

```
<type>(<scope>): <subject>
```

常用 `type`：

| 类型 | 含义 |
| --- | --- |
| `feat` | 新功能 |
| `fix` | 修复 Bug |
| `docs` | 仅文档改动 |
| `style` | 不影响逻辑的格式调整（空格、分号等） |
| `refactor` | 重构（非新功能也非修 Bug） |
| `perf` | 性能优化 |
| `test` | 增加或修改测试 |
| `chore` | 构建流程、依赖、工具等杂项 |

示例：

```
feat(clipboard): 增加剪贴板历史搜索过滤
fix(shelf): 修复重启后安全书签失效导致的文件打不开
docs: 补充 CONTRIBUTING 指南
```

> 如果一次提交包含多种改动，请尽量按主要意图归类； squash 合并前确保每个 commit 信息清晰。

---

## 分支与 Pull Request 流程

1. **基于最新 `main` 创建功能分支**：

   ```bash
   git checkout main
   git pull upstream main
   git checkout -b feat/clipboard-search   # 或 fix/shelf-bookmark
   ```

2. **保持分支与上游同步**（若 `main` 有更新）：

   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

3. **提交改动**并撰写清晰的提交信息（见上文规范）。

4. **推送分支**到你的 Fork：

   ```bash
   git push origin feat/clipboard-search
   ```

5. **在 GitHub 发起 Pull Request**，目标分支选 `LuckyOneTwoThree:main`，并：
   - 填写 PR 模板，说明「做了什么 / 为什么 / 如何测试」。
   - 关联相关 Issue（如 `Closes #123`）。
   - 附上必要的截图或录屏（UI 改动强烈建议）。

6. **Review 与合并**：维护者会进行 Code Review；可能需要你根据意见修改。合并方式通常为 **Squash and merge**，以保持 `main` 历史整洁。

---

## 报告问题

- 🐛 **Bug 报告**：请使用 [Bug Report 模板](.github/ISSUE_TEMPLATE/bug_report.yml)，尽量提供复现步骤、环境信息（macOS 版本、DropNest 版本、芯片类型）与日志。
- 💡 **功能建议**：请使用 [Feature Request 模板](.github/ISSUE_TEMPLATE/feature_request.yml)。
- 🔒 **安全问题**：请勿公开提 Issue，请按 [SECURITY.md](SECURITY.md) 中的方式私报告知。

---

## 许可证说明

DropNest 是 [boring.notch](https://github.com/TheBoredTeam/boring.notch) 的派生作品，依据 GPL-3.0 的「衍生作品」条款，**同样以 GPL-3.0 发布**。

- 你提交的贡献将默认在 **GPL-3.0** 下授权。
- 提交 PR 即表示你同意你的贡献在本许可证下被使用、修改与分发。
- 完整许可证文本见 [LICENSE](LICENSE)。

---

再次感谢你的贡献！每一个 Issue、PR 与建议都让 DropNest 更好 ❤️
