//
//  GalleryGridView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum MainTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case collections = "Collections"
    case spaces = "Spaces"

    var id: String { rawValue }
}

struct GalleryGridView: View {
    @Environment(\.modelContext) private var modelContext
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
    @State private var activeSpaceFilter: String? = nil
    @State private var showSettingsPopover = false

    @State private var isDropTargeted = false
    @State private var showWebLinkSheet = false
    @State private var showCodeSnippetSheet = false

    private var isTrashView: Bool {
        selectedCategory == .trash
    }

    private var categoryAssets: [AssetItem] {
        switch selectedCategory {
        case .all, .unsorted:
            return assets.filter { !$0.isTrash }
        case .trash:
            return assets.filter { $0.isTrash }
        }
    }

    private var filteredAssets: [AssetItem] {
        var items = categoryAssets

        if let collectionFilter = activeCollectionFilter {
            items = items.filter { $0.collectionName == collectionFilter }
        }

        if let spaceFilter = activeSpaceFilter {
            items = items.filter { $0.spaceName == spaceFilter }
        }

        guard !searchText.isEmpty else {
            return items.sorted { $0.dateAdded > $1.dateAdded }
        }

        let query = searchText.lowercased()
        return items.filter {
            $0.title.lowercased().contains(query) ||
            $0.prompt.lowercased().contains(query) ||
            ($0.codeContent?.lowercased().contains(query) ?? false)
        }
        .sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Distributes items across columns for masonry layout (shortest column first)
    private func distributeToColumns(availableWidth: CGFloat) -> [[AssetItem]] {
        let baseCount = max(1, Int(columnCount))
        // Target about 160pt minimum width per column to prevent squishing
        let maxColumnsForWidth = max(1, Int(availableWidth / 160))
        let count = min(baseCount, maxColumnsForWidth)
        
        var columns = Array(repeating: [AssetItem](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for item in filteredAssets {
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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Top toolbar
                topBar

                // Content
                ZStack {
                    if selectedTab == .library {
                        if filteredAssets.isEmpty {
                            emptyStateView
                        } else {
                            VStack(spacing: 0) {
                                filterBadgeBar
                                masonryGrid
                            }
                        }
                    } else if selectedTab == .collections {
                        collectionsGrid
                    } else {
                        spacesGrid
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
        .onAppear {
            for asset in assets {
                if asset.assetType == .webLink && asset.relativeFilePath.isEmpty {
                    WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: modelContext)
                }
            }
        }
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
            .padding(.top, 12)
            .padding(.bottom, 14)
            
            // Row 2: Tabs and Filters
            HStack(alignment: .center) {
                categoryTabs
                
                Spacer()
                
                controlCluster
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var brandMark: some View {
        HStack(spacing: 10) {
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
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.32))
                .padding(.leading, 6)
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
                
                let bgColor: Color = {
                    if isSelected {
                        return isDarkMode ? Color.white : Color.black
                    } else {
                        return Color.clear
                    }
                }()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    tabLabel(for: tab)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(bgColor)
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
                Image(systemName: "square.grid.3x3.square")
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
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.rawValue)
                        .font(.system(size: 14, weight: selectedCategory == category ? .bold : .medium))
                        .foregroundStyle(selectedCategory == category ? Color.primary : Color.primary.opacity(0.38))
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(selectedCategory == category ? Color.primary : Color.clear)
                                .frame(height: 2.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterBadgeBar: some View {
        Group {
            if activeCollectionFilter != nil || activeSpaceFilter != nil {
                HStack(spacing: 8) {
                    Text("Filters:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                    
                    if let col = activeCollectionFilter {
                        filterBadge(text: "Collection: \(col)") {
                            activeCollectionFilter = nil
                        }
                    }
                    
                    if let sp = activeSpaceFilter {
                        filterBadge(text: "Space: \(sp)") {
                            activeSpaceFilter = nil
                        }
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
        let collections = Dictionary(grouping: assets.filter { !$0.isDeleted }) { $0.collectionName ?? "Unassigned" }
        let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(collections.keys.sorted(), id: \.self) { name in
                    let items = collections[name] ?? []
                    Button {
                        activeCollectionFilter = name == "Unassigned" ? nil : name
                        withAnimation {
                            selectedTab = .library
                        }
                    } label: {
                        folderCard(title: name, count: items.count, items: items)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private var spacesGrid: some View {
        let spaces = Dictionary(grouping: assets.filter { !$0.isDeleted }) { $0.spaceName ?? "Default Space" }
        let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(spaces.keys.sorted(), id: \.self) { name in
                    let items = spaces[name] ?? []
                    Button {
                        activeSpaceFilter = name == "Default Space" ? nil : name
                        withAnimation {
                            selectedTab = .library
                        }
                    } label: {
                        spaceCard(title: name, count: items.count, items: items)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private func folderCard(title: String, count: Int, items: [AssetItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                    )

                if !items.isEmpty {
                    let cover = items.first!
                    if !cover.relativeFilePath.isEmpty, cover.assetType != .codeSnippet {
                        CachedImageView(relativePath: cover.relativeFilePath, maxSize: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 100, height: 80)
                            .rotationEffect(.degrees(-4))
                            .shadow(color: .black.opacity(0.15), radius: 6, x: -2, y: 3)
                    } else {
                        Image(systemName: cover.assetType == .codeSnippet ? "curlybraces" : "globe")
                            .font(.system(size: 32))
                            .foregroundStyle(ManatherTheme.accent)
                            .frame(width: 80, height: 80)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(-4))
                    }
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(ManatherTheme.accent.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                    .lineLimit(1)

                Text("\(count) saves")
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

    private func spaceCard(title: String, count: Int, items: [AssetItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                    )

                HStack(spacing: -12) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                        if !item.relativeFilePath.isEmpty, item.assetType != .codeSnippet {
                            CachedImageView(relativePath: item.relativeFilePath, maxSize: 100)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(isDarkMode ? Color.black : Color.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                                .zIndex(Double(3 - index))
                        } else {
                            Image(systemName: item.assetType == .codeSnippet ? "curlybraces" : "globe")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(ManatherTheme.accent)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(isDarkMode ? Color.black : Color.white, lineWidth: 1.5))
                                .zIndex(Double(3 - index))
                        }
                    }

                    if items.isEmpty {
                        Image(systemName: "square.grid.3x3.square")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(ManatherTheme.accent.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                    .lineLimit(1)

                Text("\(count) items")
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

    private var controlCluster: some View {
        HStack(spacing: 18) {
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

    private var sortMenu: some View {
        Menu {
            Button("Most recent") {}
            Button("Oldest first") {}
            Button("Name A-Z") {}
        } label: {
            HStack(spacing: 6) {
                Text("Most recent")
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

    private var masonryGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 14
            let columns = distributeToColumns(availableWidth: geometry.size.width)
            
            // Calculate column width in points
            let colWidth = max(100, (geometry.size.width - CGFloat(columns.count - 1) * spacing - 40) / CGFloat(columns.count))
            
            // Calculate raw pixel size using screen scaling
            let rawPixelSize = colWidth * (NSScreen.main?.backingScaleFactor ?? 2.0)
            
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
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns.count, id: \.self) { colIndex in
                        VStack(spacing: spacing) {
                            ForEach(columns[colIndex]) { asset in
                                AssetCardView(
                                    asset: asset,
                                    isSelected: selectedAsset?.id == asset.id,
                                    isTrashView: isTrashView,
                                    animationNamespace: animationNamespace,
                                    maxImageSize: targetMaxSize,
                                    onSelect: {
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                                            selectedAsset = asset
                                        }
                                    },
                                    onTrash: {
                                        if selectedAsset?.id == asset.id {
                                            withAnimation(.spring(response: 0.35)) {
                                                selectedAsset = nil
                                            }
                                        }
                                        Task { @MainActor in
                                            asset.isTrash = true
                                        }
                                    },
                                    onRestore: {
                                        if selectedAsset?.id == asset.id {
                                            withAnimation(.spring(response: 0.35)) {
                                                selectedAsset = nil
                                            }
                                        }
                                        Task { @MainActor in
                                            asset.isTrash = false
                                        }
                                    },
                                    onDeletePermanently: {
                                        let filePath = asset.relativeFilePath
                                        let id = asset.id
                                        
                                        // Remove from selection if needed
                                        if selectedAsset?.id == id {
                                            withAnimation(.spring(response: 0.35)) {
                                                selectedAsset = nil
                                            }
                                        }
                                        
                                        // Delete files in background to prevent UI freeze
                                        Task.detached {
                                            if !filePath.isEmpty {
                                                FileManagerHelper.deleteFile(relativePath: filePath)
                                                await ImageCache.shared.removeCachedImages(for: filePath)
                                            }
                                        }
                                        
                                        // Delete SwiftData model outside of animation transaction
                                        Task { @MainActor in
                                            modelContext.delete(asset)
                                        }
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 80) // Extra bottom padding for FAB
            }
        }
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
                withAnimation(.spring(response: 0.4)) {
                    let asset = AssetItem(
                        title: title,
                        relativeFilePath: relativePath,
                        imageWidth: finalDims?.width ?? 0,
                        imageHeight: finalDims?.height ?? 0,
                        typeRaw: type,
                        codeLanguage: codeLanguage,
                        codeContent: codeContent
                    )
                    modelContext.insert(asset)
                }
            }
        }
    }
}
