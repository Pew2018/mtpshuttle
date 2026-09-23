import SwiftUI

@main
struct OpenMTPNativeApp: App {
    @NSApplicationDelegateAdaptor(OpenMTPAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("OpenMTP", id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 480)
                .onAppear {
                    appDelegate.openMainWindow = {
                        openWindow(id: "main")
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            OpenMTPCommands()
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 520, height: 220)
        .windowResizability(.contentSize)
    }
}

private struct OpenMTPCommands: Commands {
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

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
