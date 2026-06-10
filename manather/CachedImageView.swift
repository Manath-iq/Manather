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
    
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasFailed = false
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
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
    
    private func loadImage() {
        hasFailed = false
        
        if let maxSize = maxSize {
            // Check thumbnail cache synchronously
            if let cached = ImageCache.shared.cachedThumbnail(for: relativePath, maxSize: maxSize) {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.image = cached
                }
                return
            }
        } else {
            // Check full cache synchronously
            if let cached = ImageCache.shared.cachedFullImage(for: relativePath) {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.image = cached
                }
                return
            }
        }
        
        // Cancel any existing load
        loadTask?.cancel()
        isLoading = true
        
        let path = relativePath
        loadTask = Task {
            let loadedImage: NSImage?
            if let maxSize = maxSize {
                loadedImage = await ImageCache.shared.thumbnail(for: path, maxSize: maxSize)
            } else {
                loadedImage = await ImageCache.shared.fullImageAsync(for: path)
            }
            
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeOut(duration: 0.2)) {
                self.image = loadedImage
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
                            Color(red: 0.15, green: 0.20, blue: 0.23),
                            Color(red: 0.10, green: 0.15, blue: 0.18)
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
