import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode")
    private var dragDropMode = DragDropMode.copy.rawValue

    @AppStorage("androidOnlyMode")
    private var androidOnlyMode = false

    var body: some View {
        Form {
            Section("Workspace") {
                Toggle("Show only Android Device", isOn: $androidOnlyMode)

                Text("Hide the This Mac pane and use the window as a single-pane Android file browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Drag & Drop") {
                Picker(
                    "When dragging items between panes",
                    selection: $dragDropMode
                ) {
                    ForEach(DragDropMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Choose whether a drag between panes copies items, moves them, or asks each time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 320)
    }
}

#Preview {
    SettingsView()
}
