//
//  AssetIngest.swift
//  manather
//
//  One place that turns "stuff" (a file, an in-memory image, a URL, some text,
//  or a whole pasteboard) into AssetItems. Shared by drag & drop, the file
//  importer, ⌘V smart-paste and the global screenshot hotkey so they all behave
//  identically and stay in sync.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
enum AssetIngest {

    // MARK: - Files (drag & drop, importer, screenshots on disk)

    /// Copy a file into the sandbox and create the matching asset (image / gif /
    /// video / code snippet), extracting dimensions and code content as needed.
    static func ingestFile(at url: URL, into context: ModelContext) {
        Task {
            let type = FileManagerHelper.detectAssetType(for: url)

            var codeContent: String? = nil
            var codeLanguage: String? = nil
            if type == "codeSnippet" {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                codeContent = try? String(contentsOf: url, encoding: .utf8)
                codeLanguage = url.pathExtension.capitalized
            }

            let dims = await FileManagerHelper.imageDimensions(from: url)
            guard let relativePath = FileManagerHelper.copyFileToSandbox(from: url) else { return }
            let title = FileManagerHelper.displayName(from: url)
            let finalDims: (width: Double, height: Double)?
            if let dims {
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
                withAnimation(ManatherTheme.uiMotion) { context.insert(asset) }
                ColorIndexer.shared.ensureColors(for: asset)
            }
        }
    }

    // MARK: - Raw image data (screenshots, raw clipboard images)

    /// Write image bytes to the sandbox UNCHANGED — no decode/re-encode, so the
    /// full resolution, bit depth and embedded colour profile survive exactly as
    /// captured. Dimensions are read back from the saved file. This is the path
    /// the screenshot hotkey uses (the file `screencapture` produced is already a
    /// perfect PNG, so we just copy its bytes).
    static func ingestImageData(_ data: Data, ext: String, title: String, into context: ModelContext) {
        guard let relativePath = FileManagerHelper.saveImageData(data, baseName: title, ext: ext) else { return }
        Task {
            let dims = await FileManagerHelper.imageDimensions(relativePath: relativePath)
            let asset = AssetItem(
                title: title,
                relativeFilePath: relativePath,
                imageWidth: dims?.width ?? 0,
                imageHeight: dims?.height ?? 0,
                typeRaw: ext.lowercased() == "gif" ? "gif" : "image"
            )
            withAnimation(ManatherTheme.uiMotion) { context.insert(asset) }
            ColorIndexer.shared.ensureColors(for: asset)
        }
    }

    // MARK: - In-memory image (true bitmap with no source bytes — rare fallback)

    static func ingestImage(_ image: NSImage, title: String, into context: ModelContext) {
        guard let data = image.pngData(),
              let relativePath = FileManagerHelper.saveImageData(data, baseName: title, ext: "png") else { return }
        let size = image.pixelSize
        let asset = AssetItem(
            title: title,
            relativeFilePath: relativePath,
            imageWidth: size.width,
            imageHeight: size.height,
            typeRaw: "image"
        )
        withAnimation(ManatherTheme.uiMotion) { context.insert(asset) }
        ColorIndexer.shared.ensureColors(for: asset)
    }

    // MARK: - Pasted bitmap (clipboard) with optional web-original upgrade

    /// Save a bitmap copied to the clipboard. Browsers put the on-screen (often
    /// CSS-downscaled) bitmap on the clipboard — e.g. a 736 px Pinterest pin —
    /// NOT the original file. When the clipboard also carries the image's source
    /// URL we fetch the full-resolution original and keep it instead, but only if
    /// it really has more pixels. Falls back to the clipboard bytes on any failure
    /// so paste never breaks or hangs indefinitely.
    static func ingestClipboardImage(_ clipboardData: Data, ext: String, sourceURL: URL?,
                                     title: String, into context: ModelContext) {
        Task {
            var data = clipboardData
            var finalExt = ext

            if let sourceURL,
               let remote = await downloadImage(from: sourceURL),
               pixelArea(of: remote.data) > pixelArea(of: clipboardData) {
                data = remote.data
                finalExt = remote.ext
            }

            guard let relativePath = FileManagerHelper.saveImageData(data, baseName: title, ext: finalExt) else { return }
            let dims = await FileManagerHelper.imageDimensions(relativePath: relativePath)
            let asset = AssetItem(
                title: title,
                relativeFilePath: relativePath,
                imageWidth: dims?.width ?? 0,
                imageHeight: dims?.height ?? 0,
                typeRaw: finalExt.lowercased() == "gif" ? "gif" : "image"
            )
            withAnimation(ManatherTheme.uiMotion) { context.insert(asset) }
            ColorIndexer.shared.ensureColors(for: asset)
        }
    }

    // MARK: - Web link (mirrors AddWebLinkSheet)

