//
//  LibraryArchive.swift
//  manather
//
//  Export a whole library (its assets + collections) to a shareable ZIP, and
//  import such a ZIP back as a brand-new library. The archive is self-contained:
//
//      <LibraryName>/
//        manifest.json     — names, prompts, notes, tags, collections, metadata
//        assets/           — the actual media files (images, gifs, videos)
//
//  Text-only assets (web links, code snippets, MCP configs, skills) keep their
//  content inside manifest.json, so no separate files are needed for them.
//
//  Export zips in-process via NSFileCoordinator (sandbox-safe — no `zip` binary).
//  Import unzips with ZipArchive and rebuilds the objects under a fresh Library.
//

import Foundation
import AppKit
import SwiftData
import UniformTypeIdentifiers

enum LibraryArchiveError: Error, LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "This ZIP isn't a Manather library (no manifest.json found)."
        }
    }
}

enum LibraryArchive {

    static let manifestName = "manifest.json"
    static let formatTag = "manather-library"

    // MARK: - Export

    /// Shows a save panel and writes the library as a `.zip`. Runs synchronously
    /// on the main actor so it can safely read the SwiftData asset objects.
    @MainActor
    static func export(libraryName: String, assets: [AssetItem], collections: [String]) {
        let panel = NSSavePanel()
        panel.title = "Export Library"
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = sanitized(libraryName) + ".zip"
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try writeArchive(to: dest, libraryName: libraryName, assets: assets, collections: collections)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            presentError("Export failed", error)
        }
    }

    @MainActor
    private static func writeArchive(to dest: URL, libraryName: String, assets: [AssetItem], collections: [String]) throws {
        let fm = FileManager.default
        let tmpRoot = fm.temporaryDirectory.appendingPathComponent("manather-export-\(UUID().uuidString)", isDirectory: true)
        let root = tmpRoot.appendingPathComponent(sanitized(libraryName), isDirectory: true)
        let assetsDir = root.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpRoot) }

        var assetEntries: [[String: Any]] = []
        for asset in assets where !asset.isDeleted {
            var entry: [String: Any] = [
                "id": asset.id.uuidString,
                "title": asset.title,
                "type": asset.typeRaw,
                "dateAdded": iso(asset.dateAdded),
                "isTrash": asset.isTrash
            ]
            if !asset.sourceURL.isEmpty { entry["sourceURL"] = asset.sourceURL }
            if !asset.prompt.isEmpty { entry["prompt"] = asset.prompt }
            if !asset.notes.isEmpty { entry["notes"] = asset.notes }
            if !asset.tags.isEmpty { entry["tags"] = asset.tags }
            if let name = asset.collectionName { entry["collectionName"] = name }
            if let lang = asset.codeLanguage { entry["codeLanguage"] = lang }
            if let content = asset.codeContent { entry["codeContent"] = content }
            if asset.imageWidth > 0 { entry["imageWidth"] = asset.imageWidth }
            if asset.imageHeight > 0 { entry["imageHeight"] = asset.imageHeight }
            if let colors = asset.dominantColorsHex, !colors.isEmpty { entry["dominantColorsHex"] = colors }

            // Copy the backing media file, if any.
            if !asset.relativeFilePath.isEmpty {
                let src = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                if fm.fileExists(atPath: src.path) {
                    let ext = src.pathExtension
                    let destName = ext.isEmpty ? asset.id.uuidString : "\(asset.id.uuidString).\(ext)"
                    try? fm.copyItem(at: src, to: assetsDir.appendingPathComponent(destName))
                    entry["file"] = "assets/\(destName)"
                }
            }
            assetEntries.append(entry)
        }

        let manifest: [String: Any] = [
            "format": formatTag,
            "version": 1,
            "exportedAt": iso(Date()),
            "library": ["name": libraryName],
            "collections": collections.map { ["name": $0] },
            "assets": assetEntries
        ]
        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: root.appendingPathComponent(manifestName))

        try zipFolder(at: root, to: dest)
    }

    /// Produce a real `.zip` of `folder` without an external tool. NSFileCoordinator's
    /// `.forUploading` option hands back a temporary zipped copy; we copy it out
    /// to the user's destination before the block returns (it's only valid inside).
    private static func zipFolder(at folder: URL, to dest: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { zipped in
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: zipped, to: dest)
            } catch {
                copyError = error
            }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
    }

    // MARK: - Import

    /// Unzip a shared library and rebuild it as a new `Library`. Returns the new
    /// library so the caller can switch to it. Runs on the main actor (SwiftData).
    @MainActor
    @discardableResult
    static func importArchive(from zipURL: URL, context: ModelContext) throws -> Library {
        let fm = FileManager.default
        let accessing = zipURL.startAccessingSecurityScopedResource()
        defer { if accessing { zipURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: zipURL)
        let tmp = fm.temporaryDirectory.appendingPathComponent("manather-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        try ZipArchive.unzip(data, to: tmp)

        guard let manifestURL = firstFile(named: manifestName, under: tmp),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any]
        else {
            throw LibraryArchiveError.invalidArchive
        }
        let baseDir = manifestURL.deletingLastPathComponent()

        let rawName = (manifest["library"] as? [String: Any])?["name"] as? String ?? "Imported Library"
        let library = Library(name: LibraryManager.uniqueName(rawName, context: context))
        context.insert(library)

        // Collections first, so assets referencing them line up.
        if let collections = manifest["collections"] as? [[String: Any]] {
            for entry in collections {
                if let name = entry["name"] as? String, !name.isEmpty {
                    context.insert(AssetCollection(name: name, libraryID: library.id))
                }
            }
        }

        if let assets = manifest["assets"] as? [[String: Any]] {
            for entry in assets {
                var relativePath = ""
                if let file = entry["file"] as? String {
                    let fileURL = baseDir.appendingPathComponent(file)
                    if fm.fileExists(atPath: fileURL.path),
                       let copied = FileManagerHelper.copyFileToSandbox(from: fileURL) {
                        relativePath = copied
                    }
                }

                let asset = AssetItem(
                    title: entry["title"] as? String ?? "Untitled",
                    relativeFilePath: relativePath,
                    sourceURL: entry["sourceURL"] as? String ?? "",
                    prompt: entry["prompt"] as? String ?? "",
                    notes: entry["notes"] as? String ?? "",
                    imageWidth: (entry["imageWidth"] as? NSNumber)?.doubleValue ?? 0,
                    imageHeight: (entry["imageHeight"] as? NSNumber)?.doubleValue ?? 0,
                    typeRaw: entry["type"] as? String ?? "image",
                    codeLanguage: entry["codeLanguage"] as? String,
                    codeContent: entry["codeContent"] as? String,
                    dominantColorsHex: entry["dominantColorsHex"] as? [String],
                    collectionName: entry["collectionName"] as? String,
                    spaceName: nil,
                    libraryID: library.id,
                    tags: entry["tags"] as? [String] ?? []
                )
                asset.isTrash = entry["isTrash"] as? Bool ?? false
                context.insert(asset)
            }
        }

        try? context.save()
        return library
    }

    // MARK: - Helpers

    private static func firstFile(named target: String, under root: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker where url.lastPathComponent == target {
            return url
        }
        return nil
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(mapped))
        return result.isEmpty ? "library" : result
    }

    @MainActor
    private static func presentError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
