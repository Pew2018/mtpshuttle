import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case filesAndTransfers
    case favorites
    case diagnostics
    case about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .appearance: return "Appearance"
        case .filesAndTransfers: return "Files & Transfers"
        case .favorites: return "Favorites"
        case .diagnostics: return "Diagnostics"
        case .about: return "About"
        }
    }
}

private struct SettingsSectionPositions: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum SettingsConfirmation: Equatable {
    case clearFavorites
    case clearLog

    var title: String {
        switch self {
        case .clearFavorites: return MTPShuttleText.localized("Clear Favorites?")
        case .clearLog: return MTPShuttleText.localized("Clear Debug Log?")
        }
    }

    var message: String {
        switch self {
        case .clearFavorites:
            return MTPShuttleText.localized("This removes all saved favorites from this Mac.")
        case .clearLog:
            return MTPShuttleText.localized("This permanently removes all current log entries.")
        }
    }
}

private enum SettingsMessage: Identifiable {
    case favoritesCleared
    case favoritesImported
    case favoritesExported
    case favoritesImportFailed(String)
    case favoritesExportFailed(String)
    case logCleared
    case logClearFailed(String)

    var id: String { title + "|" + message }

    var title: String {
        switch self {
        case .favoritesCleared, .favoritesImported, .favoritesExported,
             .favoritesImportFailed, .favoritesExportFailed:
            return MTPShuttleText.localized("Favorites")
        case .logCleared, .logClearFailed:
            return MTPShuttleText.localized("Debug Log")
        }
    }

    var message: String {
        switch self {
        case .favoritesCleared:
            return MTPShuttleText.localized("Favorites cleared.")
        case .favoritesImported:
            return MTPShuttleText.localized("Favorites imported.")
        case .favoritesExported:
            return MTPShuttleText.localized("Favorites exported.")
        case .favoritesImportFailed(let detail):
            return MTPShuttleText.format("Could not import favorites: %@", detail)
        case .favoritesExportFailed(let detail):
            return MTPShuttleText.format("Could not export favorites: %@", detail)
        case .logCleared:
            return MTPShuttleText.localized("Debug log cleared.")
        case .logClearFailed(let detail):
            return MTPShuttleText.format("Could not clear the debug log: %@", detail)
        }
    }
}

