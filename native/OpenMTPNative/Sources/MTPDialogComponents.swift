import SwiftUI

struct MTPDialogHeader: View {
    let symbol: String?
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct MTPDialogActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            content
        }
        .padding(.top, 8)
    }
}
