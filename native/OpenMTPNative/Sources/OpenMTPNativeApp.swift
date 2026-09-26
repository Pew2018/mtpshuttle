import SwiftUI

@main
struct OpenMTPNativeApp: App {
    @AppStorage(MTPShuttleLanguage.storageKey) private var appLanguage = MTPShuttleLanguage.system.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appAppearance = AppearanceMode.system.rawValue
    @NSApplicationDelegateAdaptor(OpenMTPAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(MTPShuttleText.localized("MTP Shuttle"), id: "main") {
            ContentView()
                .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
                .preferredColorScheme(AppearanceMode.resolve(appAppearance).colorScheme)
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
                .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
                .preferredColorScheme(AppearanceMode.resolve(appAppearance).colorScheme)
        }
        .defaultSize(width: 630, height: 510)
        .windowResizability(.contentMinSize)

        Window(MTPShuttleText.localized("About MTP Shuttle"), id: "about") {
            AboutView()
                .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
                .preferredColorScheme(AppearanceMode.resolve(appAppearance).colorScheme)
        }
        .defaultSize(width: 440, height: 520)
        .windowResizability(.contentSize)

        Window(MTPShuttleText.localized("Task Details"), id: "tasks") {
            TaskDetailsView()
                .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
                .preferredColorScheme(AppearanceMode.resolve(appAppearance).colorScheme)
        }
        .defaultSize(width: 560, height: 420)
    }
}

private struct SwiftMTPCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openMTPEditActions) private var editActions

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(MTPShuttleText.localized("About MTP Shuttle")) {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .pasteboard) {
        }

        CommandGroup(after: .newItem) {
            Button(MTPShuttleText.localized("Quick Look")) {
                NotificationCenter.default.post(name: .openMTPQuickLook, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button(MTPShuttleText.localized("Copy")) {
                editActions?.copy()
            }
            .disabled(!(editActions?.canCopy ?? false))
            .keyboardShortcut("c", modifiers: .command)

            Button(MTPShuttleText.localized("Cut")) {
                editActions?.cut()
            }
            .disabled(!(editActions?.canCopy ?? false))
            .keyboardShortcut("x", modifiers: .command)

            Button(MTPShuttleText.localized("Paste")) {
                editActions?.paste()
            }
            .disabled(!(editActions?.canPaste ?? false))
            .keyboardShortcut("v", modifiers: .command)

            Button(MTPShuttleText.localized("Select All")) {
                editActions?.selectAll()
            }
            .disabled(!(editActions?.canSelectAll ?? false))
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button(MTPShuttleText.localized("New Folder")) {
                editActions?.newFolder()
            }
            .disabled(!(editActions?.canNewFolder ?? false))

            Button(MTPShuttleText.localized("Properties")) {
                editActions?.showProperties()
            }
            .disabled(!(editActions?.canShowProperties ?? false))

            Button(MTPShuttleText.localized("Delete"), role: .destructive) {
                editActions?.delete()
            }
            .disabled(!(editActions?.canDelete ?? false))
            .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button(MTPShuttleText.localized("Copy to Other Pane")) {
                editActions?.copyToOther()
            }
            .disabled(!(editActions?.canCopyToOther ?? false))

            Button(MTPShuttleText.localized("Move to Other Pane")) {
                editActions?.moveToOther()
            }
            .disabled(!(editActions?.canMoveToOther ?? false))

            Divider()

            Button(MTPShuttleText.localized("Settings…")) {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
