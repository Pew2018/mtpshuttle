import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            WorkspaceView()
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    // Navigation will be connected to the file browsing model later.
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .help("Back")
            }

            ToolbarItem {
                Button {
                    // Navigation will be connected to the file browsing model later.
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .help("Forward")
            }

            ToolbarItem {
                Button {
                    // Refresh will be connected to native services later.
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }

            ToolbarItem(placement: .principal) {
                Text("OpenMTP")
                    .font(.headline)
            }
        }
    }
}

private struct SidebarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connection")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            HStack(spacing: 10) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Android device")
                        .font(.subheadline.weight(.medium))
                    Text("Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("The two panes below are the file sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("The sidebar is reserved for app-level controls and device status.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)

            Spacer()

            HStack {
                Text("Native SwiftUI")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

private struct WorkspaceView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FilePaneView(
                    title: "This Mac",
                    subtitle: "Local files",
                    path: "/Users/",
                    items: FileItem.localSamples
                )

                Divider()

                FilePaneView(
                    title: "Android Device",
                    subtitle: "Not connected",
                    path: "/Internal storage/",
                    items: FileItem.androidSamples,
                    showsPreviewBanner: true
                )
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)

                Text("The native UI is ready. MTP services will be connected in the next phase.")
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
