//
//  SettingsView.swift
//  manather
//
//  The centered modal settings window (opened by the gear icon). A left sidebar
//  of tabs — General, Libraries, AI Providers, CLI Agents, About — with content
//  on the right. The dimmed backdrop and click-outside-to-close are provided by
//  the caller (GalleryGridView); this view is the card itself. Esc also closes it.
//

import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, libraries, providers, cli, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:   return "General"
        case .libraries: return "Libraries"
        case .providers: return "AI Providers"
        case .cli:       return "CLI Agents"
        case .about:     return "About"
        }
    }
    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .libraries: return "books.vertical"
        case .providers: return "key.horizontal"
        case .cli:       return "terminal"
        case .about:     return "info.circle"
        }
    }
}

struct SettingsView: View {
    let onLoadDemo: () -> Void
    let onClearCache: () -> Void
    let onImportClaude: () -> String
    let onDismiss: () -> Void

    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var tab: SettingsTab = .general
    @State private var store = AIProviderStore()
    @State private var detector = CLIAgentDetector()
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(ManatherTheme.hairline)
            content
        }
        .frame(width: 720, height: 540)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ManatherTheme.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ManatherTheme.hairline, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onExitCommand { onDismiss() }
        // Esc closes the window regardless of which control has focus. A local
        // key monitor (the pattern used elsewhere in the app) is reliable here
        // where .onExitCommand / .onKeyPress depend on focus.
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { onDismiss(); return nil }   // 53 = Esc
                return event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("Settings")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ManatherTheme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { item in
                tabButton(item)
            }
            Spacer()
        }
        .frame(width: 196)
        .padding(.horizontal, 8)
        .background(ManatherTheme.paperDeep)
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        Button {
            withAnimation(ManatherTheme.uiMotion) { tab = item }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: tab == item ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tab == item ? ManatherTheme.ink : ManatherTheme.mutedInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tab == item ? (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Title bar with close button.
            HStack {
                Text(tab.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ManatherTheme.ink)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ManatherTheme.mutedInk)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().overlay(ManatherTheme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .general:
                        GeneralSettingsView(
                            onLoadDemo: onLoadDemo,
                            onClearCache: onClearCache, onImportClaude: onImportClaude
                        )
                    case .libraries:
                        LibrariesSettingsView()
                    case .providers:
                        AIProvidersSettingsView(store: store)
                    case .cli:
                        CLIAgentsSettingsView(detector: detector)
                    case .about:
                        AboutSettingsView()
                    }
                }
                .padding(22)
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    let onLoadDemo: () -> Void
    let onClearCache: () -> Void
    let onImportClaude: () -> String

    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Content — fill the current library with material.
            SettingsStyle.sectionHeader("Content")
            SettingsStyle.actionRow(icon: "square.and.arrow.down", title: "Import from ~/.claude",
                                    subtitle: "Add your existing skills & MCP servers to the library") {
                withAnimation(ManatherTheme.uiMotion) { importMessage = onImportClaude() }
            }
            if let importMessage {
                Text(importMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(ManatherTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            SettingsStyle.actionRow(icon: "sparkles", title: "Load Demo Assets",
                                    subtitle: "Fill the library with sample content", action: onLoadDemo)

            // Storage — disk maintenance.
            SettingsStyle.sectionHeader("Storage")
            SettingsStyle.actionRow(icon: "trash", title: "Clear Image Cache",
                                    subtitle: "Free disk space; thumbnails regenerate", destructive: true, action: onClearCache)

            // Shortcuts.
            SettingsStyle.sectionHeader("Global Screenshot Hotkey")
            HotKeyRecorderView()
        }
    }
}

// MARK: - Libraries

/// Full library management: list every library, switch, export any to a ZIP,
/// rename, delete, create new, import. Self-contained — reads/writes SwiftData
/// directly and changes the active library via the shared AppStorage key (the
/// gallery picks that up and re-filters / resets its view state).
struct LibrariesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Library.dateCreated) private var libraries: [Library]
    @AppStorage("activeLibraryID") private var activeLibraryIDString = ""
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var pendingDelete: Library?

    private var activeID: UUID? { UUID(uuidString: activeLibraryIDString) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep separate libraries — e.g. one per client or topic. Switch between them, export any as a shareable .zip, or import one someone sent you.")
                .font(.system(size: 12))
                .foregroundStyle(ManatherTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            let counts = itemCounts()
            ForEach(libraries) { library in
                libraryRow(library, count: counts[library.id] ?? 0)
            }

            SettingsStyle.sectionHeader("Add")
            SettingsStyle.actionRow(icon: "plus", title: "New Library",
                                    subtitle: "Start an empty library and switch to it") { createLibrary() }
            SettingsStyle.actionRow(icon: "square.and.arrow.down", title: "Import Library (.zip)…",
                                    subtitle: "Rebuild a shared library from a ZIP") { importLibrary() }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”? Its assets and collections are permanently removed.",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Library", role: .destructive) {
                if let lib = pendingDelete { deleteLibrary(lib) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func libraryRow(_ library: Library, count: Int) -> some View {
        let isActive = library.id == activeID
        return HStack(spacing: 10) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? ManatherTheme.accent : ManatherTheme.mutedInk)
                .frame(width: 20)

            if renamingID == library.id {
                TextField("Library name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink)
                    .focused($renameFocused)
                    .onSubmit { commitRename(library) }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(library.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ManatherTheme.ink)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(ManatherTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(ManatherTheme.accent.opacity(0.15)))
                        }
                    }
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(.system(size: 11))
                        .foregroundStyle(ManatherTheme.mutedInk)
                }
            }

            Spacer(minLength: 8)

            if renamingID == library.id {
                rowButton("checkmark", "Save") { commitRename(library) }
            } else {
                if !isActive { rowButton("arrow.right.circle", "Switch to this library") { switchTo(library) } }
                rowButton("square.and.arrow.up", "Export as .zip") { exportLibrary(library) }
                rowButton("pencil", "Rename") { startRename(library) }
                rowButton("trash", "Delete", destructive: true) { pendingDelete = library }
                    .disabled(libraries.count <= 1)
                    .opacity(libraries.count <= 1 ? 0.35 : 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.card(isDarkMode))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive && renamingID != library.id { switchTo(library) }
        }
    }

    private func rowButton(_ icon: String, _ tooltip: String, destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? Color(red: 0.85, green: 0.30, blue: 0.28) : ManatherTheme.mutedInk)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Actions

    private func itemCounts() -> [UUID: Int] {
        let all = (try? modelContext.fetch(FetchDescriptor<AssetItem>())) ?? []
        var counts: [UUID: Int] = [:]
        for asset in all where !asset.isDeleted && !asset.isTrash {
            if let id = asset.libraryID { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private func createLibrary() {
        let lib = Library(name: LibraryManager.uniqueName("New Library", context: modelContext))
        modelContext.insert(lib)
        activeLibraryIDString = lib.id.uuidString
    }

    private func switchTo(_ library: Library) {
        guard library.id != activeID else { return }
        activeLibraryIDString = library.id.uuidString
    }

    private func startRename(_ library: Library) {
        renameText = library.name
        renamingID = library.id
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ library: Library) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let clash = libraries.contains {
                $0.id != library.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            library.name = clash ? LibraryManager.uniqueName(trimmed, context: modelContext) : trimmed
        }
        renamingID = nil
        renameText = ""
    }

    private func deleteLibrary(_ library: Library) {
        guard libraries.count > 1 else { return }   // never delete the last library
        let all = (try? modelContext.fetch(FetchDescriptor<AssetItem>())) ?? []
        for asset in all where asset.libraryID == library.id {
            if !asset.relativeFilePath.isEmpty {
                FileManagerHelper.deleteFile(relativePath: asset.relativeFilePath)
                ImageCache.shared.removeCachedImages(for: asset.relativeFilePath)
            }
            modelContext.delete(asset)
        }
        let collections = (try? modelContext.fetch(FetchDescriptor<AssetCollection>())) ?? []
        for collection in collections where collection.libraryID == library.id {
            modelContext.delete(collection)
        }
        let wasActive = library.id == activeID
        let fallback = libraries.first { $0.id != library.id }
        modelContext.delete(library)
        if wasActive, let fallback { activeLibraryIDString = fallback.id.uuidString }
    }

    private func exportLibrary(_ library: Library) {
        let all = (try? modelContext.fetch(FetchDescriptor<AssetItem>())) ?? []
        let libAssets = all.filter { $0.libraryID == library.id && !$0.isDeleted && !$0.isTrash }
        let collections = ((try? modelContext.fetch(FetchDescriptor<AssetCollection>())) ?? [])
            .filter { $0.libraryID == library.id }
            .map(\.name)
        LibraryArchive.export(libraryName: library.name, assets: libAssets, collections: collections)
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Import Library"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let library = try LibraryArchive.importArchive(from: url, context: modelContext)
            activeLibraryIDString = library.id.uuidString
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - AI Providers

struct AIProvidersSettingsView: View {
    let store: AIProviderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect a provider by API key. Keys are stored in your macOS Keychain — never in plain text. The default provider powers AI features.")
                .font(.system(size: 12))
                .foregroundStyle(ManatherTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(AIProvider.all) { provider in
                ProviderRow(provider: provider, store: store)
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: AIProvider
    let store: AIProviderStore

    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var expanded = false
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var editingKey = false

    private var isDefault: Bool { store.defaultProviderID == provider.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if provider.kind.needsKey { keySection }
                    if provider.baseURLEditable { baseURLSection }
                    modelSection
                    footer
                }
                .padding(.top, 12)
                .padding([.horizontal, .bottom], 14)
            }
        }
        .background(SettingsStyle.card(isDarkMode))
        .onAppear { editingKey = !store.isConfigured(provider) }
    }

    private var header: some View {
        Button {
            withAnimation(ManatherTheme.uiMotion) { expanded.toggle() }
            // Opening a configured provider loads its live models if we don't have them yet.
            if expanded { Task { await store.refreshModelsIfNeeded(provider) } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.iconSystemName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ManatherTheme.accent)
                    .frame(width: 20)
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink)
                if isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ManatherTheme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(ManatherTheme.accent.opacity(0.15)))
                }
                Spacer()
                statusBadge
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ManatherTheme.mutedInk)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusBadge: some View {
        switch store.result(for: provider) {
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly).font(.system(size: 11))
                .foregroundStyle(.orange).help(msg)
        case .idle:
            if store.isConfigured(provider) {
                Image(systemName: "key.fill").font(.system(size: 10)).foregroundStyle(ManatherTheme.mutedInk)
            }
        }
    }

    // MARK: Key

    @ViewBuilder private var keySection: some View {
        if store.hasKey(provider) && !editingKey {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.system(size: 12))
                Text("API key saved in Keychain").font(.system(size: 12)).foregroundStyle(ManatherTheme.ink)
                Spacer()
                Button("Replace") { editingKey = true; keyDraft = "" }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(ManatherTheme.accent)
                Button("Remove") { store.setAPIKey("", for: provider) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Group {
                        if showKey {
                            TextField(keyPlaceholder, text: $keyDraft)
                        } else {
                            SecureField(keyPlaceholder, text: $keyDraft)
                        }
                    }
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .foregroundStyle(ManatherTheme.ink)
                    .padding(8).background(SettingsStyle.field(isDarkMode))

                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye").font(.system(size: 12))
                            .foregroundStyle(ManatherTheme.mutedInk).frame(width: 30, height: 30)
                            .background(SettingsStyle.field(isDarkMode))
                    }.buttonStyle(.plain)

                    Button("Save") {
                        store.setAPIKey(keyDraft, for: provider)
                        keyDraft = ""; editingKey = false; showKey = false
                        // Saved a key → immediately pull the models it can use.
                        Task { await store.refreshModels(provider) }
                    }
                    .buttonStyle(SettingsButtonStyle(prominent: true, enabled: !keyDraft.isEmpty))
                    .disabled(keyDraft.isEmpty)
                }
                Link("Get an API key ↗", destination: URL(string: provider.docsURL)!)
                    .font(.system(size: 11)).foregroundStyle(ManatherTheme.accent)
            }
        }
    }

    private var keyPlaceholder: String {
        provider.keyPrefixHint.isEmpty ? "Paste API key" : "Paste API key (\(provider.keyPrefixHint)…)"
    }

    // MARK: Base URL (Ollama / local)

    private var baseURLSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsStyle.fieldLabel("Server URL")
            TextField(provider.defaultBaseURL, text: Binding(
                get: { store.baseURL(for: provider) },
                set: { store.setBaseURL($0, for: provider) }
            ))
            .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(ManatherTheme.ink)
            .padding(8).background(SettingsStyle.field(isDarkMode))
        }
    }

    // MARK: Model

    @ViewBuilder private var modelSection: some View {
        let models = store.discoveredModels(for: provider)
        let isLoading = { if case .testing = store.result(for: provider) { return true }; return false }()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SettingsStyle.fieldLabel("Default model")
                Spacer()
                if !models.isEmpty {
                    Button { Task { await store.refreshModels(provider) } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ManatherTheme.mutedInk)
                    }
                    .buttonStyle(.plain).help("Reload the model list from the provider")
                    .disabled(isLoading)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading models…").font(.system(size: 12)).foregroundStyle(ManatherTheme.mutedInk)
                }
            } else if models.isEmpty {
                Text(store.isConfigured(provider)
                     ? "No models loaded yet. Use “Test connection” to fetch the models available for this key."
                     : "Add an API key to load the available models.")
                    .font(.system(size: 12)).foregroundStyle(ManatherTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("", selection: Binding(
                    get: { store.selectedModel(for: provider) },
                    set: { store.setSelectedModel($0, for: provider) }
                )) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(ManatherTheme.ink)
            }
        }
    }

    // MARK: Footer (test + set default)

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.test(provider) }
            } label: {
                Label("Test connection", systemImage: "bolt.horizontal")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SettingsButtonStyle(prominent: false, enabled: store.isConfigured(provider)))
            .disabled(!store.isConfigured(provider))

            if case .failure(let msg) = store.result(for: provider) {
                Text(msg).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
            }

            Spacer()

            Button {
                store.defaultProviderID = isDefault ? nil : provider.id
            } label: {
                Text(isDefault ? "✓ Default" : "Set as default")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SettingsButtonStyle(prominent: isDefault, enabled: store.isConfigured(provider)))
            .disabled(!store.isConfigured(provider))
        }
    }
}

