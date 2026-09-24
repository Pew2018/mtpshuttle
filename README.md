# MTP Shuttle

MTP Shuttle is a native SwiftUI macOS application for browsing and transferring files between a Mac and Android/MTP devices over USB.

MTP Shuttle is developed in the native SwiftUI target of this repository. The original Electron/React OpenMTP implementation is retained in the repository for compatibility and reference, but the current preview application is built from `native/OpenMTPNative`.

## 中文说明

MTP Shuttle 是一款基于 SwiftUI 和 AppKit 开发的 macOS 原生 Android/MTP 文件传输工具，用于通过 USB 在 Mac 与 Android 设备之间浏览和传输文件。

当前预览版重点是提供更贴近 macOS 系统体验的原生界面，同时复用 OpenMTP 项目中的 Kalam MTP 后端。

### 当前功能

- 连接 Android 或其他 MTP 设备
- 浏览 Android 内部存储和其他存储空间
- 浏览 Mac 本地文件
- Mac Finder 文件拖入 Android 文件栏
- 应用内双栏拖拽传输
- 文件复制、剪切、粘贴和删除
- 新建文件夹
- 文件列表视图和网格视图
- 面包屑路径导航
- 前进、后退和刷新
- 多选文件
- 传输进度、任务详情和取消当前任务
- 文件冲突处理：覆盖、重命名或取消
- 选中文件后使用空格键打开 macOS Quick Look
- Quick Look 预览窗口跟随当前文件选择变化
- 窗口位置记忆
- 关闭窗口后重新点击 Dock 图标自动恢复主窗口
- Android-only 单栏模式
- 可配置的双栏拖拽复制/移动行为
- 本地调试日志查看和复制

### 当前限制

这是一个原生 SwiftUI 预览版，以下功能仍在开发或规划中：

- Android 文件拖出到系统 Finder 的真实文件复制
- Android 文件重命名
- Copy to Queue 传输队列
- Legacy MTP 模式
- Intel Mac 架构
- 自动更新和正式公证发布

### 系统要求

- macOS 13 Ventura 或更高版本
- Apple Silicon Mac
- Android 设备需要开启 USB 文件传输/MTP 模式
- 当前预览版只提供 arm64 构建

### 下载

当前版本：0.1.1（GitHub Actions arm64 构建产物；未创建 GitHub Release）

ARM64 GitHub Actions 构建产物：

