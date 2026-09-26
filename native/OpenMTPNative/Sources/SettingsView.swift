import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("appLanguage") private var appLanguage = MTPShuttleLanguage.system.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appAppearance = AppearanceMode.system.rawValue
    @AppStorage("alwaysShowTransferProgress") private var alwaysShowTransferProgress = false
    @AppStorage("favoriteFileOpenBehavior") private var favoriteFileOpenBehavior = FavoriteFileOpenBehavior.defaultValue.rawValue
    @AppStorage("favoriteLocations.v1") private var favoritesPayload = "[]"
    @State private var isImportingFavorites = false
    @State private var isExportingFavorites = false
    @State private var isClearFavoritesConfirmationPresented = false
    @State private var favoritesMessage: String?
    @State private var favoritesExportDocument = FavoriteLocationsDocument(data: Data("[]".utf8))
    @State private var isClearLogConfirmationPresented = false
    @State private var logClearResult: String?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $appAppearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.localizationKey)).tag(mode.rawValue)
                    }
                }
            } header: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            } footer: {
                Text("Choose Light, Dark, or System to follow macOS.")
            }

            Section {
                Picker("Double-clicking a favorite file", selection: $favoriteFileOpenBehavior) {
                    ForEach(FavoriteFileOpenBehavior.allCases) { behavior in
                        Text(LocalizedStringKey(behavior.localizationKey)).tag(behavior.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Button("Export Favorites…") {
                    favoritesExportDocument = FavoriteLocationsDocument(data: Data(favoritesPayload.utf8))
                    isExportingFavorites = true
                }
                Button("Import Favorites…") { isImportingFavorites = true }
                Button("Clear Favorites…", role: .destructive) { isClearFavoritesConfirmationPresented = true }
            } header: {
                Label("Favorites", systemImage: "star")
            } footer: {
                Text("Choose what happens when you double-click a favorite file.")
            }

            Section {
                Picker("App Language", selection: $appLanguage) {
                    ForEach(MTPShuttleLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            } header: {
                Label("Language", systemImage: "globe")
            } footer: {
                Text("Automatic follows the macOS language. You can also choose English, Simplified Chinese, or Traditional Chinese.")
            }

            Section {
                Toggle("Show only Android Device", isOn: $androidOnlyMode)
            } header: {
                Label("Workspace", systemImage: "rectangle.split.2x1")
            } footer: {
                Text("Hide This Mac and use a single-pane Android file browser.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When dragging items between panes")
                        .font(.body.weight(.medium))

                    Picker("Drag behavior", selection: $dragDropMode) {
                        ForEach(DragDropMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            } header: {
                Label("Drag & Drop", systemImage: "arrow.left.arrow.right")
            } footer: {
                Text("Choose whether a drag copies items, moves them, or asks each time.")
            }

            Section {
                Toggle("Always show file transfer progress", isOn: $alwaysShowTransferProgress)
            } header: {
                Label("Transfer Progress", systemImage: "arrow.down.circle")
            } footer: {
                Text("When enabled, the detailed transfer window opens automatically. When disabled, click the progress bar at the bottom left to open it.")
            }

            Section {
                Toggle("Enable Quick Look with Space", isOn: $quickLookPreviewEnabled)
            } header: {
                Label("Preview", systemImage: "doc.viewfinder")
            } footer: {
                Text("Select a file and press Space to open the macOS Quick Look preview.")
            }

            Section {
                Toggle("Debug mode", isOn: $debugMode)
                    .onChange(of: debugMode) { enabled in
                        DebugLogger.info("Debug mode " + (enabled ? "enabled" : "disabled"))
                    }

                HStack(spacing: 10) {
                    Button("Open Debug Log") { DebugLogger.openLog() }
                    Button("Copy Debug Log") { DebugLogger.copyLogToClipboard() }
                    Button("Clear Debug Log…") { isClearLogConfirmationPresented = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Log location")
                        .font(.caption.weight(.medium))
                    Text(DebugLogger.logURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            } header: {
                Label("Diagnostics", systemImage: "stethoscope")
            } footer: {
                Text("Enable debug mode only when investigating a problem. Diagnostics never change file operations.")
            }

            Section {
                Button {
                    openWindow(id: "about")
                } label: {
                    HStack {
                        Label("About MTP Shuttle", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Clear Debug Log?", isPresented: $isClearLogConfirmationPresented) {
            Button("Clear Log", role: .destructive) {
                do {
                    try DebugLogger.clearLog()
                    logClearResult = "Debug log cleared."
                } catch {
                    logClearResult = "Could not clear the debug log: \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all current log entries.")
        }
        .alert("Debug Log", isPresented: Binding(
            get: { logClearResult != nil },
            set: { if !$0 { logClearResult = nil } }
        )) {
            Button("OK") { logClearResult = nil }
        } message: {
            Text(logClearResult ?? "")
        }
        .confirmationDialog("Clear Favorites?", isPresented: $isClearFavoritesConfirmationPresented) {
            Button("Clear Favorites", role: .destructive) {
                favoritesPayload = "[]"
                favoritesMessage = "Favorites cleared."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved favorites from this Mac.")
        }
        .fileImporter(isPresented: $isImportingFavorites, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importFavorites(from: result)
        }
        .fileExporter(
            isPresented: $isExportingFavorites,
            document: favoritesExportDocument,
            contentType: .json,
            defaultFilename: "MTP Shuttle Favorites",
            onCompletion: { result in
                switch result {
                case .success:
                    favoritesMessage = "Favorites exported."
                case .failure(let error):
                    favoritesMessage = "Could not export favorites: \\(error.localizedDescription)"
                }
            }
        )
        .alert("Favorites", isPresented: Binding(
            get: { favoritesMessage != nil },
            set: { if !$0 { favoritesMessage = nil } }
        )) {
            Button("OK") { favoritesMessage = nil }
        } message: {
            Text(favoritesMessage ?? "")
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, minHeight: 660)
        .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }

    private func importFavorites(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let imported = try JSONDecoder().decode([FavoriteLocation].self, from: Data(contentsOf: url))
            let existing = FavoriteLocation.decode(favoritesPayload)
            var combined = existing
            for favorite in imported where !combined.contains(where: { $0.sameLocation(as: favorite) }) {
                combined.append(favorite)
            }
            favoritesPayload = FavoriteLocation.encode(combined)
            favoritesMessage = "Favorites imported."
        } catch {
            favoritesMessage = "Could not import favorites: \\(error.localizedDescription)"
        }
    }
}

private struct FavoriteLocationsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview { SettingsView() }
