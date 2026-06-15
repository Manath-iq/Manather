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
                withAnimation(.spring(response: 0.4)) { context.insert(asset) }
                ColorIndexer.shared.ensureColors(for: asset)
            }
        }
    }

    // MARK: - In-memory image (pasted bitmap, screenshot)

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
        withAnimation(.spring(response: 0.4)) { context.insert(asset) }
        ColorIndexer.shared.ensureColors(for: asset)
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
        withAnimation(.spring(response: 0.4)) { context.insert(asset) }
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
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            ingestImage(image, title: "Pasted Image", into: context)
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
