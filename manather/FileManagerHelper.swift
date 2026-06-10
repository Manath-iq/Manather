//
//  FileManagerHelper.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Image Cache

final class ImageCache {
    static let shared = ImageCache()

    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let fullImageCache = NSCache<NSString, NSImage>()

    private init() {
        thumbnailCache.countLimit = 200
        thumbnailCache.totalCostLimit = 60 * 1024 * 1024 // 60 MB

        fullImageCache.countLimit = 10
        fullImageCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    /// Returns a cached thumbnail, or generates and caches one. Supports images and videos.
    func thumbnail(for relativePath: String, maxSize: CGFloat = 400) async -> NSImage? {
        let key = "\(relativePath)_\(Int(maxSize))" as NSString

        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let url = FileManagerHelper.absolutePath(for: relativePath)
        
        // Detect if the file is a video
        let fileExtension = url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v", "avi"].contains(fileExtension)
        
        // Generate thumbnail off main thread
        let thumbnail: NSImage?
        if isVideo {
            thumbnail = await generateVideoThumbnail(for: url, maxSize: maxSize)
        } else {
            thumbnail = await generateImageThumbnail(for: url, maxSize: maxSize)
        }

        if let thumbnail {
            let cost = estimateCost(for: thumbnail)
            thumbnailCache.setObject(thumbnail, forKey: key, cost: cost)
        }
        return thumbnail
    }

    /// Memory-efficient image thumbnail using CGImageSource (doesn't load full image into RAM)
    private func generateImageThumbnail(for url: URL, maxSize: CGFloat) async -> NSImage? {
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }

    /// Helper to generate a thumbnail from a video file
    private func generateVideoThumbnail(for url: URL, maxSize: CGFloat = 400) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        
        // Try capturing at 1.0 seconds
        let time = CMTime(seconds: 1.0, preferredTimescale: 60)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            // Fallback: capture at 0.0 seconds
            let zeroTime = CMTime.zero
            do {
                let (cgImage, _) = try await generator.image(at: zeroTime)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } catch {
                return nil
            }
        }
    }

    /// Returns the full-resolution image, cached. Loads synchronously — prefer fullImageAsync for UI.
    func fullImage(for relativePath: String) -> NSImage? {
        let key = relativePath as NSString

        if let cached = fullImageCache.object(forKey: key) {
            return cached
        }

        let url = FileManagerHelper.absolutePath(for: relativePath)
        guard let image = NSImage(contentsOf: url) else { return nil }

        let cost = estimateCost(for: image)
        fullImageCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Async full image loading that runs file I/O off the main thread
    func fullImageAsync(for relativePath: String) async -> NSImage? {
        let key = relativePath as NSString

        if let cached = fullImageCache.object(forKey: key) {
            return cached
        }

        let url = FileManagerHelper.absolutePath(for: relativePath)
        
        // Load the image off the main actor
        guard let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            return NSImage(contentsOf: url)
        }.value else {
            return nil
        }

        // Cache the image on the main actor
        let cost = self.estimateCost(for: image)
        self.fullImageCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    func cachedThumbnail(for relativePath: String, maxSize: CGFloat = 400) -> NSImage? {
        let key = "\(relativePath)_\(Int(maxSize))" as NSString
        return thumbnailCache.object(forKey: key)
    }

    func cachedFullImage(for relativePath: String) -> NSImage? {
        let key = relativePath as NSString
        return fullImageCache.object(forKey: key)
    }

    func anyCachedImage(for relativePath: String) -> NSImage? {
        if let cached = cachedFullImage(for: relativePath) {
            return cached
        }
        let sizes = [1600, 1200, 800, 500, 300, 200, 100]
        for size in sizes {
            let key = "\(relativePath)_\(size)" as NSString
            if let cached = thumbnailCache.object(forKey: key) {
                return cached
            }
        }
        return nil
    }

    func clearAll() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }

    func removeCachedImages(for relativePath: String) {
        let fullKey = relativePath as NSString
        fullImageCache.removeObject(forKey: fullKey)
        
        let sizes = [1600, 1200, 800, 700, 500, 400, 300, 200, 100]
        for size in sizes {
            let thumbKey = "\(relativePath)_\(size)" as NSString
            thumbnailCache.removeObject(forKey: thumbKey)
        }
    }

    /// Estimate memory cost of an NSImage in bytes
    private func estimateCost(for image: NSImage) -> Int {
        let size = image.size
        // 4 bytes per pixel (RGBA), approximate
        return Int(size.width * size.height * 4)
    }
}

// MARK: - Color Extraction

struct DominantColorExtractor {

    /// Extracts the top dominant colors from an NSImage.
    static func extractColors(from image: NSImage, count: Int = 8) -> [NSColor] {
        let sampleSize = 40

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sampleSize,
            pixelsHigh: sampleSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return [] }