// MARK: - CLI Agents

struct CLIAgentsSettingsView: View {
    let detector: CLIAgentDetector
    @AppStorage("ai.defaultCLIAgent") private var defaultAgentID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Terminal coding agents installed on this Mac. The default one is pre-selected when you export a build pack.")
                    .font(.system(size: 12)).foregroundStyle(ManatherTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { detector.detectAll() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(ManatherTheme.accent).help("Re-scan")
            }

            ForEach(CLIAgent.all) { agent in
                CLIAgentRow(agent: agent, status: detector.status(for: agent),
                            isDefault: defaultAgentID == agent.id,
                            onSetDefault: { defaultAgentID = (defaultAgentID == agent.id ? "" : agent.id) })
            }
        }
        .onAppear { if detector.statuses.isEmpty { detector.detectAll() } }
    }
}

private struct CLIAgentRow: View {
    let agent: CLIAgent
    let status: CLIStatus
    let isDefault: Bool
    let onSetDefault: () -> Void

    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "terminal").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ManatherTheme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(agent.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(ManatherTheme.ink)
                        if agent.isLegacy {
                            Text("LEGACY").font(.system(size: 8, weight: .bold)).foregroundStyle(ManatherTheme.mutedInk)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(ManatherTheme.mutedInk.opacity(0.15)))
                        }
                    }
                    Text(agent.summary).font(.system(size: 11)).foregroundStyle(ManatherTheme.mutedInk)
                }
                Spacer()
                statusView
            }

            if case .installed = status {
                Button { onSetDefault() } label: {
                    Text(isDefault ? "✓ Default agent" : "Set as default")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SettingsButtonStyle(prominent: isDefault, enabled: true))
            } else if case .notFound = status {
                VStack(alignment: .leading, spacing: 6) {
                    commandRow(label: "Install", command: agent.installCommand)
                    commandRow(label: "Sign in", command: agent.authCommand)
                    Link("Docs ↗", destination: URL(string: agent.docsURL)!)
                        .font(.system(size: 11)).foregroundStyle(ManatherTheme.accent)
                }
            }
        }
        .padding(14)
        .background(SettingsStyle.card(isDarkMode))
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .installed(let version, _):
            Label(version, systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green).lineLimit(1)
        case .detecting, .unknown:
            ProgressView().controlSize(.small)
        case .notFound:
            Text("Not found").font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
        }
    }

    private func commandRow(label: String, command: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(ManatherTheme.mutedInk)
                .frame(width: 44, alignment: .leading)
            Text(command).font(.system(size: 11, design: .monospaced)).foregroundStyle(ManatherTheme.ink)
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(ManatherTheme.mutedInk)
            }.buttonStyle(.plain).help("Copy")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(SettingsStyle.field(isDarkMode))
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manather").font(.system(size: 18, weight: .bold)).foregroundStyle(ManatherTheme.ink)
            Text("Version \(version)").font(.system(size: 12)).foregroundStyle(ManatherTheme.mutedInk)
            Text("A personal library of references, skills, MCP servers and snippets for vibe-coders — exportable as build packs your AI agent can start from.")
                .font(.system(size: 12)).foregroundStyle(ManatherTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
    }
}

