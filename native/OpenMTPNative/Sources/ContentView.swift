import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .android
    @State private var isConnected = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, isConnected: isConnected)
        } detail: {
            WorkspaceView(isConnected: $isConnected)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    // Navigation is intentionally visual-only in this first UI shell.
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .help("Back")
            }

            ToolbarItem {
                Button {
                    // Navigation is intentionally visual-only in this first UI shell.
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .help("Forward")
            }

            ToolbarItem {
                Button {
                    // Refresh will be connected to the native services later.
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }

            ToolbarItem(placement: .principal) {
                Text("OpenMTP")
                    .font(.headline)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy) {
                        isConnected.toggle()
                    }
                } label: {
                    Label(
                        isConnected ? "Connected" : "Connect",
                        systemImage: isConnected ? "checkmark.circle.fill" : "cable.connector"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let isConnected: Bool

    var body: some View {
        List(selection: $selection) {
            Section("Locations") {
                Label(SidebarItem.computer.title, systemImage: SidebarItem.computer.icon)
                    .tag(SidebarItem.computer)

                Label(SidebarItem.android.title, systemImage: SidebarItem.android.icon)
                    .tag(SidebarItem.android)
            }

            Section("Device") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isConnected ? "Device connected" : "No device connected")
                            .font(.subheadline.weight(.medium))
                        Text(isConnected ? "Ready for MTP operations" : "USB / MTP will be added next")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Prototype") {
                Label("Native SwiftUI", systemImage: "swift")
                Label("ARM64 build", systemImage: "cpu")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenMTP")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Native UI prototype")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("0.1.0")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct WorkspaceView: View {
    @Binding var isConnected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FilePaneView(
                    title: "This Mac",
                    subtitle: "Local files",
                    path: "/Users/",
                    items: FileItem.localSamples,
                    accent: .blue
                )

                Divider()

                FilePaneView(
                    title: "Android Device",
                    subtitle: isConnected ? "MTP storage" : "Preview",
                    path: "/Internal storage/",
                    items: FileItem.androidSamples,
                    accent: .green,
                    showsPreviewBanner: !isConnected
                )
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)

                Text(
                    isConnected
                        ? "Connected state is visual only for this first build. MTP services will be wired in a later phase."
                        : "This is the first native UI build. The MTP backend is intentionally not connected yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text("SwiftUI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
