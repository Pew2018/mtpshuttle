import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage(MTPShuttleLanguage.storageKey) private var appLanguage = MTPShuttleLanguage.system.rawValue

    private func text(_ key: String) -> String { MTPShuttleText.localized(key) }

    var body: some View {
        Form {
            Section(text("Language")) {
                Picker(text("App Language"), selection: $appLanguage) {
                    ForEach(MTPShuttleLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                Text(text("Automatic follows the macOS language. You can also choose English, Simplified Chinese, or Traditional Chinese."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(text("Workspace")) {
                Toggle(text("Show only Android Device"), isOn: $androidOnlyMode)
                Text(text("Hide the This Mac pane and use the window as a single-pane Android file browser."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(text("Drag & Drop")) {
                Picker(text("When dragging items between panes"), selection: $dragDropMode) {
                    ForEach(DragDropMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode.rawValue)
                    }
                }.pickerStyle(.radioGroup)
                Text(text("Choose whether a drag between panes copies items, moves them, or asks each time."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(text("Preview")) {
                Toggle(text("Enable Quick Look with Space"), isOn: $quickLookPreviewEnabled)
                Text(text("Select a file and press Space to open the macOS Quick Look preview."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(text("Diagnostics")) {
                Toggle(text("Debug mode"), isOn: $debugMode)
                    .onChange(of: debugMode) { enabled in
                        DebugLogger.info(text(enabled ? "Debug mode enabled" : "Debug mode disabled"))
                    }
                HStack {
                    Button(text("Open Debug Log")) { DebugLogger.openLog() }
                    Button(text("Copy Debug Log")) { DebugLogger.copyLogToClipboard() }
                }
                Text(DebugLogger.logURL.path)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 570)
        .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }
}

#Preview { SettingsView() }
