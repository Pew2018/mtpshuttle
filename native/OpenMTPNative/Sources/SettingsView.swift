import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("appLanguage") private var appLanguage = MTPShuttleLanguage.system.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("App Language", selection: $appLanguage) {
                    ForEach(MTPShuttleLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                Text("Automatic follows the macOS language. You can also choose English, Simplified Chinese, or Traditional Chinese.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Workspace") {
                Toggle("Show only Android Device", isOn: $androidOnlyMode)
                Text("Hide the This Mac pane and use the window as a single-pane Android file browser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Drag & Drop") {
                Picker("When dragging items between panes", selection: $dragDropMode) {
                    ForEach(DragDropMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }.pickerStyle(.radioGroup)
                Text("Choose whether a drag between panes copies items, moves them, or asks each time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Preview") {
                Toggle("Enable Quick Look with Space", isOn: $quickLookPreviewEnabled)
                Text("Select a file and press Space to open the macOS Quick Look preview.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Diagnostics") {
                Toggle("Debug mode", isOn: $debugMode)
                    .onChange(of: debugMode) { enabled in
                        DebugLogger.info("Debug mode " + (enabled ? "enabled" : "disabled"))
                    }
                HStack {
                    Button("Open Debug Log") { DebugLogger.openLog() }
                    Button("Copy Debug Log") { DebugLogger.copyLogToClipboard() }
                }
                Text(DebugLogger.logURL.path)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped).padding(20).frame(width: 520, height: 570)
            .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }
}

#Preview { SettingsView() }