        // Draw the image into the small bitmap
        let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        // Sample all pixels and group by quantized color
        var buckets: [String: (r: CGFloat, g: CGFloat, b: CGFloat, count: Int)] = [:]

        for x in 0..<sampleSize {
            for y in 0..<sampleSize {
                guard let color = bitmapRep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }

                let r = color.redComponent
                let g = color.greenComponent
                let b = color.blueComponent

                // Skip near-white and near-black (not useful for palette)
                let brightness = (r + g + b) / 3.0
                if brightness > 0.95 || brightness < 0.05 { continue }

                // Quantize to ~8 levels per channel
                let qr = Int(r * 7)
                let qg = Int(g * 7)
                let qb = Int(b * 7)
                let key = "\(qr),\(qg),\(qb)"

                if let existing = buckets[key] {
                    let n = existing.count + 1
                    buckets[key] = (
                        (existing.r * CGFloat(existing.count) + r) / CGFloat(n),
                        (existing.g * CGFloat(existing.count) + g) / CGFloat(n),
                        (existing.b * CGFloat(existing.count) + b) / CGFloat(n),
                        n
                    )
                } else {
                    buckets[key] = (r, g, b, 1)
                }
            }
        }

        // Sort by frequency, take top N
        let sorted = buckets.values
            .sorted { $0.count > $1.count }
            .prefix(count)

        return sorted.map { NSColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1.0) }
    }
}

// MARK: - File Manager Helper

struct FileManagerHelper {

    // MARK: - Assets Directory

    nonisolated static var assetsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let assetsDir = appSupport
            .appendingPathComponent("ManatherAssets", isDirectory: true)

        if !FileManager.default.fileExists(atPath: assetsDir.path) {
            try? FileManager.default.createDirectory(
                at: assetsDir,
                withIntermediateDirectories: true
            )
        }

        return assetsDir
    }

    // MARK: - File Operations

    static func copyFileToSandbox(from sourceURL: URL) -> String? {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let originalName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        var destinationName = originalName
        var destinationURL = assetsDirectory.appendingPathComponent(destinationName)

        var counter = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationName = "\(baseName)_\(counter).\(fileExtension)"
            destinationURL = assetsDirectory.appendingPathComponent(destinationName)
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationName
        } catch {
            print("Failed to copy file: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func absolutePath(for relativePath: String) -> URL {
        return assetsDirectory.appendingPathComponent(relativePath)
    }

    nonisolated static func deleteFile(relativePath: String) {
        let fileURL = absolutePath(for: relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func displayName(from url: URL) -> String {
        return url.deletingPathExtension().lastPathComponent
    }

    static func fileExists(relativePath: String) -> Bool {
        let fileURL = absolutePath(for: relativePath)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Format & Dimensions

    static func detectAssetType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "avi"].contains(ext) {
            return "video"
        } else if ext == "gif" {
            return "gif"
        } else if ["swift", "js", "ts", "json", "txt", "py", "html", "css", "cpp", "c", "h", "rs", "go", "xml", "yaml", "yml", "sh", "md"].contains(ext) {
            return "codeSnippet"
        } else {
            return "image"
        }
    }

    static func imageDimensions(from url: URL) async -> (width: Double, height: Double)? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v", "avi"].contains(ext)
        
        if isVideo {
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                if let size = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let finalSize = size.applying(transform)
                    return (Double(abs(finalSize.width)), Double(abs(finalSize.height)))
                }
            }
            return (640, 360) // Fallback video size
        }

        guard let nsImage = NSImage(contentsOf: url) else { return nil }

        if let rep = nsImage.representations.first {
            let w = rep.pixelsWide
            let h = rep.representationsHigh
            if w > 0 && h > 0 {
                return (Double(w), Double(h))
            }
        }

        let size = nsImage.size
        guard size.width > 0 && size.height > 0 else { return nil }
        return (Double(size.width), Double(size.height))
    }

    static func imageDimensions(relativePath: String) async -> (width: Double, height: Double)? {
        let url = absolutePath(for: relativePath)
        let ext = url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v", "avi"].contains(ext)
        
        if isVideo {
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                if let size = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let finalSize = size.applying(transform)
                    return (Double(abs(finalSize.width)), Double(abs(finalSize.height)))
                }
            }
            return (640, 360) // Fallback
        }

        guard let nsImage = NSImage(contentsOf: url) else { return nil }

        if let rep = nsImage.representations.first {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > 0 && h > 0 {
                return (Double(w), Double(h))
            }
        }

        let size = nsImage.size
        guard size.width > 0 && size.height > 0 else { return nil }
        return (Double(size.width), Double(size.height))
    }

    /// Legacy convenience — use ImageCache.shared.fullImage instead for cached access.
    static func loadImage(relativePath: String) -> NSImage? {
        return ImageCache.shared.fullImage(for: relativePath)
    }
}

// Private helper to avoid compilation issue on older macOS versions
extension NSImageRep {
    fileprivate var representationsHigh: Int {
        return pixelsHigh
    }
}
