# DropNest 🪺

基于 boring.notch 深度裁剪的个人项目，只保留两个核心能力：

1. **文件拖放暂存（Shelf）** —— 把文件拖到 MacBook 刘海区域暂存，随时取用
2. **媒体播放状态监听** —— 刘海显示当前正在播放的曲目（封面 + 动态频谱）

> 已移除原版的花哨功能：日历/提醒事项、电池指示、摄像头镜像、系统 HUD 替换、下载指示器、
> 歌词/可视化器、自动更新、Onboarding 引导等。

## 功能特性

- **刘海媒体条**：播放音乐时，刘海两侧显示专辑封面和动态频谱，暂停后自动恢复细条
- **文件暂存（Shelf）**：
  - 拖文件到刘海自动展开并收入
  - 安全书签持久化，重启不丢失
  - 单项右键菜单：打开 / 用其他方式打开 / 在访达中显示 / 快速查看 / 分享 / 复制 / 重命名 / 移除
  - 图片操作：移除背景 / 转换图片 / 创建 PDF；文件夹可压缩
- **悬停/手势/拖拽**：悬停展开、双指手势开合、拖拽检测区域可调
- **中文界面**：设置页（通用 / 外观 / 媒体 / 文件架 / 关于）

## 系统要求

- macOS 14 Sonoma 或更高
- Apple Silicon 或 Intel Mac
- 构建需 Xcode 26+（Swift 6 严格并发）

## 构建与运行

```bash
./.workbuddy/build.sh
```

脚本会自动编译、部署到 `/Applications` 并启动。编译日志写入 `.workbuddy/build.log`。

### 手动构建

```bash
xcodebuild -project DropNest.xcodeproj -scheme DropNest -configuration Debug -destination 'platform=macOS' build
```

## 技术说明

- **媒体监听**：通过 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（Perl 脚本 + MediaRemoteAdapter.framework 子进程）流式获取系统级 Now Playing 状态，支持任何 App（Apple Music / Spotify / 浏览器等）
- **窗口体系**：无边框 SkyLight 窗口贴合刘海，多显示器支持
- **持久化**：Shelf 文件使用 security-scoped bookmark（`com.apple.security.files.bookmarks`）

## 目录结构

```
DropNest/（源码目录名）
├── DropNestApp.swift         # 入口，刘海窗口与拖拽检测管理
├── ContentView.swift         # 刘海布局（closed 媒体条 / open Shelf）
├── components/
│   ├── Notch/                # 刘海窗口、形状、头部、频谱
│   ├── Shelf/                # 文件暂存模块（模型/服务/视图模型/视图）
│   └── Settings/             # 设置界面
├── managers/                 # MusicManager（Now Playing 监听）等
├── MediaControllers/         # NowPlayingController（mediaremote-adapter 封装）
├── observers/                # DragDetector（拖拽检测）
└── sizing/                   # 刘海尺寸计算
```

## License

[MIT](LICENSE)（原项目为 MIT 许可，见 THIRD_PARTY_LICENSES）
