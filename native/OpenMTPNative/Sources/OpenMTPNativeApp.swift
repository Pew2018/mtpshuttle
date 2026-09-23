import SwiftUI

@main
struct OpenMTPNativeApp: App {
    var body: some Scene {
        WindowGroup("OpenMTP") {
            ContentView()
                .frame(minWidth: 980, minHeight: 620)
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

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
