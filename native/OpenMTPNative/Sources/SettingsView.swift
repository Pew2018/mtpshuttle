import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("appLanguage") private var appLanguage = MTPShuttleLanguage.system.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appAppearance = AppearanceMode.system.rawValue
    @AppStorage("alwaysShowTransferProgress") private var alwaysShowTransferProgress = false
    @State private var isClearLogConfirmationPresented = false
    @State private var logClearResult: String?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $appAppearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.localizationKey)).tag(mode.rawValue)
                    }
                }
            } header: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            } footer: {
                Text("Choose Light, Dark, or System to follow macOS.")
            }

            Section {
                Picker("App Language", selection: $appLanguage) {
                    ForEach(MTPShuttleLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            } header: {
                Label("Language", systemImage: "globe")
            } footer: {
                Text("Automatic follows the macOS language. You can also choose English, Simplified Chinese, or Traditional Chinese.")
            }

            Section {
                Toggle("Show only Android Device", isOn: $androidOnlyMode)
            } header: {
                Label("Workspace", systemImage: "rectangle.split.2x1")
            } footer: {
                Text("Hide This Mac and use a single-pane Android file browser.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When dragging items between panes")
                        .font(.body.weight(.medium))

                    Picker("Drag behavior", selection: $dragDropMode) {
                        ForEach(DragDropMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            } header: {
                Label("Drag & Drop", systemImage: "arrow.left.arrow.right")
            } footer: {
                Text("Choose whether a drag copies items, moves them, or asks each time.")
            }

            Section {
                Toggle("Always show file transfer progress", isOn: $alwaysShowTransferProgress)
            } header: {
                Label("Transfer Progress", systemImage: "arrow.down.circle")
            } footer: {
                Text("When enabled, the detailed transfer window opens automatically. When disabled, click the progress bar at the bottom left to open it.")
            }

            Section {
                Toggle("Enable Quick Look with Space", isOn: $quickLookPreviewEnabled)
            } header: {
                Label("Preview", systemImage: "doc.viewfinder")
            } footer: {
                Text("Select a file and press Space to open the macOS Quick Look preview.")
            }

            Section {
                Toggle("Debug mode", isOn: $debugMode)
                    .onChange(of: debugMode) { enabled in
                        DebugLogger.info("Debug mode " + (enabled ? "enabled" : "disabled"))
                    }

                HStack(spacing: 10) {
                    Button("Open Debug Log") { DebugLogger.openLog() }
                    Button("Copy Debug Log") { DebugLogger.copyLogToClipboard() }
                    Button("Clear Debug Log…") { isClearLogConfirmationPresented = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Log location")
                        .font(.caption.weight(.medium))
                    Text(DebugLogger.logURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            } header: {
                Label("Diagnostics", systemImage: "stethoscope")
            } footer: {
                Text("Enable debug mode only when investigating a problem. Diagnostics never change file operations.")
            }

            Section {
                Button {
                    openWindow(id: "about")
                } label: {
                    HStack {
                        Label("About MTP Shuttle", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Clear Debug Log?", isPresented: $isClearLogConfirmationPresented) {
            Button("Clear Log", role: .destructive) {
                do {
                    try DebugLogger.clearLog()
                    logClearResult = "Debug log cleared."
                } catch {
                    logClearResult = "Could not clear the debug log: \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all current log entries.")
        }
        .alert("Debug Log", isPresented: Binding(
            get: { logClearResult != nil },
            set: { if !$0 { logClearResult = nil } }
        )) {
            Button("OK") { logClearResult = nil }
        } message: {
            Text(logClearResult ?? "")
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, minHeight: 660)
        .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }
}

#Preview { SettingsView() }
