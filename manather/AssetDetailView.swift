//
//  AssetDetailView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit

// MARK: - Detail View Colors

private enum ViewerColors {
    static let background = ManatherTheme.viewerBackground
    static let navArrow = Color.white.opacity(0.7)
    static let tertiaryText = Color.white.opacity(0.4)
}

struct AssetDetailView: View {
    @Binding var selectedAsset: AssetItem?
    let assets: [AssetItem]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var zoomScale: Double = 1.0
    @State private var lastZoomScale: Double = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var loadedImage: NSImage? = nil
    @State private var blurImage: NSImage? = nil
    @State private var isLoading = false
    @State private var showInspector = true
    @State private var loadTask: Task<Void, Never>?
    @State private var videoPlayer: AVPlayer?

    private var currentIndex: Int {
        guard let asset = selectedAsset else { return 0 }
        return assets.firstIndex(where: { $0.id == asset.id }) ?? 0
    }

    private var canGoBack: Bool { currentIndex > 0 }
    private var canGoForward: Bool { currentIndex < assets.count - 1 }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Full-screen width header
                topBar
                    .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    // Left: Transparent Image Area
                    imageArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right: Floating Glassmorphic Inspector
                    if showInspector {
                        InspectorView(asset: $selectedAsset)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                            .padding(.trailing, 16)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .onChange(of: geometry.size.width) { oldValue, newValue in
                if newValue < 650 && showInspector {
                    withAnimation(ManatherTheme.uiMotion) {
                        showInspector = false
                    }
                }
            }
        }
        .ignoresSafeArea()
        .background(
            ZStack {
                Color.black
                
                if let nsImage = blurImage ?? loadedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60, opaque: true)
                        .saturation(1.50)
                        .opacity(0.55)
                        .scaleEffect(1.20)
                        .clipped()
                        .drawingGroup() // Rasterize blur for GPU performance
                } else {
                    // Fallback ambient gradient if no image is available (e.g. code snippets)
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.08, blue: 0.12),
                            Color(red: 0.02, green: 0.03, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // Vignette gradient for readability
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.65),
                        Color.black.opacity(0.15),
                        Color.black.opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .onAppear {
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            videoPlayer?.pause()
            videoPlayer = nil
        }
        .onChange(of: selectedAsset) { _, _ in
            videoPlayer?.pause()
            videoPlayer = nil
            loadImage()
        }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
        .onKeyPress(.escape) {
            selectedAsset = nil
            return .handled
        }
    }

    // MARK: - Image Area

    private var imageArea: some View {
        ZStack(alignment: .bottom) {
                Color.clear // Transparent to let blurred background show through

                if isLoading && selectedAsset?.assetType != .webLink && selectedAsset?.assetType != .codeSnippet {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else if let asset = selectedAsset {
                    let fileURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)

                    Group {
                        switch asset.assetType {
                        case .image:
                            if let nsImage = loadedImage {
                                GeometryReader { geometry in
                                    let dragGesture = DragGesture(minimumDistance: 3)
                                        .onChanged { value in
                                            guard zoomScale > 1.0 else { return }
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { value in
                                            lastOffset = offset
                                            limitOffset(viewSize: geometry.size, imageSize: nsImage.size)
                                        }

                                    let magnifyGesture = MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastZoomScale * value
                                            zoomScale = min(max(newScale, 0.25), 4.0)
                                        }
                                        .onEnded { value in
                                            if zoomScale < 1.0 {
                                                withAnimation(ManatherTheme.uiMotion) {
                                                    zoomScale = 1.0
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            }
                                            lastZoomScale = zoomScale
                                        }

                                    ZStack {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .id(asset.id)
                                            .scaleEffect(zoomScale)
                                            .offset(offset)
                                            .gesture(dragGesture.simultaneously(with: magnifyGesture))
                                            .onTapGesture(count: 2) {
                                                withAnimation(ManatherTheme.uiMotion) {
                                                    if zoomScale > 1.0 {
                                                        zoomScale = 1.0
                                                        offset = .zero
                                                        lastOffset = .zero
                                                    } else {
                                                        zoomScale = 2.0
                                                    }
                                                    lastZoomScale = zoomScale
                                                }
                                            }
                                    }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                                .clipped()
                            }

                        case .gif:
                            GeometryReader { geometry in
                                let dragGesture = DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        guard zoomScale > 1.0 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { value in
                                        lastOffset = offset
                                        let size = loadedImage?.size ?? CGSize(width: 500, height: 500)
                                        limitOffset(viewSize: geometry.size, imageSize: size)
                                    }

                                let magnifyGesture = MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastZoomScale * value
                                        zoomScale = min(max(newScale, 0.25), 4.0)
                                    }
                                    .onEnded { value in
                                        if zoomScale < 1.0 {
                                            withAnimation(ManatherTheme.uiMotion) {
                                                zoomScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                        lastZoomScale = zoomScale
                                    }

                                ZStack {
                                    AnimatedGifView(url: fileURL)
                                        .id(asset.id)
                                        .scaleEffect(zoomScale)
                                        .offset(offset)
                                        .gesture(dragGesture.simultaneously(with: magnifyGesture))
                                        .onTapGesture(count: 2) {
                                            withAnimation(ManatherTheme.uiMotion) {
                                                if zoomScale > 1.0 {
                                                    zoomScale = 1.0
                                                    offset = .zero
                                                    lastOffset = .zero
                                                } else {
                                                    zoomScale = 2.0
                                                }
                                                lastZoomScale = zoomScale
                                            }
                                        }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                            .clipped()

                        case .video:
                            if let videoPlayer {
                                VideoPlayer(player: videoPlayer)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(40)
                                    .id(asset.id)
                            }

                        case .webLink:
                            if let url = URL(string: asset.sourceURL) {
                                WebView(url: url)
                                    .id(asset.id)
                                    .background(colorScheme == .dark ? Color.black : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                    .padding(40)
                            }

                        case .codeSnippet, .mcpServer, .skill:
                            textContentViewer(for: asset)
                        }
                    }

                    // Floating Navigation Pill at the bottom
                    bottomNav
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(ViewerColors.tertiaryText)
                        Text("Image not available")
                            .font(.system(size: 13))
                            .foregroundStyle(ViewerColors.tertiaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Text Content Viewer (code / MCP / skill)

    private func textContentViewer(for asset: AssetItem) -> some View {
        let headerLabel: String = {
            switch asset.assetType {
            case .mcpServer: return asset.codeLanguage?.isEmpty == false ? asset.codeLanguage! : "MCP Server"
            case .skill: return "Skill · Markdown"
            default: return asset.codeLanguage ?? "Code"
            }
        }()

        let body: String = {
            if asset.assetType == .mcpServer {
                var parts: [String] = []
                if let cmd = asset.codeLanguage, !cmd.isEmpty { parts.append("# Launch command\n\(cmd)") }
                if let cfg = asset.codeContent, !cfg.isEmpty { parts.append("# Config\n\(cfg)") }
                return parts.joined(separator: "\n\n")
            }
            return asset.codeContent ?? ""
        }()

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if asset.assetType == .mcpServer {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11))
                        .foregroundStyle(ManatherTheme.accent)
                } else if asset.assetType == .skill {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.30))
                }

                Text(headerLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)

                Spacer()

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(body, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.microAnimated)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView {
                Text(body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .background(Color(red: 0.09, green: 0.10, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(40)
    }

    // MARK: - Top Bar (Inline macOS Header)

    private var topBar: some View {
        HStack(spacing: 16) {
            // Padding to accommodate the OS traffic light buttons on the far left
            Spacer()
                .frame(width: 80)

            // Back button + counter
            HStack(spacing: 12) {
                Button {
                    selectedAsset = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.microAnimated)

                Text("\(currentIndex + 1) / \(assets.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            Spacer()

            // Zoom controls (only show for image & gif)
            if let type = selectedAsset?.assetType, type == .image || type == .gif {
                HStack(spacing: 8) {
                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)

                    Slider(value: Binding(
                        get: { zoomScale },
                        set: { newValue in
                            zoomScale = newValue
                            if newValue <= 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            }
                            lastZoomScale = newValue
                        }
                    ), in: 0.25...4.0)
                    .frame(width: 100)
                    .controlSize(.mini)
                    .tint(.white.opacity(0.4))
                }
            } else {
                Spacer()
                    .frame(width: 150)
            }

            // Divider line
            dividerLine

            // Action buttons
            HStack(spacing: 4) {
                // Native ShareLink (only show for local files)
                if let asset = selectedAsset, !asset.relativeFilePath.isEmpty {
                    let fileURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                    ShareLink(item: fileURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.microAnimated)
                    .help("Share")
                }
                
                // Save/Download button (only show for local files)
                if let asset = selectedAsset, !asset.relativeFilePath.isEmpty {
                    actionButton(icon: "arrow.down.to.line", tooltip: "Save") {
                        saveImage()
                    }
                }
                
                // Copy snippet content button (only show for code)
                if let asset = selectedAsset, asset.assetType == .codeSnippet {
                    actionButton(icon: "doc.on.doc", tooltip: "Copy Code") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(asset.codeContent ?? "", forType: .string)
                    }
                }
                
                actionButton(icon: "trash", tooltip: "Delete") {
                    if let asset = selectedAsset {
                        selectedAsset = nil
                        Task { @MainActor in
                            asset.isTrash = true
                        }
                    }
                }
            }

            // Divider line
            dividerLine

            // Toggle Inspector
            Button {
                withAnimation(ManatherTheme.uiMotion) {
                    showInspector.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundStyle(showInspector ? ManatherTheme.accent : .white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.microAnimated)
            .help("Toggle Inspector")

            // Divider line
            dividerLine

            // Close button
            Button {
                selectedAsset = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.microAnimated)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            // Scrim keeps white toolbar icons readable over light images
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    // MARK: - Floating Bottom Navigation Pill

    private var bottomNav: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                navigatePrevious()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        canGoBack ? Color.white : Color.white.opacity(0.25)
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.microAnimated)
            .disabled(!canGoBack)

            Text("to navigate")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.70))

            Button {
                navigateNext()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        canGoForward ? Color.white : Color.white.opacity(0.25)
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.microAnimated)
            .disabled(!canGoForward)

            Spacer()
        }
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                Color.black.opacity(0.50)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
        .padding(.bottom, 20)
        .frame(width: 240)
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 16)
    }

    private func actionButton(
        icon: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help(tooltip)
    }

    private func navigatePrevious() {
        let idx = currentIndex
        guard idx > 0, idx - 1 < assets.count else { return }
        withAnimation(ManatherTheme.fade) {
            selectedAsset = assets[idx - 1]
        }
    }

    private func navigateNext() {
        let idx = currentIndex
        guard idx >= 0, idx + 1 < assets.count else { return }
        withAnimation(ManatherTheme.fade) {
            selectedAsset = assets[idx + 1]
        }
    }

    private func loadImage() {
        guard let asset = selectedAsset else { return }
        
        // Reset zoom & pan
        zoomScale = 1.0
        lastZoomScale = 1.0
        offset = .zero
        lastOffset = .zero
        
        // Cancel previous load
        loadTask?.cancel()
        
        // Set up video player if needed
        if asset.assetType == .video, !asset.relativeFilePath.isEmpty {
            let fileURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
            videoPlayer = AVPlayer(url: fileURL)
        }
        
        // For non-local files, loadedImage is nil
        if asset.relativeFilePath.isEmpty {
            self.loadedImage = nil
            self.blurImage = nil
            return
        }
        
        // Check for any cached image instantly (synchronously) to avoid black flash / loading spinners
        if let cached = ImageCache.shared.anyCachedImage(for: asset.relativeFilePath) {
            withAnimation(ManatherTheme.fade) {
                self.loadedImage = cached
                self.isLoading = false
            }
        } else {
            withAnimation(ManatherTheme.fade) {
                self.loadedImage = nil
                self.isLoading = true
            }
        }
        
        // Try cached blur thumbnail
        if let cachedBlur = ImageCache.shared.cachedThumbnail(for: asset.relativeFilePath, maxSize: 200) {
            withAnimation(ManatherTheme.fade) {
                self.blurImage = cachedBlur
            }
        } else {
            withAnimation(ManatherTheme.fade) {
                self.blurImage = nil
            }
        }
        
        let path = asset.relativeFilePath
        let assetID = asset.id
        
        loadTask = Task {
            // Small thumbnail first for the background blur (fast) if not cached.
            if self.blurImage == nil {
                let blurThumb = await ImageCache.shared.thumbnail(for: path, maxSize: 200)
                guard !Task.isCancelled, self.selectedAsset?.id == assetID else { return }
                withAnimation(ManatherTheme.fade) {
                    self.blurImage = blurThumb
                }
            }

            // Then the full-resolution image for the foreground.
            let img = await ImageCache.shared.fullImageAsync(for: path)
            guard !Task.isCancelled, self.selectedAsset?.id == assetID else { return }

            withAnimation(ManatherTheme.fade) {
                self.loadedImage = img
                self.isLoading = false
            }
            // Keep `blurImage` (a tiny 200px thumb) as the background source — never
            // null it. Otherwise the background would blur the full-resolution image
            // every time, stalling a frame on open and on each navigation.

            // Warm the neighbours so ← / → paging is instant (no spinner, no decode).
            prefetchNeighbors()
        }
    }

    /// Decode the previous/next images into the cache ahead of time, so paging
    /// through the library with ← / → shows them instantly instead of flashing a
    /// spinner while the full image decodes.
    private func prefetchNeighbors() {
        let idx = currentIndex
        for n in [idx - 1, idx + 1] where n >= 0 && n < assets.count {
            let neighbor = assets[n]
            guard !neighbor.relativeFilePath.isEmpty else { continue }
            switch neighbor.assetType {
            case .image, .gif, .webLink:
                let path = neighbor.relativeFilePath
                Task(priority: .utility) {
                    _ = await ImageCache.shared.thumbnail(for: path, maxSize: 200)
                    _ = await ImageCache.shared.fullImageAsync(for: path)
                }
            case .video, .codeSnippet, .mcpServer, .skill:
                break
            }
        }
    }

    private func limitOffset(viewSize: CGSize, imageSize: CGSize) {
        // Avoid NaN offsets (which make the image jump off-screen) if a size is
        // momentarily zero during layout or the image has degenerate dimensions.
        guard viewSize.width > 0, viewSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return }
        let viewRatio = viewSize.width / viewSize.height
        let imageRatio = imageSize.width / imageSize.height
        
        let displayedWidth: CGFloat
        let displayedHeight: CGFloat
        
        if imageRatio > viewRatio {
            displayedWidth = viewSize.width
            displayedHeight = viewSize.width / imageRatio
        } else {
            displayedWidth = viewSize.height * imageRatio
            displayedHeight = viewSize.height
        }
        
        let scaledWidth = displayedWidth * zoomScale
        let scaledHeight = displayedHeight * zoomScale
        
        let maxHorizontalOffset = max(0, (scaledWidth - viewSize.width) / 2)
        let maxVerticalOffset = max(0, (scaledHeight - viewSize.height) / 2)
        
        withAnimation(ManatherTheme.uiMotion) {
            offset = CGSize(
                width: min(max(offset.width, -maxHorizontalOffset), maxHorizontalOffset),
                height: min(max(offset.height, -maxVerticalOffset), maxVerticalOffset)
            )
            lastOffset = offset
        }
    }

    private func saveImage() {
        guard let asset = selectedAsset, !asset.relativeFilePath.isEmpty else { return }
        
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
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                } catch {
                    print("Error saving file: \(error.localizedDescription)")
                }
            }
        }
    }
}
