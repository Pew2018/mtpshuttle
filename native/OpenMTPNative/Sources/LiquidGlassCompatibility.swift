import SwiftUI

/// Applies the macOS 26 Liquid Glass material when available while preserving
/// an equivalent native material on earlier supported macOS releases.
extension View {
    @ViewBuilder
    func liquidGlassBackground<S: Shape, F: ShapeStyle>(
        in shape: S,
        fallback: F
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }
}
