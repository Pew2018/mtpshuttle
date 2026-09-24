import SwiftUI

@main
struct OpenMTPNativeApp: App {
    @NSApplicationDelegateAdaptor(OpenMTPAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MTPShuttleLanguage.storageKey) private var appLanguage = MTPShuttleLanguage.system.rawValue

    var body: some Scene {
        WindowGroup(MTPShuttleText.localized("MTP Shuttle"), id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 480)
                .onAppear {
                    appDelegate.openMainWindow = {
                        openWindow(id: "main")
                        DispatchQueue.main.async {
                            appDelegate.restoreMainWindowFrame()
                        }
                    }
                    appDelegate.restoreMainWindowFrame()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SwiftMTPCommands()
        }

        Window(MTPShuttleText.localized("Settings"), id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 520, height: 220)
        .windowResizability(.contentSize)

        Window(MTPShuttleText.localized("Task Details"), id: "tasks") {
            TaskDetailsView()
        }
        .defaultSize(width: 560, height: 420)
    }
}

private struct SwiftMTPCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openMTPEditActions) private var editActions

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {}

        CommandGroup(after: .newItem) {
            Button(MTPShuttleText.localized("Quick Look")) {
                NotificationCenter.default.post(name: .openMTPQuickLook, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button(MTPShuttleText.localized("Copy")) { editActions?.copy() }
                .disabled(!(editActions?.canCopy ?? false))
                .keyboardShortcut("c", modifiers: .command)

            Button(MTPShuttleText.localized("Cut")) { editActions?.cut() }
                .disabled(!(editActions?.canCopy ?? false))
                .keyboardShortcut("x", modifiers: .command)

            Button(MTPShuttleText.localized("Paste")) { editActions?.paste() }
                .disabled(!(editActions?.canPaste ?? false))
                .keyboardShortcut("v", modifiers: .command)

            Button(MTPShuttleText.localized("Select All")) { editActions?.selectAll() }
                .disabled(!(editActions?.canSelectAll ?? false))
                .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button(MTPShuttleText.localized("Settings…")) {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
