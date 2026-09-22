import SwiftUI

@main
struct OpenMTPNativeApp: App {
    var body: some Scene {
        WindowGroup("OpenMTP") {
            ContentView()
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
    }
}