struct SettingsView: View {
    @AppStorage("dragDropMode") private var dragDropMode = DragDropMode.copy.rawValue
    @AppStorage("androidOnlyMode") private var androidOnlyMode = false
    @AppStorage("quickLookPreviewEnabled") private var quickLookPreviewEnabled = true
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("appLanguage") private var appLanguage = MTPShuttleLanguage.system.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appAppearance = AppearanceMode.system.rawValue
    @AppStorage("alwaysShowTransferProgress") private var alwaysShowTransferProgress = false
    @AppStorage("favoriteFileOpenBehavior") private var favoriteFileOpenBehavior = FavoriteFileOpenBehavior.defaultValue.rawValue
    @AppStorage("favoriteLocations.v1") private var favoritesPayload = "[]"
    @AppStorage("openFavoritesOnLaunch") private var openFavoritesOnLaunch = false

    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var isImportingFavorites = false
    @State private var isExportingFavorites = false
    @State private var activeConfirmation: SettingsConfirmation?
    @State private var activeMessage: SettingsMessage?
    @State private var favoritesExportDocument = FavoriteLocationsDocument(data: Data("[]".utf8))

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                sidebar(scrollTo: proxy)
                Divider()
                settingsContent
            }
            .frame(minWidth: 850, minHeight: 660)
            .background(Color(nsColor: .windowBackgroundColor))
            .onPreferenceChange(SettingsSectionPositions.self) { positions in
                updateSelectedCategory(from: positions)
            }
        }
        .confirmationDialog(
            Text(activeConfirmation?.title ?? ""),
            isPresented: Binding(
                get: { activeConfirmation != nil },
                set: { if !$0 { activeConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if activeConfirmation == .clearFavorites {
                Button("Clear Favorites", role: .destructive) {
                    activeConfirmation = nil
                    favoritesPayload = "[]"
                    activeMessage = .favoritesCleared
                }
            } else if activeConfirmation == .clearLog {
                Button("Clear Log", role: .destructive) {
                    activeConfirmation = nil
                    do {
                        try DebugLogger.clearLog()
                        activeMessage = .logCleared
                    } catch {
                        activeMessage = .logClearFailed(error.localizedDescription)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                activeConfirmation = nil
            }
        } message: {
            Text(activeConfirmation?.message ?? "")
        }
        .alert(
            Text(activeMessage?.title ?? ""),
            isPresented: Binding(
                get: { activeMessage != nil },
                set: { if !$0 { activeMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { activeMessage = nil }
            },
            message: {
                Text(activeMessage?.message ?? "")
            }
        )
        .fileImporter(
            isPresented: $isImportingFavorites,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
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
                    activeMessage = .favoritesExported
                case .failure(let error):
                    activeMessage = .favoritesExportFailed(error.localizedDescription)
                }
            }
        )
        .environment(\.locale, MTPShuttleLanguage.locale(for: appLanguage))
    }

    private func sidebar(scrollTo proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(category.rawValue, anchor: .top)
                    }
                } label: {
                    Text(LocalizedStringKey(category.titleKey))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedCategory == category ? Color.accentColor : Color.primary)
                        .background {
                            if selectedCategory == category {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.13))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section(.appearance) {
                    settingsGroup {
                        settingRow("Appearance") {
                            Picker("Appearance", selection: $appAppearance) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(LocalizedStringKey(mode.localizationKey)).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 285)
                            .accessibilityLabel(Text("Appearance"))
                        }

                        rowDivider

                        settingRow(
                            "App Language",
                            detail: "Choose the language used in the app."
                        ) {
                            Picker("App Language", selection: $appLanguage) {
                                ForEach(MTPShuttleLanguage.allCases) { language in
                                    Text(language.displayName).tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 285, alignment: .trailing)
                        }

                        rowDivider

                        settingRow(
                            "Show only Android devices",
                            detail: "When enabled, the device browser shows only Android devices."
                        ) {
                            Toggle("Show only Android devices", isOn: $androidOnlyMode)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Show only Android devices"))
                        }
                    }
                }

                section(.filesAndTransfers) {
                    settingsGroup {
                        settingRow(
                            "Enable Quick Look with Space",
                            detail: "Select a file and press Space to open the macOS Quick Look preview."
                        ) {
                            Toggle("Enable Quick Look with Space", isOn: $quickLookPreviewEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Enable Quick Look with Space"))
                        }

                        rowDivider

                        settingRow(
                            "Show Transfer Progress Window",
                            detail: "When enabled, the detailed transfer window opens automatically. When disabled, click the progress bar at the bottom left to open it."
                        ) {
                            Toggle("Show Transfer Progress Window", isOn: $alwaysShowTransferProgress)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Show Transfer Progress Window"))
                        }

                        rowDivider

                        settingRow(
                            "Default Drop Action",
                            detail: "Applies to files dragged from Finder into Android and items dragged between panes. Folder drops may still require separate confirmation."
                        ) {
                            Picker("Default Drop Action", selection: $dragDropMode) {
                                ForEach(DragDropMode.allCases) { mode in
                                    Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 285)
                        }
                    }
                }

                section(.favorites) {
                    settingsGroup {
                        settingRow(
                            "Show Favorites on Launch",
                            detail: "Automatically show the Favorites shelf when the app starts."
                        ) {
                            Toggle("Show Favorites on Launch", isOn: $openFavoritesOnLaunch)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Show Favorites on Launch"))
                        }

                        rowDivider

                        settingRow(
                            "Double-clicking a favorite file",
                            detail: "Choose what happens when you double-click a favorite file."
                        ) {
                            Picker("Double-clicking a favorite file", selection: $favoriteFileOpenBehavior) {
                                Text("Show File Properties").tag(FavoriteFileOpenBehavior.showProperties.rawValue)
                                Text("Reveal in Folder and Select File").tag(FavoriteFileOpenBehavior.revealAndSelect.rawValue)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                        }

                        rowDivider

                        settingRow(
                            "Manage Favorites",
                            detail: "Export, import, or remove all saved favorites."
                        ) {
                            HStack(spacing: 8) {
                                Button("Export Favorites…") {
                                    favoritesExportDocument = FavoriteLocationsDocument(data: Data(favoritesPayload.utf8))
                                    isExportingFavorites = true
                                }
                                .buttonStyle(.bordered)

                                Button("Import Favorites…") {
                                    isImportingFavorites = true
                                }
                                .buttonStyle(.bordered)

                                Button("Clear Favorites…", role: .destructive) {
                                    activeConfirmation = .clearFavorites
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                section(.diagnostics) {
                    settingsGroup {
                        settingRow(
                            "Debug Mode",
                            detail: "Collect additional information to help troubleshoot issues."
                        ) {
                            Toggle("Debug Mode", isOn: $debugMode)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel(Text("Debug Mode"))
                                .onChange(of: debugMode) { enabled in
                                    DebugLogger.info("Debug mode " + (enabled ? "enabled" : "disabled"))
                                }
                        }

                        rowDivider

                        settingRow(
                            "Log Actions",
                            detail: "Open the log, copy it to the clipboard, or clear its contents."
                        ) {
                            HStack(spacing: 8) {
                                Button("Open Log") { DebugLogger.openLog() }
                                    .buttonStyle(.bordered)
                                Button("Copy Log") { DebugLogger.copyLogToClipboard() }
                                    .buttonStyle(.bordered)
                                Button("Clear Log…", role: .destructive) {
                                    activeConfirmation = .clearLog
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        rowDivider

                        settingRow("Log Location") {
                            Text(DebugLogger.logURL.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .frame(maxWidth: 330, alignment: .leading)
                        }
                    }
                }

                section(.about) {
                    settingsGroup {
                        settingRow("App Version") {
                            Text(appVersion)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        rowDivider

                        settingRow(
                            "Project Information",
                            detail: "MTP Shuttle is an open-source macOS app for transferring files between a Mac and Android device."
                        ) {
                            VStack(alignment: .trailing, spacing: 6) {
                                Link("View Project", destination: URL(string: "https://github.com/Pew2018/mtpshuttle")!)
                                Link("Original Project", destination: URL(string: "https://github.com/ganeshrvel/openmtp")!)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .coordinateSpace(name: "settingsScroll")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 2)
    }

    private func section<Content: View>(
        _ category: SettingsCategory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(category.titleKey))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .id(category.rawValue)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SettingsSectionPositions.self,
                    value: [category.rawValue: geometry.frame(in: .named("settingsScroll")).minY]
                )
            }
        }
    }

    private func settingsGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.7)
            }
    }

    private func settingRow<Control: View>(
        _ titleKey: String,
        detail detailKey: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(titleKey))
                    .font(.body.weight(.medium))
                if let detailKey {
                    Text(LocalizedStringKey(detailKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .frame(maxWidth: 360, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }

    private func updateSelectedCategory(from positions: [String: CGFloat]) {
        let passed = positions
            .filter { $0.value <= 90 }
            .max(by: { $0.value < $1.value })

        let candidate = passed ?? positions.min(by: { $0.value < $1.value })
        if let rawValue = candidate?.key,
           let category = SettingsCategory(rawValue: rawValue) {
            selectedCategory = category
        }
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
            activeMessage = .favoritesImported
        } catch {
            activeMessage = .favoritesImportFailed(error.localizedDescription)
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
