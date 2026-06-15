//
//  CachedImageView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI

struct CachedImageView: View {
    let relativePath: String
    let maxSize: CGFloat? // nil means load full image
    /// How the image fills its frame. `.fit` (default) keeps the whole image
    /// visible; `.fill` crops it to the frame — used for square collection tiles.
    var contentMode: ContentMode = .fit

    @State private var image: NSImage?
    @State private var loadedPath: String? // which path the displayed image belongs to
    @State private var isLoading = false
    @State private var hasFailed = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: contentMode == .fit ? .infinity : nil)
            } else if hasFailed {
                fallbackPlaceholder
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: relativePath) { _, _ in
            loadImage()
        }
        .onChange(of: maxSize) { _, _ in
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    /// Best synchronously-available cached image for the current path, or nil.
    private func bestCachedImage() -> NSImage? {
        if let cached = ImageCache.shared.cachedFullImage(for: relativePath) {
            return cached
        }
        guard let maxSize = maxSize else { return nil }
        let sizes: [CGFloat] = [3000, 2200, 1600, 1200, 800, 500, 300, 200, 100]
        for size in sizes where size >= maxSize {
            if let cached = ImageCache.shared.cachedThumbnail(for: relativePath, maxSize: size) {
                return cached
            }
        }
        return nil
    }

    private func loadImage() {
        let path = relativePath

        // Already displaying an image for this exact path — nothing to do.
        // (loadedPath check is what prevents the stale-thumbnail bug: a cache
        // hit for the NEW path must still replace the OLD displayed image.)
        if image != nil && loadedPath == path { return }

        hasFailed = false
        loadTask?.cancel()

        // Synchronous cache hit — swap immediately, no spinner
        if let cached = bestCachedImage() {
            withAnimation(.easeOut(duration: 0.15)) {
                self.image = cached
                self.loadedPath = path
                self.isLoading = false
            }
            return
        }

        // Keep the old image visible while the new one loads? No — clear it,
        // otherwise navigation appears stuck on the previous asset.
        withAnimation(.easeOut(duration: 0.1)) {
            self.image = nil
            self.loadedPath = nil
        }
        isLoading = true

        loadTask = Task {
            let loadedImage: NSImage?
            if let maxSize = maxSize {
                loadedImage = await ImageCache.shared.thumbnail(for: path, maxSize: maxSize)
            } else {
                loadedImage = await ImageCache.shared.fullImageAsync(for: path)
            }

            guard !Task.isCancelled else { return }
            // Discard result if the view has moved on to a different path
            guard path == relativePath else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                self.image = loadedImage
                self.loadedPath = loadedImage != nil ? path : nil
                self.isLoading = false
                if loadedImage == nil {
                    self.hasFailed = true
                }
            }
        }
    }

    private var fallbackPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.17, blue: 0.19),
                            Color(red: 0.11, green: 0.12, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.red.opacity(0.6))
                Text("Load Error")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
