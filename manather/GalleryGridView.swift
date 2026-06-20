//
//  GalleryGridView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum SidebarCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case unsorted = "Unsorted"
    case trash = "Trash"
    var id: String { rawValue }
}

enum MainTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case collections = "Collections"
    case spaces = "Boards" // third tab now shows the user's boards collection
                           // (the Projects grid code is parked for later reuse)

    var id: String { rawValue }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case mostRecent = "Most recent"
    case oldestFirst = "Oldest first"
    case nameAZ = "Name A-Z"
    case nameZA = "Name Z-A"

    var id: String { rawValue }
}

/// The asset whose custom context menu is open, plus the card's frame (in the
/// gallery coordinate space) used to position the menu.
struct ContextTarget {
    let asset: AssetItem
    let frame: CGRect
}

/// A pending collection export: which collection, its assets and the chosen
/// target. Held while the goal sheet is shown, then handed to ContextPackExporter.
struct PendingExport: Identifiable {
    let id = UUID()
    let name: String
    let assets: [AssetItem]
    let target: ExportTarget
}

struct GalleryGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale
    let assets: [AssetItem]
    @Binding var selectedCategory: SidebarCategory
    @Binding var selectedAsset: AssetItem?
    @Binding var searchText: String
    @Binding var columnCount: Double
    @Binding var isImporting: Bool
    let animationNamespace: Namespace.ID

    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var selectedTab: MainTab = .library
    @State private var activeCollectionFilter: String? = nil
    @State private var activeColorFilter: BaseColor? = nil
    @State private var showSettings = false
    @State private var sortOrder: SortOrder = .mostRecent
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var assetToDelete: AssetItem? = nil
    @State private var showDeleteConfirmation = false

    @State private var contextTarget: ContextTarget?
    /// Whether the custom "+" (add) menu is open.
    @State private var showAddMenu = false
    /// Whether the "Library ▾" switcher menu is open.
    @State private var showLibraryMenu = false

    // Boards tab: all boards the user created (across projects).
    @Query(sort: \Board.dateModified, order: .reverse) private var allBoards: [Board]
    @State private var openBoard: Board?
    @State private var showNewBoardSheet = false

    @Query(sort: \AssetCollection.dateAdded, order: .reverse) private var savedCollections: [AssetCollection]
    @State private var showNewCollectionSheet = false

    // Libraries the user can switch between (the "Library ▾" menu). The active
    // one is mirrored in AppStorage so model code can read it too.
    @Query(sort: \Library.dateCreated) private var libraries: [Library]
    @AppStorage("activeLibraryID") private var activeLibraryIDString: String = ""
    /// When set, the Collections tab shows this collection's contents in-place
    /// (a dedicated browse screen) instead of the grid of collection folders.
    @State private var openCollection: String? = nil

    @State private var isDropTargeted = false
    @State private var showWebLinkSheet = false
    @State private var showCodeSnippetSheet = false
    @State private var showMCPServerSheet = false
    @State private var showSkillSheet = false

    // A collection export awaiting its goal sheet (set from the export menus).
    @State private var pendingExport: PendingExport?

    private var isTrashView: Bool {
        selectedCategory == .trash
    }

    // MARK: - Active library

    private var activeLibraryID: UUID? { UUID(uuidString: activeLibraryIDString) }

    /// Collections belonging to the active library (before seeding, when no id is
    /// set, fall back to all so nothing disappears).
    private var activeCollections: [AssetCollection] {
        guard let id = activeLibraryID else { return savedCollections }
        return savedCollections.filter { $0.libraryID == id }
    }

    private var currentLibraryName: String {
        libraries.first { $0.id == activeLibraryID }?.name ?? libraries.first?.name ?? "Library"
    }

    // Computed once per render from the full asset list — passed into cards to avoid per-card @Query
    private var allCollections: [String] {
        Array(Set(assets.filter { !$0.isDeleted && !$0.isTrash }.flatMap { $0.collectionNames })).sorted()
    }

    /// The canonical list of every collection: real `AssetCollection` objects
    /// (including empty ones) plus any legacy names still living only on assets.
    private var collectionNames: [String] {
        Set(activeCollections.map(\.name)).union(allCollections).sorted()
    }

    /// Live assets belonging to `name` ("Unassigned" = saves not in any
    /// collection), newest first.
    private func assets(inCollection name: String) -> [AssetItem] {
        let live = assets.filter { !$0.isDeleted && !$0.isTrash }
        let items = name == "Unassigned"
            ? live.filter { $0.isUnassigned }
            : live.filter { $0.inCollection(name) }
        return items.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Assets of the collection currently open in the Collections tab.
    private var openCollectionAssets: [AssetItem] {
        guard let name = openCollection else { return [] }
        return assets(inCollection: name)
    }

    private var categoryAssets: [AssetItem] {
        switch selectedCategory {
        case .all:
            return assets.filter { !$0.isTrash }
        case .unsorted:
            return assets.filter { !$0.isTrash && $0.isUnassigned }
        case .trash:
            return assets.filter { $0.isTrash }
        }
    }

    private var filteredAssets: [AssetItem] {
        var items = categoryAssets

        if let collectionFilter = activeCollectionFilter {
            items = items.filter { $0.inCollection(collectionFilter) }
        }

        if let colorFilter = activeColorFilter {
            items = items.filter { asset in
                guard let hexes = asset.dominantColorsHex, !hexes.isEmpty else { return false }
                return ColorIndex.buckets(forHexes: hexes).contains(colorFilter)
            }
        }

        let filtered: [AssetItem]
        if searchText.isEmpty {
            filtered = items
        } else {
            let query = searchText.lowercased()
            filtered = items.filter {
                $0.title.lowercased().contains(query) ||
                $0.prompt.lowercased().contains(query) ||
                $0.notes.lowercased().contains(query) ||
                ($0.codeContent?.lowercased().contains(query) ?? false) ||
                $0.tags.contains { $0.lowercased().contains(query) }
            }
        }
        
        switch sortOrder {
        case .mostRecent:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .oldestFirst:
            return filtered.sorted { $0.dateAdded < $1.dateAdded }
        case .nameAZ:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameZA:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    /// Distributes items across columns for masonry layout (shortest column first)
    private func distributeToColumns(_ items: [AssetItem], availableWidth: CGFloat) -> [[AssetItem]] {
        let baseCount = max(1, Int(columnCount))
        // Target about 160pt minimum width per column to prevent squishing
        let maxColumnsForWidth = max(1, Int(availableWidth / 160))
        let count = min(baseCount, maxColumnsForWidth)

        var columns = Array(repeating: [AssetItem](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for item in items {
            let minIndex = heights.enumerated()
                .min(by: { $0.element < $1.element })!.offset
            columns[minIndex].append(item)
            
            // Adjust height calculations for aspect ratio
            let ratio = item.aspectRatio
            heights[minIndex] += 1.0 / ratio
        }

        return columns
    }

    var body: some View {
        // Compute the filtered + sorted list once per render and reuse it for the
        // empty check, the grid layout and the detail view. Previously each of
        // those re-ran the whole filter+sort, and the grid did it again on every
        // layout pass (e.g. while resizing the window) — the main source of lag.
        let visibleAssets = filteredAssets
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Top toolbar
                topBar

                // Content
                ZStack {
                    if selectedTab == .library {
                        Group {
                            if visibleAssets.isEmpty {
                                emptyStateView
                            } else {
                                VStack(spacing: 0) {
                                    filterBadgeBar
                                    masonryGrid(visibleAssets)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    } else if selectedTab == .collections {
                        Group {
                            if let name = openCollection {
                                collectionDetailView(name)
                            } else {
                                collectionsGrid
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    } else {
                        boardsGrid
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Floating Add Button (FAB)
            if !isTrashView {
                addFAB
                    .padding(.trailing, 28)
                    .padding(.bottom, 28)
            }

            if selectedAsset != nil {
                AssetDetailView(
                    selectedAsset: $selectedAsset,
                    assets: openCollection != nil ? openCollectionAssets : visibleAssets
                )
                // Smooth zoom-in/out instead of a flat fade.
                .transition(.scale(scale: 0.93).combined(with: .opacity))
            }

            // Custom right-click context menu (dark panel + dimmed backdrop)
            if let target = contextTarget {
                contextMenuOverlay(target)
            }

            // Custom "+" add menu (same style as the right-click menu).
            if showAddMenu {
                addMenuOverlay
                    .zIndex(12)
            }

            // Custom "Library ▾" switcher menu (same styled panel).
            if showLibraryMenu {
                libraryMenuOverlay
                    .zIndex(13)
            }

            // Settings — centered modal window.
            if showSettings {
                settingsOverlay
                    .zIndex(13)
            }

            // A board opened from the Boards tab.
            if let board = openBoard {
                BoardView(board: board) {
                    withAnimation(ManatherTheme.overlayMotion) {
                        openBoard = nil
                    }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(11)
            }
        }
        .coordinateSpace(name: "gallerySpace")
        .onChange(of: selectedTab) { _, _ in
            // Leaving (or re-entering) the Collections tab returns to the folder list.
            openCollection = nil
        }
        .focusEffectDisabled()
        .overlay(
            // Drop target overlay
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ManatherTheme.accent.opacity(0.85), lineWidth: 2)
                .padding(14)
                .opacity(isDropTargeted ? 1 : 0)
                .scaleEffect(isDropTargeted ? 1.01 : 1.0)
                .animation(ManatherTheme.uiMotion, value: isDropTargeted)
        )
        .onDrop(of: [.image, .movie, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        // ⌘V — smart-paste whatever is on the clipboard straight into the library.
        // Fires only when a text field isn't the paste target, so search/inputs
        // keep their own paste behaviour.
        .onPasteCommand(of: [UTType.fileURL, UTType.image, UTType.url, UTType.plainText]) { _ in
            AssetIngest.ingestPasteboard(.general, into: modelContext)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .movie, .text, .sourceCode, .json],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
        .sheet(isPresented: $showWebLinkSheet) {
            AddWebLinkSheet()
        }
        .sheet(isPresented: $showCodeSnippetSheet) {
            AddCodeSnippetSheet()
        }
        .sheet(isPresented: $showMCPServerSheet) {
            AddMCPServerSheet()
        }
        .sheet(isPresented: $showSkillSheet) {
            AddSkillSheet()
        }
        .sheet(isPresented: $showNewBoardSheet) {
            NewBoardSheet(projectName: "") { newBoard in
                withAnimation(ManatherTheme.overlayMotion) { openBoard = newBoard }
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewCollectionSheet(existingNames: collectionNames) { _ in }
        }
        .sheet(item: $pendingExport) { pending in
            ExportGoalSheet(target: pending.target, collectionName: pending.name, assets: pending.assets) { goal, gitInit in
                ContextPackExporter.export(
                    projectName: pending.name,
                    assets: pending.assets,
                    target: pending.target,
                    goal: goal,
                    gitInit: gitInit
                )
            }
        }
        .onAppear {
            // Make sure a library exists and is active before any seeding below,
            // so new collection objects get stamped with the right library.
            LibraryManager.ensureActive(context: modelContext)
            let pendingLinks = assets.filter { $0.assetType == .webLink && $0.relativeFilePath.isEmpty }
            for asset in pendingLinks {
                WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: modelContext)
            }
            // Backfill palette data so color filtering works for older imports
            ColorIndexer.shared.backfill(assets: assets.filter { !$0.isTrash })
            // Projects were merged into Collections — fold any old project tag
            // into a collection of the same name (one-time, idempotent).
            mergeProjectsIntoCollections()
            // Backfill multi-collection membership for assets saved before it existed.
            migrateToMultiCollections()
            // Turn any collection names still living only on assets into real
            // AssetCollection objects, so they can be managed like the rest.
            seedCollectionsFromAssets()
        }
        .onChange(of: activeLibraryIDString) { _, _ in
            resetLibraryViewState()
        }
        .confirmationDialog(
            "Are you sure you want to permanently delete \"\(assetToDelete?.title ?? "")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let asset = assetToDelete {
                    deleteAssetPermanently(asset)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone and the file will be deleted from your disk.")
        }
        .background(
            Group {
                Button("") {
                    expandSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("") {
                    withAnimation(ManatherTheme.uiMotion) {
                        selectedTab = .library
                    }
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("") {
                    withAnimation(ManatherTheme.uiMotion) {
                        selectedTab = .collections
                    }
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("") {
                    withAnimation(ManatherTheme.uiMotion) {
                        selectedTab = .spaces
                    }
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("") {
                    if let asset = selectedAsset {
                        if isTrashView {
                            assetToDelete = asset
                            showDeleteConfirmation = true
                        } else {
                            moveAssetToTrash(asset)
                        }
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .center) {
                // Left & Right
                HStack(alignment: .center) {
                    brandMark
                    Spacer()
                    if !isTrashView { rightToolbarIcons }
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)

                // Center (Segmented Control)
                topSegmentedControl
            }
            .padding(.top, ManatherTheme.titleBarInset)
            .padding(.bottom, 14)
            
            // Row 2: Tabs and Filters — library-only. Categories (All / Unsorted /
            // Trash) and the color/column/sort controls don't apply to Collections
            // or Boards, so the whole row is hidden there.
            if selectedTab == .library {
                HStack(alignment: .center) {
                    categoryTabs

                    Spacer()

                    controlCluster
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var brandMark: some View {
        HStack(spacing: 12) {
            Image("BrandIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            libraryMenu


            // Collapsed search — icon only, expands on click (matches GatherOS)
            if isSearchExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 150)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if searchText.isEmpty { collapseSearch() }
                        }
                        .onKeyPress(.escape) {
                            searchText = ""
                            collapseSearch()
                            return .handled
                        }

                    Button {
                        searchText = ""
                        collapseSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.hairline, lineWidth: 1)
                        )
                )
                .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            } else {
                Button {
                    expandSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Search (⌘F)")
            }
        }
    }

    // MARK: - Library switcher

    /// The "Library ▾" button. Opens a custom styled menu (see libraryMenuOverlay)
    /// instead of a native Menu — that's what removes the blue focus ring and lets
    /// the dropdown match the app's add/right-click menus.
    private var libraryMenu: some View {
        Button {
            withAnimation(ManatherTheme.menuMotion) { showLibraryMenu.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text(currentLibraryName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    /// Dimmed backdrop + the styled library menu, anchored under the brand mark.
    private var libraryMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeLibraryMenu() }

            LibraryMenuView(
                isDarkMode: isDarkMode,
                libraries: libraries,
                activeID: activeLibraryID,
                onSelect: { switchLibrary(to: $0) },
                onNewLibrary: { createLibrary() },
                onImport: { importLibrary() },
                onDismiss: { closeLibraryMenu() }
            )
            // Sit just below the "My Library" label (brand icon + spacing).
            .padding(.leading, 56)
            .padding(.top, ManatherTheme.titleBarInset + 44)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
        }
        .onExitCommand { closeLibraryMenu() }
    }

    private func closeLibraryMenu() {
        withAnimation(ManatherTheme.menuMotion) { showLibraryMenu = false }
    }

    private func switchLibrary(to library: Library) {
        guard library.id != activeLibraryID else { return }
        LibraryManager.setActive(library.id)
        // View-state reset is handled centrally by onChange(activeLibraryIDString)
        // so it runs no matter where the switch came from (this menu or Settings).
    }

    /// Drop any view state tied to the library we're leaving. Fires for every
    /// switch path — the "Library ▾" menu and the Libraries settings tab.
    private func resetLibraryViewState() {
        activeCollectionFilter = nil
        activeColorFilter = nil
        openCollection = nil
        selectedAsset = nil
        selectedTab = .library
    }

    /// Create a brand-new empty library and switch to it (from the "Library ▾" menu).
    private func createLibrary() {
        let lib = Library(name: LibraryManager.uniqueName("New Library", context: modelContext))
        modelContext.insert(lib)
        switchLibrary(to: lib)
    }

    /// Pick a `.zip` exported from Manather and rebuild it as a new library, then
    /// switch to it. Uses a modal panel so the work stays on the main actor.
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
            switchLibrary(to: library)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func expandSearch() {
        withAnimation(ManatherTheme.uiMotion) {
            isSearchExpanded = true
        }
        // Focus after the field exists in the hierarchy
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func collapseSearch() {
        isSearchFocused = false
        withAnimation(ManatherTheme.uiMotion) {
            isSearchExpanded = false
        }
    }

    private var topSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                let isSelected = selectedTab == tab
                
                let textColor: Color = {
                    if isSelected {
                        return isDarkMode ? Color.black : Color.white
                    } else {
                        return isDarkMode ? Color.white.opacity(0.8) : Color.black.opacity(0.7)
                    }
                }()

                Button {
                    withAnimation(ManatherTheme.uiMotion) {
                        selectedTab = tab
                    }
                } label: {
                    tabLabel(for: tab)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            // The active capsule is a single shared shape that
                            // slides between tabs instead of popping in place.
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(isDarkMode ? Color.white : Color.black)
                                        .matchedGeometryEffect(id: "activeTabCapsule", in: animationNamespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tabLabel(for tab: MainTab) -> some View {
        HStack(spacing: 7) {
            switch tab {
            case .library:
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 11, weight: .semibold))
            case .collections:
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
            case .spaces:
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(tab.rawValue)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private var rightToolbarIcons: some View {
        HStack(spacing: 6) {
            toolbarIconButton(icon: isDarkMode ? "sun.max.fill" : "moon", tooltip: "Toggle Dark Mode") {
                withAnimation(ManatherTheme.uiMotion) {
                    isDarkMode.toggle()
                }
            }
            toolbarIconButton(icon: "gearshape", tooltip: "Settings") {
                withAnimation(ManatherTheme.overlayMotion) { showSettings.toggle() }
            }
        }
    }

    /// Dimmed backdrop + the centered settings window. Clicking the backdrop or
    /// pressing Esc closes it; clicks on the card itself are absorbed by it.
    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeSettings() }

            SettingsView(
                onLoadDemo: { loadDemoAssets() },
                onClearCache: { ImageCache.shared.clearAll() },
                onImportClaude: { ClaudeImporter.importAll(into: modelContext).summary },
                onDismiss: { closeSettings() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func closeSettings() {
        withAnimation(ManatherTheme.overlayMotion) { showSettings = false }
    }

    private func toolbarIconButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.48))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func loadDemoAssets() {
        let snippet = AssetItem(
            title: "Standard QuickSort",
            relativeFilePath: "",
            prompt: "QuickSort algorithm implemented in Swift 6.2",
            notes: "Useful reference for sorting arrays in Swift",
            typeRaw: "codeSnippet",
            codeLanguage: "Swift",
            codeContent: "func quickSort<T: Comparable>(_ array: [T]) -> [T] {\n    guard array.count > 1 else { return array }\n    let pivot = array[array.count / 2]\n    let less = array.filter { $0 < pivot }\n    let equal = array.filter { $0 == pivot }\n    let greater = array.filter { $0 > pivot }\n    return quickSort(less) + equal + quickSort(greater)\n}",
            collectionName: "Typography",
            spaceName: "Mobile App"
        )
        
        let link1 = AssetItem(
            title: "Apple Developer Documentation",
            relativeFilePath: "",
            sourceURL: "https://developer.apple.com",
            prompt: "Apple portal for developers",
            notes: "WWDC documentation, API references, and Human Interface Guidelines",
            typeRaw: "webLink",
            collectionName: "Branding",
            spaceName: "Design System"
        )
        
        let link2 = AssetItem(
            title: "SwiftUI tutorials",
            relativeFilePath: "",
            sourceURL: "https://developer.apple.com/xcode/swiftui/",
            prompt: "Learn SwiftUI",
            notes: "Official Apple tutorials and layout patterns",
            typeRaw: "webLink",
            collectionName: "Branding",
            spaceName: "Design System"
        )
        
        modelContext.insert(snippet)
        modelContext.insert(link1)
        modelContext.insert(link2)
        
        try? modelContext.save()
    }

    // MARK: - Floating Add Button

    @State private var isFABHovered = false

    private var addFAB: some View {
        Button {
            withAnimation(ManatherTheme.menuMotion) { showAddMenu.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(isDarkMode ? Color.white : Color.black)
                    .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.black : Color.white)
                    // Spin into an "×" while the menu is open.
                    .rotationEffect(.degrees(showAddMenu ? 45 : 0))
            }
            .frame(width: 58, height: 58)
            .scaleEffect(isFABHovered ? 1.06 : 1.0)
            .animation(ManatherTheme.microMotion, value: isFABHovered)
            .animation(ManatherTheme.menuMotion, value: showAddMenu)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            isFABHovered = hovering
        }
    }

    /// Dimmed backdrop + custom add menu anchored just above the FAB.
    private var addMenuOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeAddMenu() }

            AddMenuView(
                isDarkMode: isDarkMode,
                onDismiss: { closeAddMenu() },
                onImport: { isImporting = true },
                onWebLink: { showWebLinkSheet = true },
                onCodeSnippet: { showCodeSnippetSheet = true },
                onSkill: { showSkillSheet = true },
                onMCPServer: { showMCPServerSheet = true }
            )
            // Sit above the 58pt FAB (28pt bottom inset + height + gap).
            .padding(.trailing, 28)
            .padding(.bottom, 28 + 58 + 12)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
        }
        .onExitCommand { closeAddMenu() }
    }

    private func closeAddMenu() {
        withAnimation(ManatherTheme.menuMotion) { showAddMenu = false }
    }

    private var categoryTabs: some View {
        HStack(spacing: 28) {
            ForEach(SidebarCategory.allCases) { category in
                let isSelected = selectedCategory == category
                Button {
                    withAnimation(ManatherTheme.uiMotion) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.rawValue)
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.38))
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            // The underline is a single shared shape that glides
                            // to the selected category instead of blinking on/off.
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary)
                                    .frame(height: 2.5)
                                    .matchedGeometryEffect(id: "categoryUnderline", in: animationNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterBadgeBar: some View {
        Group {
            if activeCollectionFilter != nil || activeColorFilter != nil {
                HStack(spacing: 8) {
                    Text("Filters:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.black.opacity(0.4))

                    if let col = activeCollectionFilter {
                        filterBadge(text: "Collection: \(col)") {
                            activeCollectionFilter = nil
                        }
                    }

                    if let colorF = activeColorFilter {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorF.swatch)
                                .frame(width: 9, height: 9)
                            Text(colorF.label)
                                .font(.system(size: 11, weight: .medium))
                            Button {
                                withAnimation(ManatherTheme.uiMotion) {
                                    activeColorFilter = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.clear)
            }
        }
    }

    private func filterBadge(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(isDarkMode ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
        )
    }

    private var collectionsGrid: some View {
        // An asset can belong to several collections, so each named bucket is built
        // from membership rather than a single grouping key. Loose (uncollected)
        // saves go into "Unassigned".
        let live = assets.filter { !$0.isDeleted && !$0.isTrash }
        let names = collectionNames // real collections (incl. empty) + legacy names
        let unassigned = live.filter { $0.isUnassigned }
        let columns = [GridItem(.adaptive(minimum: 184, maximum: 240), spacing: 22)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                // Create a new (possibly empty) collection.
                Button {
                    showNewCollectionSheet = true
                } label: {
                    newCollectionCard
                        .hoverLift()
                }
                .buttonStyle(.plain)

                // Every real collection, including empty ones.
                ForEach(names, id: \.self) { name in
                    let items = live.filter { $0.inCollection(name) }
                    Button {
                        withAnimation(ManatherTheme.uiMotion) { openCollection = name }
                    } label: {
                        CollectionFolderCard(title: name, count: items.count, items: items, isDarkMode: isDarkMode)
                            .hoverLift()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Menu {
                            ForEach(ExportTarget.allCases) { target in
                                Button(target.menuLabel) {
                                    pendingExport = PendingExport(name: name, assets: items, target: target)
                                }
                            }
                        } label: {
                            Label("Export for…", systemImage: "shippingbox.and.arrow.backward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deleteCollection(name)
                        } label: {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    }
                }

                // Loose saves that aren't in any collection (shown last, read-only).
                if !unassigned.isEmpty {
                    Button {
                        withAnimation(ManatherTheme.uiMotion) { openCollection = "Unassigned" }
                    } label: {
                        CollectionFolderCard(title: "Unassigned", count: unassigned.count, items: unassigned, isDarkMode: isDarkMode)
                            .hoverLift()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    /// Dashed "+" card that opens the new-collection sheet. Mirrors the "New
    /// board" card so the two tabs feel the same.
    private var newCollectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .frame(height: 150)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(ManatherTheme.accent)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text("New collection")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                Text("Group saves together")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Collection detail (browse inside one collection)

    @ViewBuilder
    private func collectionDetailView(_ name: String) -> some View {
        let items = openCollectionAssets
        let isUnassigned = name == "Unassigned"

        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    withAnimation(ManatherTheme.uiMotion) { openCollection = nil }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Collections")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(ManatherTheme.mutedInk)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.microAnimated)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // Title row + actions
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isUnassigned ? "tray" : "folder.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text(name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ManatherTheme.ink)
                Text("\(items.count) \(items.count == 1 ? "save" : "saves")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ManatherTheme.mutedInk)

                Spacer()

                if !isUnassigned {
                    Menu {
                        Menu {
                            ForEach(ExportTarget.allCases) { target in
                                Button(target.menuLabel) {
                                    pendingExport = PendingExport(name: name, assets: items, target: target)
                                }
                            }
                        } label: {
                            Label("Export for…", systemImage: "shippingbox.and.arrow.backward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deleteCollection(name)
                            withAnimation(ManatherTheme.uiMotion) { openCollection = nil }
                        } label: {
                            Label("Delete Collection", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ManatherTheme.mutedInk)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            if items.isEmpty {
                collectionEmptyState
            } else {
                masonryGrid(items, showsCollectionRow: false)
            }
        }
    }

    private var collectionEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ManatherTheme.mutedInk.opacity(0.42))
            Text("This collection is empty")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ManatherTheme.ink.opacity(0.72))
            Text("Right-click any save in your library → Add to Collection")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ManatherTheme.mutedInk.opacity(0.70))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Boards tab

    private var boardsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                Button {
                    showNewBoardSheet = true
                } label: {
                    newBoardCard
                        .hoverLift()
                }
                .buttonStyle(.plain)

                ForEach(allBoards) { board in
                    Button {
                        withAnimation(ManatherTheme.overlayMotion) { openBoard = board }
                    } label: {
                        boardCard(board)
                            .hoverLift()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            duplicateBoard(board)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Divider()
                        Button(role: .destructive) {
                            if openBoard?.id == board.id { openBoard = nil }
                            modelContext.delete(board)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var newBoardCard: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .frame(height: 120)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(ManatherTheme.accent)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text("New board")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                Text("Start a mood-board canvas")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func boardCard(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            boardPreviewArea(board)

            VStack(alignment: .leading, spacing: 3) {
                Text(board.title.isEmpty ? "Untitled board" : board.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                    .lineLimit(1)

                Text("\(board.items.count) item\(board.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    /// Thumbnail area for a board card.
    /// Uses up to 3 images already on the board (cheap — same cached thumbnails).
    /// Falls back to a content-type summary, then an empty hint.
    @ViewBuilder
    private func boardPreviewArea(_ board: Board) -> some View {
        let imagePaths: [String] = board.items
            .filter { $0.kind == .image }
            .compactMap { item -> String? in
                guard let id = item.assetID,
                      let asset = assets.first(where: { $0.id == id }),
                      !asset.relativeFilePath.isEmpty else { return nil }
                return asset.relativeFilePath
            }
            .prefix(3)
            .map { $0 }

        ZStack {
            // Dark base (always visible behind images / in empty state)
            ManatherTheme.viewerBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !imagePaths.isEmpty {
                boardImageCollage(imagePaths)
            } else {
                boardNoImageHint(board)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    /// 1 image → full bleed.  2 → side-by-side.  3 → left large + right column.
    @ViewBuilder
    private func boardImageCollage(_ paths: [String]) -> some View {
        switch paths.count {
        case 1:
            CachedImageView(relativePath: paths[0], maxSize: 400, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case 2:
            HStack(spacing: 2) {
                ForEach(paths, id: \.self) { path in
                    CachedImageView(relativePath: path, maxSize: 250, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }

        default: // 3+
            HStack(spacing: 2) {
                CachedImageView(relativePath: paths[0], maxSize: 300, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                VStack(spacing: 2) {
                    CachedImageView(relativePath: paths[1], maxSize: 200, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    CachedImageView(relativePath: paths[2], maxSize: 200, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Shown when there are no image items — summarises content types with icons.
    @ViewBuilder
    private func boardNoImageHint(_ board: Board) -> some View {
        if board.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
                Text("Empty board")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
        } else {
            let noteCount  = board.items.filter { $0.kind == .note || $0.kind == .text  }.count
            let shapeCount = board.items.filter { $0.kind == .shape || $0.kind == .frame }.count

            HStack(spacing: 20) {
                if noteCount > 0 {
                    boardHintItem(icon: "note.text", count: noteCount)
                }
                if shapeCount > 0 {
                    boardHintItem(icon: "square.on.circle", count: shapeCount)
                }
            }
        }
    }

    private func boardHintItem(icon: String, count: Int) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.42))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))
        }
    }

    /// Projects were merged into Collections: move any old project tag into a
    /// collection of the same name, then clear the project field. Idempotent.
    private func mergeProjectsIntoCollections() {
        for asset in assets where asset.spaceName != nil {
            if let space = asset.spaceName, !space.isEmpty {
                asset.addToCollection(space)
            }
            asset.spaceName = nil
        }
    }

    /// One-time backfill: assets persisted before many-to-many only carry the
    /// single `collectionName`. Lift it into `collectionNames`. Idempotent.
    private func migrateToMultiCollections() {
        for asset in assets where asset.collectionNames.isEmpty {
            if let name = asset.collectionName, !name.isEmpty {
                asset.collectionNames = [name]
            }
        }
    }

    /// Promote any collection name that only lives on an asset into a real
    /// AssetCollection object, so older libraries gain manageable collections.
    /// Idempotent — safe to run on every launch.
    private func seedCollectionsFromAssets() {
        let existing = Set(activeCollections.map(\.name))
        let fromAssets = Set(assets.filter { !$0.isDeleted }.flatMap { $0.collectionNames })
        for name in fromAssets where !existing.contains(name) {
            modelContext.insert(AssetCollection(name: name))
        }
    }

    /// Create a collection object for `name` if one doesn't already exist
    /// (case-insensitive). Used by the right-click "New collection…" flow.
    private func createCollectionEntity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = activeCollections.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !exists {
            modelContext.insert(AssetCollection(name: trimmed))
        }
    }

    /// Delete a collection. Assets in it aren't deleted — they just fall back to
    /// "Unassigned" (so nothing is lost).
    private func deleteCollection(_ name: String) {
        for asset in assets where asset.inCollection(name) {
            asset.removeFromCollection(name)
        }
        for collection in activeCollections where collection.name == name {
            modelContext.delete(collection)
        }
        if activeCollectionFilter == name {
            activeCollectionFilter = nil
        }
    }

    private func duplicateBoard(_ board: Board) {
        let copy = Board(
            title: board.title + " copy",
            details: board.details,
            projectName: board.projectName,
            cameraX: board.cameraX,
            cameraY: board.cameraY,
            zoom: board.zoom
        )
        modelContext.insert(copy)
        for item in board.items {
            let newItem = BoardItem(
                kind: item.kind,
                x: item.x,
                y: item.y,
                width: item.width,
                height: item.height,
                zIndex: item.zIndex,
                assetID: item.assetID,
                text: item.text,
                fillColorHex: item.fillColorHex,
                shapeKind: item.shapeKindRaw == nil ? nil : item.shapeKind,
                frameTitle: item.frameTitle
            )
            newItem.board = copy
            modelContext.insert(newItem)
        }
    }

    private var controlCluster: some View {
        HStack(spacing: 18) {
            colorFilterRow

            Slider(value: Binding(
                get: { columnCount },
                set: { newValue in
                    withAnimation(ManatherTheme.uiMotion) {
                        columnCount = newValue
                    }
                }
            ), in: 2...6, step: 1)
                .frame(width: 70)
                .controlSize(.small)
                .tint(isDarkMode ? Color.white.opacity(0.4) : Color.black.opacity(0.3))

            sortMenu
        }
    }

    // MARK: - Color Filter Swatches

    private var colorFilterRow: some View {
        HStack(spacing: 7) {
            ForEach(BaseColor.allCases) { base in
                ColorFilterSwatch(
                    base: base,
                    isActive: activeColorFilter == base,
                    isDimmed: activeColorFilter != nil && activeColorFilter != base
                ) {
                    withAnimation(ManatherTheme.uiMotion) {
                        activeColorFilter = (activeColorFilter == base) ? nil : base
                    }
                }
            }

            if activeColorFilter != nil {
                Button {
                    withAnimation(ManatherTheme.uiMotion) {
                        activeColorFilter = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .help("Clear color filter")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.white.opacity(0.55))
                .overlay(
                    Capsule().stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases) { order in
                Button(order.rawValue) {
                    sortOrder = order
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sortOrder.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
    }

    // MARK: - Masonry Grid

    /// Pixel size for the thumbnail's longest edge so the card's WIDTH renders
    /// crisply. `kCGImageSourceThumbnailMaxPixelSize` caps the LONGEST side, but
    /// the masonry column constrains width — so a tall image needs a larger cap
    /// (its height) to avoid being upscaled and looking soft. Landscape images
    /// keep a small cap, so memory stays proportional to the pixels we actually
    /// show. The result is quantized into a few buckets so the thumbnail cache
    /// stays reusable instead of regenerating on every tiny resize.
    private func thumbnailMaxSize(colWidth: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        let widthPx = colWidth * displayScale
        // Longest side in pixels: width for landscape, height (= widthPx / ar) for portrait.
        let longestPx = widthPx * max(1, 1 / max(aspectRatio, 0.01))
        let buckets: [CGFloat] = [300, 500, 800, 1200, 1600, 2200, 3000]
        return buckets.first(where: { $0 >= longestPx }) ?? buckets.last!
    }

    private func masonryGrid(_ items: [AssetItem], showsCollectionRow: Bool = true) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 14
            let columns = distributeToColumns(items, availableWidth: geometry.size.width)
            
            // Calculate column width in points
            let colWidth = max(100, (geometry.size.width - CGFloat(columns.count - 1) * spacing - 40) / CGFloat(columns.count))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                // Collection stack cards (only on "All", no filters/search)
                if showsCollectionRow && selectedCategory == .all && activeCollectionFilter == nil
                    && searchText.isEmpty && !allCollections.isEmpty {
                    collectionStackRow
                }

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns.count, id: \.self) { colIndex in
                        LazyVStack(spacing: spacing) {
                            ForEach(columns[colIndex]) { asset in
                                AssetCardView(
                                    asset: asset,
                                    isSelected: selectedAsset?.id == asset.id,
                                    isTrashView: isTrashView,
                                    maxImageSize: thumbnailMaxSize(colWidth: colWidth, aspectRatio: asset.aspectRatio),
                                    onSelect: {
                                        // Animation is driven once by ContentView's
                                        // .animation(value: selectedAsset != nil).
                                        selectedAsset = asset
                                    },
                                    onContextMenu: { frame in
                                        withAnimation(ManatherTheme.menuMotion) {
                                            contextTarget = ContextTarget(asset: asset, frame: frame)
                                        }
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                ))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 80) // Extra bottom padding for FAB
            }
        }
    }

    // MARK: - Collection Stack Cards (library header row)

    private var collectionStackRow: some View {
        let live = assets.filter { !$0.isDeleted && !$0.isTrash && !$0.isUnassigned }
        let names = Set(live.flatMap { $0.collectionNames }).sorted()

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(names, id: \.self) { name in
                    let items = live.filter { $0.inCollection(name) }
                    Button {
                        withAnimation(ManatherTheme.uiMotion) {
                            activeCollectionFilter = name
                        }
                    } label: {
                        collectionStackCard(name: name, items: items)
                            .hoverLift(scale: 1.03)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2) // room for card shadows
        }
    }

    private func collectionStackCard(name: String, items: [AssetItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fanned preview stack
            ZStack {
                ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                    Group {
                        if !item.relativeFilePath.isEmpty, item.assetType != .codeSnippet {
                            CachedImageView(relativePath: item.relativeFilePath, maxSize: 200)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                .frame(width: 96, height: 96)
                                .overlay(
                                    Image(systemName: item.assetType.iconName)
                                        .font(.system(size: 22))
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                    .rotationEffect(.degrees(Double(index) * 5 - 4))
                    .offset(x: CGFloat(index) * 5, y: CGFloat(index) * -2)
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                }
            }
            .frame(width: 110, height: 104)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text("\(items.count) \(items.count == 1 ? "save" : "saves")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.05) : Color.white.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            if !searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(ManatherTheme.mutedInk.opacity(0.42))

                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink.opacity(0.72))

                Text("Try a different search term")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ManatherTheme.mutedInk.opacity(0.70))
            } else if let colorF = activeColorFilter {
                Circle()
                    .fill(colorF.swatch.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 2))

                Text("No \(colorF.label.lowercased()) assets")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink.opacity(0.72))

                Button("Clear color filter") {
                    withAnimation(ManatherTheme.uiMotion) {
                        activeColorFilter = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ManatherTheme.accent)
            } else if isTrashView {
                Image(systemName: "trash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(ManatherTheme.mutedInk.opacity(0.42))

                Text("Trash is empty")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ManatherTheme.ink.opacity(0.72))
            } else {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.34))
                            .frame(width: 82, height: 82)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ManatherTheme.hairline, lineWidth: 1)
                            )

                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(ManatherTheme.ink.opacity(0.45))
                    }
                    .scaleEffect(isDropTargeted ? 1.06 : 1.0)
                    .animation(ManatherTheme.pulse, value: isDropTargeted)

                    Text("Drop assets here")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ManatherTheme.ink.opacity(0.76))

                    Text("or click + to add links, code, and files")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ManatherTheme.mutedInk.opacity(0.72))
                }
                .padding(30)
                .frame(width: 330)
                .manatherGlass(cornerRadius: 18, material: .ultraThinMaterial, tint: Color.white.opacity(0.32))
                .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import Handling

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importFile(from: url)
            }
        case .failure(let error):
            print("File import error: \(error.localizedDescription)")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier,
                    options: nil
                ) { item, _ in
                    // macOS 13+ returns URL directly; older builds return Data
                    let resolved: URL?
                    if let url = item as? URL {
                        resolved = url
                    } else if let data = item as? Data {
                        resolved = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        resolved = nil
                    }
                    guard let url = resolved else { return }
                    DispatchQueue.main.async {
                        importFile(from: url)
                    }
                }
            }
        }
    }

    private func importFile(from url: URL) {
        // Shared with drag & drop, ⌘V paste and the screenshot hotkey.
        AssetIngest.ingestFile(at: url, into: modelContext)
    }

    private func moveAssetToTrash(_ asset: AssetItem) {
        if selectedAsset?.id == asset.id {
            withAnimation(ManatherTheme.overlayMotion) {
                selectedAsset = nil
            }
        }
        Task { @MainActor in
            asset.isTrash = true
        }
    }

    // MARK: - Custom Context Menu

    private let contextMenuWidth: CGFloat = 232

    private func contextMenuOverlay(_ target: ContextTarget) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Dimmed backdrop — click anywhere to dismiss.
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissContextMenu() }

                AssetContextMenuView(
                    asset: target.asset,
                    isDarkMode: isDarkMode,
                    collections: collectionNames,
                    onCreateCollection: { createCollectionEntity($0) },
                    isTrash: isTrashView,
                    onOpen: { selectedAsset = target.asset },
                    onCopyPrompt: { copyPrompt(target.asset) },
                    onCopyImage: canCopyImage(target.asset) ? { copyImageToPasteboard(target.asset) } : nil,
                    onRevealInFinder: target.asset.relativeFilePath.isEmpty ? nil : { revealInFinder(target.asset) },
                    onDuplicate: { duplicateAsset(target.asset) },
                    onExport: target.asset.relativeFilePath.isEmpty ? nil : { exportAsset(target.asset) },
                    onTrash: { moveAssetToTrash(target.asset) },
                    onRestore: { restoreAsset(target.asset) },
                    onDeletePermanently: {
                        assetToDelete = target.asset
                        showDeleteConfirmation = true
                    },
                    onDismiss: { dismissContextMenu() }
                )
                .offset(
                    x: min(target.frame.minX, max(8, geo.size.width - contextMenuWidth - 12)),
                    y: min(target.frame.minY, max(8, geo.size.height - 360))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
            .onExitCommand { dismissContextMenu() }
        }
    }

    private func canCopyImage(_ asset: AssetItem) -> Bool {
        !asset.relativeFilePath.isEmpty && (asset.assetType == .image || asset.assetType == .gif)
    }

    private func copyImageToPasteboard(_ asset: AssetItem) {
        let url = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
        guard let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func revealInFinder(_ asset: AssetItem) {
        let url = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func dismissContextMenu() {
        withAnimation(ManatherTheme.menuMotion) {
            contextTarget = nil
        }
    }

    private func restoreAsset(_ asset: AssetItem) {
        if selectedAsset?.id == asset.id {
            selectedAsset = nil
        }
        asset.isTrash = false
    }

    private func copyPrompt(_ asset: AssetItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(asset.prompt, forType: .string)
    }

    private func duplicateAsset(_ asset: AssetItem) {
        var newPath = asset.relativeFilePath
        if !asset.relativeFilePath.isEmpty {
            let srcURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
            let ext = srcURL.pathExtension
            let newFilename = "copy_\(UUID().uuidString).\(ext)"
            let destURL = FileManagerHelper.assetsDirectory.appendingPathComponent(newFilename)
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
            newPath = newFilename
        }

        let copy = AssetItem(
            title: "\(asset.title) (Copy)",
            relativeFilePath: newPath,
            sourceURL: asset.sourceURL,
            prompt: asset.prompt,
            notes: asset.notes,
            imageWidth: asset.imageWidth,
            imageHeight: asset.imageHeight,
            typeRaw: asset.typeRaw,
            codeLanguage: asset.codeLanguage,
            codeContent: asset.codeContent,
            dominantColorsHex: asset.dominantColorsHex,
            collectionNames: asset.collectionNames,
            spaceName: asset.spaceName,
            tags: asset.tags
        )
        modelContext.insert(copy)
    }

    private func exportAsset(_ asset: AssetItem) {
        guard !asset.relativeFilePath.isEmpty else { return }

        let savePanel = NSSavePanel()
        let ext = (asset.relativeFilePath as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) {
            savePanel.allowedContentTypes = [type]
        } else {
            savePanel.allowedContentTypes = [.image]
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = asset.title

        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                let sourceURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                try? FileManager.default.removeItem(at: destinationURL)
                try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private func deleteAssetPermanently(_ asset: AssetItem) {
        let filePath = asset.relativeFilePath
        let id = asset.id

        // Mark soft-deleted immediately so the card disappears while animation plays
        asset.isDeleted = true

        if selectedAsset?.id == id {
            withAnimation(ManatherTheme.overlayMotion) {
                selectedAsset = nil
            }
        }

        // Drop the in-memory caches on the main actor (where this runs — fast,
        // just removing dictionary entries)...
        if !filePath.isEmpty {
            ImageCache.shared.removeCachedImages(for: filePath)
        }

        // ...and delete the file from disk off the main thread (I/O).
        Task.detached {
            if !filePath.isEmpty {
                FileManagerHelper.deleteFile(relativePath: filePath)
            }
        }

        // Remove from SwiftData after a brief delay so any outgoing animations finish
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            modelContext.delete(asset)
        }
    }
}

// MARK: - Color Filter Swatch

struct ColorFilterSwatch: View {
    let base: BaseColor
    let isActive: Bool
    let isDimmed: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(base.swatch)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isActive ? 0.9 : 0.25), lineWidth: isActive ? 2 : 1)
                )
                .overlay(
                    // Selection ring outside the swatch
                    Circle()
                        .stroke(base.swatch.opacity(isActive ? 0.5 : 0), lineWidth: 2)
                        .padding(-3)
                )
                .scaleEffect(isHovered || isActive ? 1.25 : 1.0)
                .opacity(isDimmed ? 0.35 : 1.0)
                .animation(ManatherTheme.microMotion, value: isHovered)
                .animation(ManatherTheme.uiMotion, value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(base.label)
    }
}
