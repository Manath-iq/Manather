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
    let animationNamespace: Namespace.ID

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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
        .onChange(of: selectedAsset) { _, _ in
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
                                    let dragGesture = DragGesture(minimumDistance: 0)
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
                                                withAnimation(.spring()) {
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
                                            .matchedGeometryEffect(id: asset.id, in: animationNamespace)
                                            .id(asset.id)
                                            .scaleEffect(zoomScale)
                                            .offset(offset)
                                            .gesture(dragGesture.simultaneously(with: magnifyGesture))
                                            .onTapGesture(count: 2) {
                                                withAnimation(.spring(response: 0.3)) {
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
                                let dragGesture = DragGesture(minimumDistance: 0)
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
                                            withAnimation(.spring()) {
                                                zoomScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                        lastZoomScale = zoomScale
                                    }

                                ZStack {
                                    AnimatedGifView(url: fileURL)
                                        .matchedGeometryEffect(id: asset.id, in: animationNamespace)
                                        .id(asset.id)
                                        .scaleEffect(zoomScale)
                                        .offset(offset)
                                        .gesture(dragGesture.simultaneously(with: magnifyGesture))
                                        .onTapGesture(count: 2) {
                                            withAnimation(.spring(response: 0.3)) {
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
                            VideoPlayer(player: AVPlayer(url: fileURL))
                                .matchedGeometryEffect(id: asset.id, in: animationNamespace)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(40)
                                .id(asset.id) // Force recreation to avoid stale player

                        case .webLink:
                            if let url = URL(string: asset.sourceURL) {
                                WebView(url: url)
                                    .matchedGeometryEffect(id: asset.id, in: animationNamespace)
                                    .id(asset.id)
                                    .background(colorScheme == .dark ? Color.black : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                    .padding(40)
                            }

                        case .codeSnippet:
                            VStack(alignment: .leading, spacing: 0) {
                                // Header
                                HStack {
                                    Text(asset.codeLanguage ?? "Swift")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))

                                    Spacer()

                                    Button {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(asset.codeContent ?? "", forType: .string)
                                    } label: {
                                        Label("Copy Code", systemImage: "doc.on.doc")
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

                                // Scrollable Code View
                                ScrollView {
                                    Text(asset.codeContent ?? "")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .matchedGeometryEffect(id: asset.id, in: animationNamespace)
                            .background(Color(red: 0.08, green: 0.10, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(40)
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

    // MARK: - Top Bar (Inline macOS Header)

    private var topBar: some View {
        HStack(spacing: 16) {
            // Padding to accommodate the OS traffic light buttons on the far left
            Spacer()
                .frame(width: 80)

            // Back button + counter
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedAsset = nil
                    }
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
                        withAnimation {
                            selectedAsset = nil
                        }
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedAsset = nil
                }
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
        .background(Color.clear)
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
        guard canGoBack else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAsset = assets[currentIndex - 1]
        }
    }

    private func navigateNext() {
        guard canGoForward else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAsset = assets[currentIndex + 1]
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
        
        // For non-local files, loadedImage is nil
        if asset.relativeFilePath.isEmpty {
            self.loadedImage = nil
            self.blurImage = nil
            return
        }
        
        // Check for any cached image instantly (synchronously) to avoid black flash / loading spinners
        if let cached = ImageCache.shared.anyCachedImage(for: asset.relativeFilePath) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.loadedImage = cached
                self.isLoading = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.loadedImage = nil
                self.isLoading = true
            }
        }
        
        // Try cached blur thumbnail
        if let cachedBlur = ImageCache.shared.cachedThumbnail(for: asset.relativeFilePath, maxSize: 200) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.blurImage = cachedBlur
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.blurImage = nil
            }
        }
        
        let path = asset.relativeFilePath
        let assetID = asset.id
        
        loadTask = Task {
            // Load a small thumbnail first for background blur (fast) if not cached
            if self.blurImage == nil {
                let blurThumb = await ImageCache.shared.thumbnail(for: path, maxSize: 200)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.blurImage = blurThumb
                }
            }
            
            // Then load full image
            let img = await ImageCache.shared.fullImageAsync(for: path)
            guard !Task.isCancelled else { return }
            
            if self.selectedAsset?.id == assetID {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.loadedImage = img
                    self.isLoading = false
                }
            }
        }
    }

    private func limitOffset(viewSize: CGSize, imageSize: CGSize) {
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
        
        withAnimation(.easeOut(duration: 0.15)) {
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
