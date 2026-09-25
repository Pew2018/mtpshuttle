import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    private var text: (String) -> String {
        MTPShuttleText.localized
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlAccentColor).opacity(0.14),
                                Color(nsColor: .controlBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 43, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                    }
                    .frame(width: 96, height: 96)
                    .accessibilityLabel(text("App icon placeholder"))

                Text(text("App icon coming soon"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                Text("MTP Shuttle")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(text("A simple, native way to move files between your Mac and Android device."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(text("Version")) \(appVersion)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            VStack(spacing: 9) {
                repositoryLink(
                    title: text("MTP Shuttle on GitHub"),
                    subtitle: text("Project repository"),
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/Pew2018/mtpshuttle")!
                )
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
        }
        .padding(30)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func repositoryLink(title: String, subtitle: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .frame(width: 34, height: 34)
                    .background(Color(nsColor: .controlAccentColor).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(11)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
