import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
    }
}

#Preview { SettingsView() }