- [最新 ARM64 Artifact](https://github.com/Pew2018/swiftmtp/actions)

预览版可能尚未经过所有 Android 设备、文件类型和大文件场景的完整验证。使用前请保留重要数据的备份。

### 构建流程

Native SwiftUI 构建由 GitHub Actions 完成：

1. 在 Apple Silicon runner 上构建 ARM64 Kalam 动态库
2. 构建 MTP Shuttle Swift Package
3. 运行 Swift 单元测试
4. 手工组装 MTP Shuttle.app
5. 根据 macOS 版本准备 standard 或 seg5 Kalam 动态库
6. 验证动态库依赖、App bundle、代码签名和 ZIP 结构
7. 上传可下载的 ARM64 ZIP

Native 构建不会编译或打包仓库中的 Electron/React 前端、Node 依赖或原 Electron 资源。最终 App 只包含 MTP Shuttle 可执行文件、Info.plist、Kalam 动态库和运行所需的 libusb 动态库。

本地 Native 工程位置：

~~~text
native/OpenMTPNative/
~~~

### 项目结构

~~~text
native/OpenMTPNative/          SwiftUI 原生客户端
native/OpenMTPNative/Sources/  SwiftUI、AppKit 和 MTP 调用代码
native/OpenMTPNative/Tests/    Native 单元测试
ffi/kalam/native/              Kalam Go MTP 后端
.github/workflows/              GitHub Actions 构建流程
app/                            原始 Electron/React 客户端
~~~

### 开发原则

- 已经通过真实设备验证的功能应保持稳定
- 新功能应从 master 分支创建独立分支
- 不为了重构而改动已验证的拖拽传输逻辑
- CI 构建成功不等于真实设备交互测试成功
- 每次功能修改都应完成 ARM64 构建并提供可下载 App

### 许可证

本项目基于 MIT License 发布。仓库中保留的原 OpenMTP 代码及其版权声明应继续遵守原项目许可证和版权要求。

原项目：

- [ganeshrvel/openmtp](https://github.com/ganeshrvel/openmtp)

---

## English

MTP Shuttle is a native SwiftUI macOS application for browsing and transferring files between a Mac and Android/MTP devices over USB.

The current preview application is built from `native/OpenMTPNative`. The original Electron/React OpenMTP implementation remains in this repository for compatibility and reference, but it is not included in the Native SwiftUI application bundle.

### Current features

- Connect to Android and other MTP devices
- Browse internal storage and other device storage volumes
- Browse local Mac files
- Drag files from Finder into the Android pane
- Transfer files by dragging between the two panes
- Copy, cut, paste, and delete files
- Create folders
- List and grid views
- Breadcrumb path navigation
- Back, forward, and refresh controls
- Multiple selection
- Transfer progress, task details, and cancellation
- Conflict handling with overwrite, rename, or cancel options
- Open macOS Quick Look with the Space key
- Keep Quick Look synchronized with the current file selection
- Restore the main window position
- Reopen the main window when clicking the Dock icon after closing it
- Android-only single-pane mode
- Configurable copy/move behavior for cross-pane drag and drop
- Local debug log viewing and copying

### Current limitations

MTP Shuttle is currently a native SwiftUI preview. The following features are not implemented or are still planned:

- Renaming Android files
- Copy to Queue transfer queue
- Legacy MTP mode
- Intel Mac builds
- Automatic updates and production notarized distribution

### Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac
- USB file transfer/MTP mode enabled on the Android device
- The current preview is arm64-only

### Downloads

Current version: 0.1.1 (GitHub Actions arm64 artifact; no GitHub Release has been published)

ARM64 GitHub Actions builds:

- [Latest ARM64 Artifacts](https://github.com/Pew2018/swiftmtp/actions)

The preview has not yet been exhaustively tested with every Android device, file type, or large-file scenario. Keep backups of important data.

### Build pipeline

The Native SwiftUI build runs on GitHub Actions:

1. Build the ARM64 Kalam dynamic library on an Apple Silicon runner
2. Build the MTP Shuttle Swift Package
3. Run Swift unit tests
4. Assemble MTP Shuttle.app explicitly
5. Include the standard or seg5 Kalam libraries required by the macOS version
6. Verify dynamic-library dependencies, the App bundle, code signing, and ZIP structure
7. Upload a downloadable ARM64 ZIP

The Native build does not compile or package the Electron/React frontend, Node dependencies, or original Electron resources. The final App contains only the MTP Shuttle executable, Info.plist, Kalam dynamic libraries, and the required libusb libraries.

Native project location:

~~~text
native/OpenMTPNative/
~~~

### Repository structure

~~~text
native/OpenMTPNative/          Native SwiftUI client
native/OpenMTPNative/Sources/  SwiftUI, AppKit, and MTP bridge code
native/OpenMTPNative/Tests/    Native unit tests
ffi/kalam/native/              Kalam Go MTP backend
.github/workflows/              GitHub Actions workflows
app/                            Original Electron/React client
~~~

### Development principles

- Preserve features that have been verified on real devices
- Create a new feature branch from master for new work
- Do not refactor verified drag-and-drop transfer code without a demonstrated reason
- A passing CI build is not the same as successful physical-device testing
- Every functional change should finish with a downloadable ARM64 App build

### License

This project is released under the MIT License. The original OpenMTP code and copyright notices retained in this repository remain subject to the original project’s license and attribution requirements.

Original project:

- [ganeshrvel/openmtp](https://github.com/ganeshrvel/openmtp)
