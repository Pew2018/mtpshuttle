import SwiftUI

struct SettingsView: View {
    @AppStorage("dragDropMode")
    private var dragDropMode = DragDropMode.copy.rawValue

    var body: some View {
        Form {
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

                Text("Copy is used by default. Choose “Ask every time” to be prompted to Copy or Move after each drop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 220)
    }
}

#Preview {
    SettingsView()
}
