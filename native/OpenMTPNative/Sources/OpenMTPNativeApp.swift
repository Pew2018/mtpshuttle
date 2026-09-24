import SwiftUI

@main
struct OpenMTPNativeApp: App {
    @NSApplicationDelegateAdaptor(OpenMTPAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("MTP Shuttle", id: "main") {
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

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 560, height: 700)
        .windowResizability(.contentSize)

        Window("任务详情", id: "tasks") {
            TaskDetailsView()
        }
        .defaultSize(width: 560, height: 420)
    }
}

private struct SwiftMTPCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openMTPEditActions) private var editActions

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
        }

        CommandGroup(after: .newItem) {
            Button("Quick Look") {
                NotificationCenter.default.post(name: .openMTPQuickLook, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Copy") {
                editActions?.copy()
            }
            .disabled(!(editActions?.canCopy ?? false))
            .keyboardShortcut("c", modifiers: .command)

            Button("Cut") {
                editActions?.cut()
            }
            .disabled(!(editActions?.canCopy ?? false))
            .keyboardShortcut("x", modifiers: .command)

            Button("Paste") {
                editActions?.paste()
            }
            .disabled(!(editActions?.canPaste ?? false))
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") {
                editActions?.selectAll()
            }
            .disabled(!(editActions?.canSelectAll ?? false))
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("New Folder") {
                editActions?.newFolder()
            }
            .disabled(!(editActions?.canNewFolder ?? false))

            Button("Properties") {
                editActions?.showProperties()
            }
            .disabled(!(editActions?.canShowProperties ?? false))

            Button("Delete", role: .destructive) {
                editActions?.delete()
            }
            .disabled(!(editActions?.canDelete ?? false))
            .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button("Copy to Other Pane") {
                editActions?.copyToOther()
            }
            .disabled(!(editActions?.canCopyToOther ?? false))

            Button("Move to Other Pane") {
                editActions?.moveToOther()
            }
            .disabled(!(editActions?.canMoveToOther ?? false))

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
