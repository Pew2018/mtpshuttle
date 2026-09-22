import SwiftUI

struct FilePaneView: View {
    let title: String
    let subtitle: String
    let path: String
    let items: [FileItem]
    let accent: Color
    var showsPreviewBanner = false

    @State private var viewMode: FileViewMode = .list

    var body: some View {
        VStack(spacing: 0) {
            paneHeader

            if showsPreviewBanner {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("UI preview — Android backend is not connected yet.")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }

            Divider()

            if viewMode == .list {
                listView
            } else {
                gridView
            }

            Divider()

            HStack {
                Text("\(items.count) items")
                Spacer()
                Text("Ready")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.12))
                    Image(systemName: title == "This Mac" ? "macbook" : "cable.connector")
                        .foregroundStyle(accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("View", selection: $viewMode) {
                    ForEach(FileViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(.bar)
    }

    private var listView: some View {
        List(items) { item in
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.title3)
                    .foregroundStyle(item.isDirectory ? accent : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let size = item.size {
                    Text(size)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .listStyle(.inset)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(items) { item in
                    VStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 34))
                            .foregroundStyle(item.isDirectory ? accent : .secondary)

                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if let size = item.size {
                            Text(size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .padding(12)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
            .padding(14)
        }
    }
}
