import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    private func text(_ key: String) -> String {
        MTPShuttleText.localized(key)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 68, height: 68)
                    .accessibilityLabel(text("App icon placeholder"))

                Text(text("App icon coming soon"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Text("MTP Shuttle")
                    .font(.title2.weight(.semibold))
                Text(text("A simple, native way to move files between your Mac and Android device."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(text("Version")) \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Divider()
                .padding(.vertical, 2)

            VStack(spacing: 0) {
                repositoryLink(
                    title: text("MTP Shuttle on GitHub"),
                    subtitle: text("Project repository"),
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/Pew2018/mtpshuttle")!
                )

                Divider()
                    .padding(.leading, 34)

                repositoryLink(
                    title: text("OpenMTP on GitHub"),
                    subtitle: text("Original project"),
                    symbol: "arrow.up.forward.app",
                    url: URL(string: "https://github.com/ganeshrvel/openmtp")!
                )
            }

            Text(text("Built for macOS"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func repositoryLink(title: String, subtitle: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