// MARK: - Shared styling

enum SettingsStyle {
    static func card(_ dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(dark ? Color.white.opacity(0.04) : Color.white.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ManatherTheme.hairline, lineWidth: 1))
    }

    static func field(_ dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ManatherTheme.hairline, lineWidth: 1))
    }

    static func sectionHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(ManatherTheme.mutedInk)
            .textCase(.uppercase).tracking(0.6).padding(.top, 4)
    }

    static func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(ManatherTheme.mutedInk)
            .textCase(.uppercase).tracking(0.5)
    }

    static func actionRow(icon: String, title: String, subtitle: String,
                          destructive: Bool = false, action: @escaping () -> Void) -> some View {
        ActionRow(icon: icon, title: title, subtitle: subtitle, destructive: destructive, action: action)
    }
}

private struct ActionRow: View {
    let icon: String, title: String, subtitle: String
    let destructive: Bool
    let action: () -> Void
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(destructive ? .red : ManatherTheme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(destructive ? .red : ManatherTheme.ink)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(ManatherTheme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(ManatherTheme.mutedInk)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hover ? (isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    let prominent: Bool
    let enabled: Bool
    @AppStorage("isDarkMode") private var isDarkMode = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? .white : (enabled ? ManatherTheme.ink : ManatherTheme.mutedInk))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? ManatherTheme.accent
                          : (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
