# MTP Shuttle

**MTP Shuttle 0.3.0** 是一款使用 SwiftUI 和 AppKit 构建的 macOS 原生应用，可通过 USB/MTP 在 Mac 与 Android 设备之间浏览和传输文件。项目复用 OpenMTP 的 Kalam MTP 后端；原 Electron/React 客户端仍保留在仓库中，但不包含在此原生应用内。

MTP Shuttle 是独立维护的 OpenMTP 衍生项目。感谢 [ganeshrvel/openmtp](https://github.com/ganeshrvel/openmtp) 及其贡献者提供的基础项目和 Kalam 后端。

[English](#english)

## 功能

- 浏览 Mac 本地文件、Android 内部共享存储和其他 MTP 存储卷
- 使用双窗格、列表/网格视图、路径面包屑、前进/后退与刷新导航
- 在窗格间拖拽文件和文件夹，也可从 Finder 拖入 Android 窗格
- 复制、剪切、粘贴、移动、删除和新建文件夹
- 处理同名项目冲突：覆盖、重命名或取消
- 显示传输进度、当前文件、速度和预计剩余时间，并支持取消
- Mac → Android 移动会回读 Android 文件并校验 SHA-256；验证失败时保留 Mac 原文件
- Android → Mac 移动先下载到暂存目录，下载成功后才删除 Android 源文件
- 使用 macOS Quick Look 预览 Mac 文件
- 收藏常用位置、Android-only 单栏模式和可配置的拖拽复制/移动行为
- 通过 macOS 文件承诺（file promise）将 Android 文件导出到 Finder

## 系统要求

- macOS 13 Ventura 或更新版本
- Apple Silicon Mac（arm64）
- Android 设备通过 USB 连接，并选择设备提供的文件传输/MTP 模式

## 下载与安装

当前原生应用版本：**0.3.0**。Apple Silicon DMG 由 GitHub Actions 构建：

- [查看 MTP Shuttle macOS 构建](https://github.com/Pew2018/mtpshuttle/actions/workflows/native-swiftui.yml)

在最新成功的工作流运行页面 Artifacts 区域下载 **MTP-Shuttle-0.3.0-macOS-arm64**，打开 DMG 并将 **MTP Shuttle.app** 拖入 **Applications**。Actions 构建产物保留 14 天；正式 GitHub Release 发布后，可从 Releases 页面获取长期下载链接。

当前构建使用 ad-hoc 签名，尚未经过 Apple Developer ID 公证。首次打开时，macOS 可能显示安全提示。

## 构建与验证

原生 macOS 应用由 .github/workflows/native-swiftui.yml 在 Apple Silicon GitHub Actions runner 上构建。工作流会：

1. 构建 Kalam 和 libusb ARM64 动态库
2. 运行 Go 测试和 Swift 单元测试
3. 构建并签名 MTP Shuttle.app
4. 验证应用包、动态库依赖和 DMG 内容
5. 上传 MTP-Shuttle-0.3.0-macOS-arm64.dmg 构建产物

CI 成功表示代码通过工作流中的构建与检查；真实 Android 设备、线缆、存储介质和大文件场景仍可能存在设备差异。

## 当前限制

- 目前仅提供 Apple Silicon（arm64）版本
- 尚未提供 Developer ID 签名、公证、自动更新或正式发布的长期下载
- 尚未实现 Android 文件重命名、传输队列和 Legacy MTP 模式
- MTP 设备的传输速度、支持的操作和文件信息可能因设备及固件而异

## 仓库结构

~~~text
native/OpenMTPNative/          SwiftUI / AppKit 原生客户端
native/OpenMTPNative/Sources/  应用界面、传输和 MTP 桥接代码
native/OpenMTPNative/Tests/    原生应用单元测试
ffi/kalam/native/              Kalam Go MTP 后端
.github/workflows/             GitHub Actions 构建流程
app/                           仓库保留的 Electron/React 客户端
~~~

原生应用 bundle 版本由 native/OpenMTPNative/Info.plist 管理。仓库根目录的 package.json 属于保留的 Electron/React 项目，不决定原生应用版本。

## 许可证

本项目基于 MIT License 发布。仓库中保留的 OpenMTP 上游代码及其版权声明仍受原有许可证约束。请查看 LICENSE 及相关源文件中的版权信息。

---

## English

**MTP Shuttle 0.3.0** is a native macOS application built with SwiftUI and AppKit. It browses and transfers files between a Mac and Android devices over USB/MTP. The project reuses the Kalam MTP backend from OpenMTP. The original Electron/React client remains in this repository but is not included in the native app.

MTP Shuttle is an independently maintained derivative of OpenMTP. Thanks to [ganeshrvel/openmtp](https://github.com/ganeshrvel/openmtp) and its contributors for the original project and Kalam backend.

## Features

- Browse local Mac files, Android shared internal storage, and other MTP volumes
- Use a dual-pane interface with list/grid views, breadcrumbs, back/forward, and refresh
- Drag files and folders between panes, or drop Finder items into the Android pane
- Copy, cut, paste, move, delete, and create folders
- Resolve name conflicts by overwriting, renaming, or cancelling
- View transfer progress, current file, speed, and estimated time; cancel active transfers
- Before a Mac → Android move deletes the Mac original, read the Android copy back and verify its SHA-256; keep the original if verification fails
- Stage Android → Mac downloads before deleting Android originals during a move
- Preview Mac files with macOS Quick Look
- Save favorite locations, use Android-only mode, and configure cross-pane drag copy/move behavior
- Export Android files to Finder through macOS file promises

## Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac (arm64)
- Connect an Android device over USB and select its File Transfer/MTP mode

## Download and install

Current native app version: **0.3.0**. The Apple Silicon DMG is built by GitHub Actions:

- [View MTP Shuttle macOS builds](https://github.com/Pew2018/mtpshuttle/actions/workflows/native-swiftui.yml)

Download **MTP-Shuttle-0.3.0-macOS-arm64** from the Artifacts section of the latest successful run, open the DMG, and drag **MTP Shuttle.app** to **Applications**. Actions artifacts are retained for 14 days. A published GitHub Release will provide a persistent download.

The current build is ad-hoc signed and is not notarized with an Apple Developer ID. macOS may show a security prompt the first time you open it.

## Build and verification

The native macOS app is built by .github/workflows/native-swiftui.yml on an Apple Silicon GitHub Actions runner. The workflow:

1. Builds ARM64 Kalam and libusb dynamic libraries
2. Runs Go tests and Swift unit tests
3. Builds and signs MTP Shuttle.app
4. Verifies the app bundle, dynamic library dependencies, and DMG contents
5. Uploads MTP-Shuttle-0.3.0-macOS-arm64.dmg as a build artifact

A passing CI run confirms the build and checks in the workflow. Behavior can still vary with Android devices, cables, storage media, and large-file transfers.

## Limitations

- Apple Silicon (arm64) builds only
- No Developer ID signing, notarization, automatic updates, or persistent release download yet
- Android file renaming, a transfer queue, and Legacy MTP mode are not implemented
- MTP speed, supported operations, and reported file metadata vary by device and firmware

## Repository layout

~~~text
native/OpenMTPNative/          Native SwiftUI / AppKit client
native/OpenMTPNative/Sources/  App UI, transfers, and MTP bridge
native/OpenMTPNative/Tests/    Native app unit tests
ffi/kalam/native/              Kalam Go MTP backend
.github/workflows/             GitHub Actions workflows
app/                           Retained Electron/React client
~~~

The native app bundle version is managed in native/OpenMTPNative/Info.plist. The root package.json belongs to the retained Electron/React project and does not set the native app version.

## License

This project is released under the MIT License. Retained OpenMTP upstream code and its copyright notices remain subject to their original license. See LICENSE and the notices in the relevant source files.
