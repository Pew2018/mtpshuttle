# OpenMTP Native 接手说明（2026-09-23）

请继续维护 [Pew2018/openmtp](https://github.com/Pew2018/openmtp) 中的 SwiftUI 原生 macOS 应用。代码的唯一交付位置是 GitHub 仓库；通过 GitHub Actions 编译、验证并下载 App，不依赖用户本地保留工程文件。当前默认分支为 `master`，Swift 项目位于 `native/OpenMTPNative/`，ARM64 工作流位于 `.github/workflows/native-swiftui.yml`。它调用 `swift test` 和 `scripts/build-app.sh`，上传 `SwiftMTP-0.1.0-arm64` artifact（保留 14 天）。用户要求每次修 bug 或增加功能，结束前都提供一个实际可下载、可运行的 ARM64 App；在正式 Release 前不要编译其他架构。构建通过不等同于用户真机验证，需分别说明。

## 已完成与边界

- 项目已采用 SwiftUI 原生界面并连接真实本地文件浏览及 Kalam/MTP 服务；不应将 `DemoFileSystem` 中的演示数据误认为实际传输实现。
- macOS Finder → 应用 Android Device 的拖入复制已由用户实测有效。应用双栏内部拖拽曾因 `NSPasteboard` 延迟 data representation 在 drop 阶段无法读取；提交 `fb72c98` 通过 concrete `NSString` payload 修复。用户明确要求以后不要修改这部分已验证代码，尤其 `FilePaneView.swift` 的拖拽接收及 `ContentView.swift` 中相应 payload 实现；除非定位出确实相关的新缺陷，且能证明旧行为无回归。
- 关闭窗口后再点 Dock 图标创建窗口的逻辑、设置里可开关的 Space/Quick Look、File 菜单与 ⌘C/⌘X/⌘V 已有实现。曾出现 File 菜单项灰色，后来改用 `focusedSceneValue` 修复；仍需用户对最新 App 的交互复测。
- 本轮对 Quick Look 预览中切换本地文件的缺陷做小范围修复：原实现的 `endPreviewPanelControl` 无条件清空预览 URLs，即使面板还可见也会失去随选择更新的状态。改为仅在面板真正隐藏后清空；`ContentView` 已在本地选择变化时调用 `updateQuickLookSelection()`。请用真实 macOS App 复测：打开文件 A 的预览，直接点文件 B，再多选/取消选、按 Space 关闭并重新打开；确认不再滞留旧内容。若问题仍存在，检查 QLPreviewPanel 控制权、SwiftUI selection 通知顺序和主线程异步时序。不要把 CI 编译通过写成实机功能通过。

## 待办：Android Device → 系统 Finder 拖拽复制（本轮只分析，尚未实现）

目标：从应用 Android 文件栏拖出单个或多个文件、文件夹到系统 Finder 的目标目录，完成真实内容的复制；不能只显示拖拽图标或生成假文件。

现状与原因：`ContentView.makeExternalDragProvider` 对 Android 项目输出应用内部使用的 `DemoDragPayload` 字符串和自定义 UTI。应用内部的 `OpenMTPExternalDropReceiver` 可以解码它，但系统 Finder 无法通过它获得可写入磁盘的文件内容或文件 promise。当前 fallback 的 `localURL` 仅适用于 Mac 项目，Android 项目没有本地 URL。多个选中项目被打包在单个 payload 中，Finder 也不会自动把它拆成多个文件。已有 Android → 应用 Mac 栏下载路径：`ContentView.performTransfer` → `MTPService.download` → `KalamBridge.download`，可以复用下载能力，不应把远程设备路径伪装成本地 `fileURL`。

实现建议：为 Android → 系统 Finder 增加独立的外部拖拽路径（例如 AppKit `NSFilePromiseProvider` / `NSFilePromiseProviderDelegate`，按每个选中项目分别提供文件 promise）。Finder 选定目标目录后，异步将 MTP 文件或递归文件夹下载到 promise 的目标 URL；明确文件命名、同名冲突、进度/取消、设备断开、失败与多选语义，并仅在实际写入成功后报告完成。现有内部 payload 和 Finder → Android 接收分支应保留。需要设计 SwiftUI 与 AppKit drag source 的衔接：当前每行 `.onDrag` 只返回一个 `NSItemProvider`，单个 provider 不一定能表示 Finder 所需的多个独立文件 promise。先用真实 Finder 逐项验证单文件、多个文件、文件夹、混合选择、大文件及断连。预计中高工作量：基础单文件约半天至一天；多选、目录递归、错误处理、Finder 交互及真机回归合计约 2–5 天，视现有 Kalam 下载路径的表现而变。

## 交付流程

1. 从 GitHub 最新 `master` 核对代码、提交及 Actions 状态；不要以旧 ZIP、记忆或本地副本覆盖仓库较新的改动。
2. 每次仅做用户指定范围的最小改动；保留已确认有效的拖拽代码。
3. 只用 `native-swiftui.yml` 的 ARM64 job 构建；检查测试、bundle、签名、Mach-O arm64 和 artifact 均成功，并给用户可直接获取的 Actions artifact / 下载链接。没有真机交互验证时明确说明。
4. 本轮 Android → 系统 Finder 的拖拽仅分析，等待用户下轮明确要求实现；后续按上面的目标实施。
