import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("alwaysShowTransferProgress") private var alwaysShowTransferProgress = false
    @AppStorage("debugMode") private var debugMode = false

    var body: some View {
        Form {
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
            Section("Transfer Progress") {
                Toggle("Always show file transfer progress", isOn: $alwaysShowTransferProgress)
                Text("When enabled, the detailed transfer progress window opens automatically. When disabled, use the progress bar at the bottom left to open it again.")
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
        .formStyle(.grouped).padding(20).frame(width: 520, height: 500)
    }
}

#Preview { SettingsView() }
