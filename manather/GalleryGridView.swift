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
    @State private var showSettingsPopover = false
    @State private var sortOrder: SortOrder = .mostRecent
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var assetToDelete: AssetItem? = nil
    @State private var showDeleteConfirmation = false

    @State private var contextTarget: ContextTarget?

    // Boards tab: all boards the user created (across projects).
    @Query(sort: \Board.dateModified, order: .reverse) private var allBoards: [Board]
    @State private var openBoard: Board?
    @State private var showNewBoardSheet = false

    @Query(sort: \AssetCollection.dateAdded, order: .reverse) private var savedCollections: [AssetCollection]
    @State private var showNewCollectionSheet = false
    /// When set, the Collections tab shows this collection's contents in-place
    /// (a dedicated browse screen) instead of the grid of collection folders.
    @State private var openCollection: String? = nil

    @State private var isDropTargeted = false
    @State private var showWebLinkSheet = false
    @State private var showCodeSnippetSheet = false
    @State private var showMCPServerSheet = false
    @State private var showSkillSheet = false

    private var isTrashView: Bool {
        selectedCategory == .trash
    }

    // Computed once per render from the full asset list — passed into cards to avoid per-card @Query
    private var allCollections: [String] {
        Array(Set(assets.filter { !$0.isDeleted && !$0.isTrash }.compactMap { $0.collectionName })).sorted()
    }

    /// The canonical list of every collection: real `AssetCollection` objects
    /// (including empty ones) plus any legacy names still living only on assets.
    private var collectionNames: [String] {
        Set(savedCollections.map(\.name)).union(allCollections).sorted()
    }

    /// Live assets belonging to `name` ("Unassigned" = saves not in any
    /// collection), newest first.
    private func assets(inCollection name: String) -> [AssetItem] {
        let live = assets.filter { !$0.isDeleted && !$0.isTrash }
        let items = name == "Unassigned"
            ? live.filter { $0.collectionName == nil }
            : live.filter { $0.collectionName == name }
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
            return assets.filter { !$0.isTrash && $0.collectionName == nil }
        case .trash:
            return assets.filter { $0.isTrash }
        }
    }

    private var filteredAssets: [AssetItem] {
        var items = categoryAssets

        if let collectionFilter = activeCollectionFilter {
            items = items.filter { $0.collectionName == collectionFilter }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDropTargeted)
        )
        .onDrop(of: [.image, .movie, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
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
        .onAppear {
            let pendingLinks = assets.filter { $0.assetType == .webLink && $0.relativeFilePath.isEmpty }
            for asset in pendingLinks {
                WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: modelContext)
            }
            // Backfill palette data so color filtering works for older imports
            ColorIndexer.shared.backfill(assets: assets.filter { !$0.isTrash })
            // Projects were merged into Collections — fold any old project tag
            // into a collection of the same name (one-time, idempotent).
            mergeProjectsIntoCollections()
            // Turn any collection names still living only on assets into real
            // AssetCollection objects, so they can be managed like the rest.
            seedCollectionsFromAssets()
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = .library
                    }
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = .collections
                    }
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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

            HStack(spacing: 5) {
                Text("Library")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
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

    private func expandSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSearchExpanded = true
        }
        // Focus after the field exists in the hierarchy
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func collapseSearch() {
        isSearchFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
            toolbarIconButton(icon: "safari", tooltip: "Add Web Link") {
                showWebLinkSheet = true
            }
            toolbarIconButton(icon: isDarkMode ? "sun.max.fill" : "moon", tooltip: "Toggle Dark Mode") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDarkMode.toggle()
                }
            }
            toolbarIconButton(icon: "gearshape", tooltip: "Settings") {
                showSettingsPopover = true
            }
            .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
                settingsPopoverContent
            }
        }
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

    private var settingsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDarkMode ? Color.white : Color.primary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("DATA SUMMARY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("Total assets:")
                    Spacer()
                    Text("\(assets.count)")
                        .bold()
                }
                .font(.system(size: 11))
            }
            
            Button("Clear Image Cache") {
                ImageCache.shared.clearAll()
                showSettingsPopover = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
            
            Button("Load Demo Assets") {
                loadDemoAssets()
                showSettingsPopover = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ManatherTheme.accent)
            
            Spacer()
        }
        .padding(16)
        .frame(width: 200, height: 180)
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
        Menu {
            Button { isImporting = true } label: { Label("Import files", systemImage: "doc.badge.plus") }
            Button { showWebLinkSheet = true } label: { Label("Add web link", systemImage: "link") }
            Button { showCodeSnippetSheet = true } label: { Label("Add code snippet", systemImage: "curlybraces") }
            Divider()
            Button { showSkillSheet = true } label: { Label("Add skill", systemImage: "sparkles.rectangle.stack") }
            Button { showMCPServerSheet = true } label: { Label("Add MCP server", systemImage: "server.rack") }
        } label: {
            ZStack {
                Circle()
                    .fill(isDarkMode ? Color.white : Color.black)
                    .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.black : Color.white)
            }
            .frame(width: 48, height: 48)
            .scaleEffect(isFABHovered ? 1.08 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isFABHovered)
        }
        .menuStyle(.borderlessButton)
        .focusable(false)
        .fixedSize()
        .onHover { hovering in
            isFABHovered = hovering
        }
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
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
        // Group live assets by their collection. The "__unassigned__" sentinel
        // keeps loose (uncollected) assets out of the named buckets.
        let grouped = Dictionary(grouping: assets.filter { !$0.isDeleted && !$0.isTrash }) {
            $0.collectionName ?? "__unassigned__"
        }
        let names = collectionNames // real collections (incl. empty) + legacy names
        let unassigned = grouped["__unassigned__"] ?? []
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
                    let items = grouped[name] ?? []
                    Button {
                        withAnimation(ManatherTheme.uiMotion) { openCollection = name }
                    } label: {
                        CollectionFolderCard(title: name, count: items.count, items: items, isDarkMode: isDarkMode)
                            .hoverLift()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            ContextPackExporter.export(projectName: name, assets: items)
                        } label: {
                            Label("Export Context Pack", systemImage: "shippingbox.and.arrow.backward")
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
                        Button {
                            ContextPackExporter.export(projectName: name, assets: items)
                        } label: {
                            Label("Export Context Pack", systemImage: "shippingbox.and.arrow.backward")
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ManatherTheme.viewerBackground)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                Image(systemName: "square.dashed")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.20))
            }
            .frame(maxWidth: .infinity)

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

    /// Projects were merged into Collections: move any old project tag into a
    /// collection of the same name, then clear the project field. Idempotent.
    private func mergeProjectsIntoCollections() {
        for asset in assets where asset.spaceName != nil {
            if (asset.collectionName ?? "").isEmpty {
                asset.collectionName = asset.spaceName
            }
            asset.spaceName = nil
        }
    }

    /// Promote any collection name that only lives on an asset into a real
    /// AssetCollection object, so older libraries gain manageable collections.
    /// Idempotent — safe to run on every launch.
    private func seedCollectionsFromAssets() {
        let existing = Set(savedCollections.map(\.name))
        let fromAssets = Set(assets.filter { !$0.isDeleted }.compactMap { $0.collectionName })
        for name in fromAssets where !existing.contains(name) {
            modelContext.insert(AssetCollection(name: name))
        }
    }

    /// Create a collection object for `name` if one doesn't already exist
    /// (case-insensitive). Used by the right-click "New collection…" flow.
    private func createCollectionEntity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let exists = savedCollections.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if !exists {
            modelContext.insert(AssetCollection(name: trimmed))
        }
    }

    /// Delete a collection. Assets in it aren't deleted — they just fall back to
    /// "Unassigned" (so nothing is lost).
    private func deleteCollection(_ name: String) {
        for asset in assets where asset.collectionName == name {
            asset.collectionName = nil
        }
        for collection in savedCollections where collection.name == name {
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
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.85)) {
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeColorFilter = (activeColorFilter == base) ? nil : base
                    }
                }
            }

            if activeColorFilter != nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
        .focusable(false)
        .fixedSize()
    }

    // MARK: - Masonry Grid

    private func masonryGrid(_ items: [AssetItem], showsCollectionRow: Bool = true) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 14
            let columns = distributeToColumns(items, availableWidth: geometry.size.width)
            
            // Calculate column width in points
            let colWidth = max(100, (geometry.size.width - CGFloat(columns.count - 1) * spacing - 40) / CGFloat(columns.count))
            
            // Calculate raw pixel size using screen scaling
            let rawPixelSize = colWidth * displayScale
            
            // Determine target maximum image size, quantized for caching efficiency
            let targetMaxSize: CGFloat = {
                if rawPixelSize <= 300 {
                    return 300
                } else if rawPixelSize <= 500 {
                    return 500
                } else if rawPixelSize <= 800 {
                    return 800
                } else if rawPixelSize <= 1200 {
                    return 1200
                } else {
                    return 1600
                }
            }()

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
                                    maxImageSize: targetMaxSize,
                                    onSelect: {
                                        // Animation is driven once by ContentView's
                                        // .animation(value: selectedAsset != nil).
                                        selectedAsset = asset
                                    },
                                    onContextMenu: { frame in
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
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
        let grouped = Dictionary(grouping: assets.filter { !$0.isDeleted && !$0.isTrash && $0.collectionName != nil }) { $0.collectionName! }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(grouped.keys.sorted(), id: \.self) { name in
                    let items = grouped[name] ?? []
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                    .animation(.spring(response: 0.4, dampingFraction: 0.5).repeatForever(autoreverses: true), value: isDropTargeted)

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
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            importFile(from: url)
                        }
                    }
                }
            }
        }
    }

    private func importFile(from url: URL) {
        Task {
            let type = FileManagerHelper.detectAssetType(for: url)

            var codeContent: String? = nil
            var codeLanguage: String? = nil

            if type == "codeSnippet" {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                codeContent = try? String(contentsOf: url, encoding: .utf8)
                codeLanguage = url.pathExtension.capitalized
            }

            // Get dimensions before copying (while we have security access)
            let dims = await FileManagerHelper.imageDimensions(from: url)

            guard let relativePath = FileManagerHelper.copyFileToSandbox(from: url) else {
                return
            }

            let title = FileManagerHelper.displayName(from: url)
            
            let finalDims: (width: Double, height: Double)?
            if let dims = dims {
                finalDims = dims
            } else {
                finalDims = await FileManagerHelper.imageDimensions(relativePath: relativePath)
            }

            await MainActor.run {
                let asset = AssetItem(
                    title: title,
                    relativeFilePath: relativePath,
                    imageWidth: finalDims?.width ?? 0,
                    imageHeight: finalDims?.height ?? 0,
                    typeRaw: type,
                    codeLanguage: codeLanguage,
                    codeContent: codeContent
                )
                withAnimation(.spring(response: 0.4)) {
                    modelContext.insert(asset)
                }
                // Index palette right away so color filters pick it up
                ColorIndexer.shared.ensureColors(for: asset)
            }
        }
    }

    private func moveAssetToTrash(_ asset: AssetItem) {
        if selectedAsset?.id == asset.id {
            withAnimation(.spring(response: 0.35)) {
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
        withAnimation(.easeOut(duration: 0.14)) {
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
            collectionName: asset.collectionName,
            spaceName: asset.spaceName
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
            withAnimation(.spring(response: 0.35)) {
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
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(base.label)
    }
}