    static func ingestWebLink(_ url: URL, into context: ModelContext) {
        Task {
            var pageTitle = url.host ?? "Web Link"
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let html = String(data: data, encoding: .utf8),
                   let range = html.range(of: "<title>([^<]+)</title>", options: [.regularExpression, .caseInsensitive]) {
                    let clean = html[range]
                        .replacingOccurrences(of: "<title>", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { pageTitle = clean }
                }
            } catch { /* keep host as fallback */ }

            await MainActor.run {
                let asset = AssetItem(
                    title: pageTitle,
                    relativeFilePath: "",
                    sourceURL: url.absoluteString,
                    typeRaw: "webLink"
                )
                context.insert(asset)
                WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: context)
            }
        }
    }

    // MARK: - Plain text → code snippet

    static func ingestText(_ text: String, into context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? "Snippet"
        let title = String(firstLine.prefix(48))
        let asset = AssetItem(
            title: title,
            relativeFilePath: "",
            typeRaw: "codeSnippet",
            codeLanguage: "Text",
            codeContent: trimmed
        )
        withAnimation(ManatherTheme.uiMotion) { context.insert(asset) }
    }

    // MARK: - Smart paste

    /// Inspect a pasteboard and create the most appropriate asset. Order matters:
    /// real files first (preserve the original), then raw image data, then a URL
    /// string, then any other text.
    @discardableResult
    static func ingestPasteboard(_ pb: NSPasteboard, into context: ModelContext) -> Bool {
        // 1. File(s) copied in Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls { ingestFile(at: url, into: context) }
            return true
        }

        // 2. Raw bitmap (image copied from a browser, screenshot in clipboard…).
        //    Save the original clipboard bytes losslessly, and — when the source
        //    URL is also on the clipboard — try to upgrade to the full-res original.
        if let bitmap = pasteboardImageData(pb) {
            ingestClipboardImage(bitmap.data, ext: bitmap.ext,
                                 sourceURL: webImageURL(from: pb),
                                 title: "Pasted Image", into: context)
            return true
        }

        // 3. Text: a URL becomes a web link, anything else a snippet.
        if let raw = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            if let url = webURL(from: raw) {
                ingestWebLink(url, into: context)
            } else {
                ingestText(raw, into: context)
            }
            return true
        }

        return false
    }

    // MARK: - Clipboard image helpers

    /// Pull encoded image bytes off a pasteboard without going through NSImage.
    /// Prefers PNG, then converts TIFF→PNG once (lossless, keeps the colour
    /// profile), and only as a last resort rasterises any NSImage on the board.
    private static func pasteboardImageData(_ pb: NSPasteboard) -> (data: Data, ext: String)? {
        if let png = pb.data(forType: .png) {
            return (png, "png")
        }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let png = images.first?.pngData() {
            return (png, "png")
        }
        return nil
    }

    /// Browsers copy the displayed (downscaled) bitmap but also include the
    /// page's `<img>` markup or the image's URL. Mine that for the original
    /// image address so we can fetch full-resolution pixels.
    private static func webImageURL(from pb: NSPasteboard) -> URL? {
        if let html = pb.string(forType: .html), let url = firstImageSrc(inHTML: html) {
            return url
        }
        if let url = NSURL(from: pb) as URL?, looksLikeImageURL(url) {
            return url
        }
        return nil
    }

    private static func firstImageSrc(inHTML html: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        guard let url = URL(string: String(html[r])),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private static func looksLikeImageURL(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]

    /// Pixel count (width × height) of encoded image data, read from metadata
    /// only — no full decode. Returns 0 if the data isn't a readable image.
    private static func pixelArea(of data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return 0 }
        return w * h
    }

    /// Download an image from its source URL. Returns the bytes and a file
    /// extension, or nil on any error / non-image response. Bounded timeout so a
    /// slow site can't make paste hang.
    private static func downloadImage(from url: URL) async -> (data: Data, ext: String)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !data.isEmpty, CGImageSourceCreateWithData(data as CFData, nil) != nil else { return nil }
            return (data, imageExtension(url: url, response: response) ?? "png")
        } catch {
            return nil
        }
    }

    private static func imageExtension(url: URL, response: URLResponse) -> String? {
        let pathExt = url.pathExtension.lowercased()
        if imageExtensions.contains(pathExt) {
            return pathExt == "jpeg" ? "jpg" : pathExt
        }
        if let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if mime.contains("png") { return "png" }
            if mime.contains("jpeg") || mime.contains("jpg") { return "jpg" }
            if mime.contains("gif") { return "gif" }
            if mime.contains("webp") { return "webp" }
            if mime.contains("heic") { return "heic" }
        }
        return nil
    }

    /// Treats a single-line, space-free string that looks like a domain/URL as a
    /// web address; returns nil for ordinary text.
    private static func webURL(from string: String) -> URL? {
        guard !string.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let lower = string.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: string)
        }
        // Bare domain like "example.com/path" → assume https.
        if string.contains("."),
           string.range(of: #"^[\w-]+(\.[\w-]+)+(/.*)?$"#, options: .regularExpression) != nil {
            return URL(string: "https://" + string)
        }
        return nil
    }
}

// MARK: - NSImage helpers

extension NSImage {
    /// PNG data for the image's first bitmap representation.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Pixel dimensions (not points), used to store the asset's aspect ratio.
    var pixelSize: (width: Double, height: Double) {
        if let rep = representations.first, rep.pixelsWide > 0 {
            return (Double(rep.pixelsWide), Double(rep.pixelsHigh))
        }
        return (Double(size.width), Double(size.height))
    }
}
