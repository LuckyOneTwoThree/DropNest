<p align="center">
  <img src="logo.png" width="128" alt="DropNest">
</p>

<h1 align="center">DropNest 🪺</h1>

<p align="center">
  把 MacBook 的刘海变成你的「第二桌面」。<br/>
  文件暂存 · 悬浮巢群 · 剪贴板历史 · 媒体控制 · 系统 HUD —— 一切尽在刘海上方。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.0-FA7343" alt="Swift">
  <img src="https://img.shields.io/badge/version-1.0-green" alt="Version">
  <a href="https://github.com/LuckyOneTwoThree/DropNest/actions"><img src="https://github.com/LuckyOneTwoThree/DropNest/actions/workflows/build.yml/badge.svg" alt="Build"></a>
</p>

> ⚠️ **许可证**：本项目派生自 [boring.notch](https://github.com/TheBoredTeam/boring.notch)（GPL-3.0）。依据 GPL「衍生作品」条款，DropNest 同样以 **GPL-3.0** 发布，必须保留原许可证与版权信息。详见 [`LICENSE`](LICENSE) 与 [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES)。

---

## 核心功能

### 🪺 悬浮暂存巢群（Floating Nest）

把文件暂存从刘海延伸到整个桌面。每个集合都可以独立展开为悬浮巢，拖拽、收纳、流转一气呵成。

- **空巢胚落点**：拖拽文件时，鼠标附近自动浮现一个紧凑胶囊式落点指示器，松手即孵化为正式巢 —— 像在桌面上「种」一个文件巢。
- **摇晃召唤**：拖拽过程中横向摇晃鼠标，指针附近瞬间召唤一个空巢胚。纯指针驱动，无需键盘快捷键。
- **集合巢群**：批量拖入的文件自动成组，每个集合可独立展开为桌面悬浮巢，位置记忆、随用随调。
- **三层手势分离**：
  - **拖标题栏** → 移动窗口位置
  - **拖空白区** → 整体拖出全部文件（Finder 标准复制/移动语义）
  - **拖单个条目** → 只拖出该文件
- **一键流转**：全部集合一键展开为桌面巢群，或一键收回刘海，集合数据始终保留在文件架中。

### 📦 文件架（Shelf）

刘海里的悬浮收纳区，拖入即收，随时取用。

- **拖入即收**：文件/文件夹/文本/链接拖到刘海区域自动展开收纳。
- **安全书签持久化**：使用 security-scoped bookmark，重启后文件引用不丢失。
- **书签自动重解析**：缓存带 30s TTL，文件改名/移动后自动重新解析，不会再显示过期路径。
- **集合管理**：多个文件可编组为集合，集合卡片显示数量角标，支持就地展开、解散、删除。
- **批量操作流畅**：批量删除、清空集合的文件 IO 全部后台执行，UI 不卡顿；批量移除只触发一次界面刷新。
- **复制 vs 移动**：默认拖出为复制（保留原文件）；可在设置中关闭以切换为移动语义。
- **丰富右键菜单**：打开 / 快速查看 / 访达中显示 / 分享 / 复制 / 重命名 / 移除。
- **图片处理**：移除背景（抠图）/ 转换图片格式 / 创建 PDF。
- **文件夹操作**：右键直接压缩为 zip。

### 📋 剪贴板历史（Clipboard）

刘海里的剪贴板管理器，记录每一次复制，随时回贴。

- **多类型 payload**：同一次复制中的文本、RTF、HTML、图片、文件 URL 全部保存，回贴时行为与原始一致。
- **全局快速面板**：按 `⌃⌥V` 在鼠标位置唤出快速面板，输入过滤、方向键选择、回车回贴，全程不离开键盘。
- **可选自动粘贴**：回贴后自动注入 `⌘V` 到当前应用（需辅助功能权限）。
- **隐私红线**：自动识别密码管理器的一次性内容、文件承诺类型，可配置忽略应用列表。
- **容量与时效**：可设置最大条目数、保留天数、是否保存图片/文件、最大条目体积。
- **过期自动清理**：后台每 10 分钟扫描过期条目，长期运行不积累垃圾。
- **小体积优化**：RTF/HTML 小于 4KB 时内联存储，避免为格式化文本产生大量碎片 blob 文件。

### 🎵 媒体条（Now Playing）

刘海两侧展开，显示专辑封面与动态频谱。

- 支持任意播放器（Apple Music、Spotify、网页播放器等），通过系统级媒体接口获取状态。
- 暂停后自动收起为细条，不遮挡屏幕内容。
- 智能标签页切换：根据最近活动（文件暂存 / 剪贴板复制）自动切换默认标签页。

### 🎛️ 系统 HUD 替换

用刘海 HUD 替代系统原生音量/亮度/键盘背光指示器。

- **三类独立开关**：音量、屏幕亮度、键盘背光各自独立控制，可混用「刘海 HUD + 原生 bezel」。
- **多种显示样式**：折叠态内联 HUD（刘海两侧）/ 展开态可拖动进度条 / 刘海下方进度条。
- **Option 键增强**：按住 Option + 媒体键可自定义行为（打开设置 / 显示 HUD / 无操作）。
- **CGEvent Tap 拦截**：精准拦截媒体键事件，抑制系统原生 bezel，需辅助功能权限（运行时授予）。
- **Tap 自恢复**：系统在回调超时时会静默禁用 tap，DropNest 检测后立即重新启用，并每 30s 健康检查一次——长时间运行不会出现「音量键 HUD 突然失效需重启」。
- **音频设备切换跟随**：切换默认输出设备（耳机/音箱/蓝牙）后自动重新注册监听，音量调节与 HUD 始终跟随当前设备。
- **事件保序**：异步处理路径已串行化，连续快速按键不会乱序执行。

### 🔋 电池指示

刘海内的电量条，颜色随状态变化。

- 低电量红色 / 低功耗黄色 / 充电绿色 / 常态白色。
- 可显示电量百分比、充电/插电图标。
- 低电量通知（20% 阈值，一次性触发）。

---

## 交互方式

| 操作 | 效果 |
|------|------|
| 鼠标悬停刘海 | 自动展开面板 |
| 触控板双指开合 | 控制面板展开 / 收起 |
| 拖文件到刘海 | 展开文件架并收纳 |
| 拖拽中摇晃鼠标 | 召唤空巢胚到指针附近 |
| `⌃⌥V` | 唤起剪贴板快速面板 |
| 媒体键 | 音量/亮度/键盘背光调节 + HUD |
| `Esc` | 关闭悬浮巢 / 快速面板 |

所有交互的感应区域、灵敏度、动画时长均可在设置中微调。

---

## 架构亮点

### XPC Helper 架构

主 App 保持沙盒化，通过独立 XPC Helper（非沙盒）调用需要特权的能力：

- **屏幕亮度**：DisplayServices + IOKit 私有 API
- **键盘背光**：CoreBrightness 私有框架（动态加载 `KeyboardBrightnessClient`）
- **辅助功能授权**：XPC 侧检查并请求辅助功能权限

XPC 通信使用 `withCheckedContinuation` 包装为 async/await，带错误处理避免永久挂起。

### 性能与稳定性

DropNest 经过两轮深度代码审查与优化，长期运行稳定：

- **主线程零文件 IO**：所有 FileManager 操作（删除集合/清空文件架/移除条目/书签解析/剪贴板图片入库）均在后台线程执行，拖拽与滚动不卡顿。
- **书签解析缓存**：`ShelfItemResolutionCache` 带 30s TTL 与 NSLock 保护，避免 `displayName`/`icon`/`identityKey` 在主线程反复做书签解析与磁盘 I/O。
- **缩略图 NSCache**：100 条 / 256MB 上限，按文件 mtime 生成 key，文件修改后自动重建；`clearCache(for:)` 按路径前缀精确匹配。
- **媒体键健壮性**：CGEvent tap 超时自动恢复 + 30s 健康检查 + 事件串行化，避免「长时间运行后音量键 HUD 失效」。
- **音频设备切换**：VolumeManager 监听默认输出设备变更，自动注销旧监听、在新设备上重新注册。
- **剪贴板后台化**：图片 TIFF→PNG 转换、SHA256、blob 写盘全部后台执行；过期条目每 10 分钟自动清理。
- **严格并发**：`SWIFT_STRICT_CONCURRENCY = targeted`，7 个 UI 状态类统一 `@MainActor` 隔离，模型层去 MainActor 化以支持后台批量编解码。

### 窗口体系

- 基于 [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) 创建贴合刘海形状的无边框窗口，跨 Space 显示。
- 悬浮巢使用独立 NSPanel 体系，与刘海窗口完全隔离，不进 NotchSpaceManager。
- 多显示器支持：自动检测并适配每个屏幕的刘海位置。

### 安全与权限

| 能力 | 机制 | 权限需求 |
|------|------|---------|
| 文件暂存 | security-scoped bookmark | 沙盒内，无额外权限 |
| 音量读写 | CoreAudio | 沙盒内，无额外权限 |
| 电池监听 | IOKit.ps | 沙盒内，无额外权限 |
| 媒体键拦截 | CGEvent Tap | 辅助功能权限（运行时授予） |
| 屏幕亮度 | XPC Helper | 无额外权限（XPC 侧调用） |
| 剪贴板热键 | Carbon RegisterEventHotKey | 无额外权限 |
| 自动粘贴 | CGEvent 注入 | 辅助功能权限（可选） |

> DropNest 不需要「完全磁盘访问」等高危权限。文件访问通过安全书签，系统 HUD 通过辅助功能权限（运行时按需授予）。

---

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | macOS 14 Sonoma 或更高 |
| 芯片 | Apple Silicon 或 Intel Mac |
| 构建工具 | Xcode 15+（需支持 Swift 严格并发） |
| 运行形态 | 沙盒化 App，无需关闭 SIP |

---

## 安装

### 方式一：下载安装包

前往 [Releases](https://github.com/LuckyOneTwoThree/DropNest/releases) 下载最新 `.dmg`，挂载后把 `DropNest.app` 拖入 `应用程序` 即可。每次打 `v*` tag 会自动触发 GitHub Actions 构建并发布。

### 方式二：从源码构建

```bash
# 克隆仓库
git clone https://github.com/LuckyOneTwoThree/DropNest.git
cd DropNest

# 用 Xcode 打开并构建
open DropNest.xcodeproj
# 在 Xcode 中按 ⌘R 运行，或 ⌘B 构建
```

构建产物 `DropNest.app` 可在 Xcode 的 `Products` 组中右键 → **Show in Finder** 取出。

### 命令行构建

```bash
xcodebuild \
  -project DropNest.xcodeproj \
  -scheme DropNest \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

> 首次请先通过 Xcode 打开工程以生成本地 Scheme。

### 构建 DMG 安装包

```bash
cd Configuration/dmg
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 dmgbuild_settings.py
```

---

## 使用指南

### 首次启动

1. 从 `应用程序` 启动 **DropNest**（首次可能被 macOS 拦截，右键 → 打开）。
2. 建议在设置中开启「登录时启动」。
3. 如需系统 HUD 替换，在设置中开启后按提示授予辅助功能权限。

### 文件暂存

- **拖入**：把文件拖到屏幕顶部刘海区域，面板自动展开并收纳。
- **批量成组**：一次拖入多个文件自动编为集合。
- **悬浮巢**：点击集合卡片右键 →「以悬浮巢展示」，或点击顶栏巢群按钮一键展开全部。
- **取出**：从文件架拖出 = 复制（默认）；从悬浮巢拖空白区 = 整体拖出全部。
- **持久化**：收纳的文件引用由安全书签记录，重启后依然可用。

### 剪贴板历史

- 在刘海面板切换到「剪贴板」标签页浏览历史。
- 按 `⌃⌥V` 在任意位置唤出快速面板，输入过滤、方向键选择、回车回贴。
- 在设置中配置忽略应用、最大条目数、保留天数等。

### 系统 HUD

- 在设置 → HUD 中开启主开关，按需勾选音量/亮度/键盘背光。
- 按媒体键时刘海显示 HUD，替代系统原生 bezel。
- 不需要的类别可关闭，按键透传给系统。

### 设置

设置窗口包含 8 个分页：

| 分页 | 内容 |
|------|------|
| 通用 | 登录启动、菜单栏图标、多显示器、屏幕录制隐藏 |
| 外观 | 刘海样式、阴影、圆角、强调色 |
| 媒体 | 专辑封面、频谱、展开等待时长 |
| 文件架 | 容量、复制/移动语义、自动移除、拖拽检测区域 |
| 剪贴板 | 开关、容量、时效、忽略应用、热键、自动粘贴 |
| 电池 | 电量条、百分比、充电图标、低电量通知 |
| HUD | 主开关、音量/亮度/背光独立开关、显示样式、Option 键行为 |
| 关于 | 版本与许可证 |

---

## 目录结构

```
DropNest/
├── App/                              # 主 App 源码
│   ├── DropNestApp.swift             # @main 入口 + AppDelegate
│   ├── NotchViewCoordinator.swift    # 刘海视图协调器
│   ├── DropNest.entitlements         # 沙盒权限声明
│   ├── components/
│   │   ├── Notch/                    # 刘海窗口、形状、频谱、头部
│   │   ├── Shelf/                    # 文件架 + 悬浮巢群
│   │   │   ├── Models/               # ShelfItem、Bookmark
│   │   │   ├── Services/             # 拖放/持久化/缩略图/图片处理
│   │   │   ├── ViewModels/           # 状态/选择/加载
│   │   │   ├── Views/                # ShelfView、FloatingNestPanel、NestGroupCardView
│   │   │   └── FloatingNestManager.swift
│   │   ├── Clipboard/                # 剪贴板历史（Models/Services/ViewModels/Views）
│   │   ├── HUD/                      # 系统 HUD（展开态/折叠态/事件指示器）
│   │   ├── Battery/                  # 电池指示视图
│   │   └── Settings/                 # 8 分页设置窗口
│   ├── managers/                     # Volume/Brightness/Battery/Music/NotchSpace
│   ├── MediaControllers/             # NowPlaying 抽象层
│   ├── observers/                    # DragDetector/MediaKeyInterceptor/ShakeGestureDetector
│   ├── XPCHelperClient/              # XPC 客户端（async/await 封装）
│   ├── models/                       # Constants、NotchViewModel、BatteryStatusViewModel
│   └── sizing/ extensions/ helpers/  # 工具
├── DropNestXPCHelper/                # XPC Helper target（非沙盒）
│   ├── DropNestXPCHelper.swift       # 亮度/背光/辅助功能授权
│   └── DropNestXPCHelper.entitlements
├── mediaremote-adapter/              # 媒体监听子模块
├── Configuration/dmg/                # DMG 打包配置
├── DropNestTests/                    # 单元测试
└── DropNest.xcodeproj/
```

---

## 技术栈

- **语言**：Swift 5（严格并发 `SWIFT_STRICT_CONCURRENCY = targeted`）+ SwiftUI
- **窗口**：[SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)（贴合刘海的原生窗口）
- **媒体**：[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（系统级 Now Playing）
- **偏好**：[Defaults](https://github.com/sindresorhus/Defaults)
- **登录启动**：[LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
- **语法**：[swift-syntax](https://github.com/swiftlang/swift-syntax)
- **特权能力**：XPC Helper 架构（屏幕亮度/键盘背光/辅助功能）
- **媒体键拦截**：CGEvent Tap
- **剪贴板热键**：Carbon RegisterEventHotKey
- **电池监听**：IOKit.ps
- **音量控制**：CoreAudio

---

## 常见问题

**Q：启动时提示「无法验证开发者」？**
A：右键 App →「打开」，在弹窗中确认；或在「系统设置 → 隐私与安全性」中点击「仍要打开」。自行构建的版本不会出现此问题。

**Q：系统 HUD 不生效？**
A：HUD 替换需要辅助功能权限。在设置 → HUD 中开启后，系统会提示授权，前往「系统设置 → 隐私与安全性 → 辅助功能」中允许 DropNest。

**Q：悬浮巢摇晃召唤不灵敏？**
A：在设置中调整「摇晃灵敏度」和「最小振幅」。灵敏度越高所需振幅越小。

**Q：剪贴板快速面板不出现？**
A：确认设置 → 剪贴板中已开启热键。`⌃⌥V` 可能与其他应用冲突，检查系统快捷键设置。

**Q：Shelf 里的文件重启后打不开了？**
A：极少数情况下安全书签可能失效（文件被移动/删除）。重新拖入该文件即可。

**Q：长时间运行后音量键 HUD 不出现？**
A：DropNest 已实现 CGEvent tap 超时自恢复与每 30s 健康检查，正常情况下不会出现此问题。如仍出现，请确认辅助功能权限未被撤销，并检查是否有其他应用抢占媒体键拦截。

**Q：切换耳机/音箱后音量调节异常？**
A：DropNest 会自动跟随默认输出设备重新注册监听。如仍异常，重启 App 即可恢复。

---

## 卸载

1. 退出 DropNest（菜单栏图标 → 退出）。
2. 将 `应用程序/DropNest.app` 拖入废纸篓。
3. （可选）删除偏好文件：`~/Library/Containers/com.dropnest.app/`。
4. 若开启了登录启动，在「系统设置 → 通用 → 登录项」中移除 DropNest。
5. 若授予了辅助功能权限，在「系统设置 → 隐私与安全性 → 辅助功能」中移除。

---

## 贡献

欢迎参与 DropNest 的开发与完善！

- 📘 **贡献指南**：[CONTRIBUTING.md](CONTRIBUTING.md)
- 🐛 **报告问题**：[Bug Report 模板](.github/ISSUE_TEMPLATE/bug_report.yml)
- 💡 **功能建议**：[Feature Request 模板](.github/ISSUE_TEMPLATE/feature_request.yml)
- 🤝 **行为准则**：[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 🔒 **安全漏洞**：请按 [SECURITY.md](SECURITY.md) 私报告知

---

## 许可证

本项目以 **GNU General Public License v3.0（GPL-3.0）** 发布。

- 完整许可证文本见 [`LICENSE`](LICENSE)。
- 第三方依赖许可证汇总见 [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES)。
- 因本项目派生于 GPL-3.0 的 boring.notch，**你必须在此许可证下使用、修改与分发本软件**；任何再分发都需附带对应源码。

---

## 致谢

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) —— 刘海窗口的完整思路与实现基础。
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) —— 系统级媒体状态获取。
- [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) —— 贴合刘海的原生窗口方案。
- [sindresorhus/Defaults](https://github.com/sindresorhus/Defaults) · [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) —— 偏好存储与登录启动。
- [swiftlang/swift-syntax](https://github.com/swiftlang/swift-syntax) —— Swift 语法支持。
