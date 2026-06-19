//
//  AssetItem.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import Foundation
import SwiftData

enum AssetType: String, Codable {
    case image
    case video
    case gif
    case webLink
    case codeSnippet
    case mcpServer   // MCP server config: launch command + JSON config in codeContent
    case skill       // Markdown instructions for an AI agent (Claude Code skill etc.)

    var iconName: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .gif: return "photo.stack"
        case .webLink: return "globe"
        case .codeSnippet: return "curlybraces"
        case .mcpServer: return "server.rack"
        case .skill: return "sparkles.rectangle.stack"
        }
    }
}

@Model
final class AssetItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var relativeFilePath: String
    var sourceURL: String
    var prompt: String
    var notes: String
    var isTrash: Bool
    var dateAdded: Date
    var imageWidth: Double
    var imageHeight: Double
    
    // New fields for multi-format support
    var typeRaw: String = "image"
    var codeLanguage: String? = nil
    var codeContent: String? = nil
    var dominantColorsHex: [String]? = nil
    
    // Grouping support.
    // `collectionNames` is the source of truth for membership (an asset can be in
    // several collections at once). `collectionName` is kept as the "primary"
    // collection (= the first one) so older code and library archives that expect
    // a single value keep working.
    var collectionName: String? = nil
    var collectionNames: [String] = []
    var spaceName: String? = nil

    // Which library this asset belongs to. Optional so older stores migrate
    // cleanly (nil = adopted by the default library on first launch — see
    // LibraryManager.adoptOrphans).
    var libraryID: UUID? = nil

    // Soft-delete flag (set before modelContext.delete so animations finish cleanly)
    var isDeleted: Bool = false

    // Tags (flat string array — fast for small libraries, no join overhead)
    var tags: [String] = []

    var assetType: AssetType {
        get { AssetType(rawValue: typeRaw) ?? .image }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Collection membership (many-to-many)

    /// Not filed under any collection.
    var isUnassigned: Bool { collectionNames.isEmpty }

    func inCollection(_ name: String) -> Bool { collectionNames.contains(name) }

    func addToCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !collectionNames.contains(trimmed) else { return }
        collectionNames.append(trimmed)
        collectionName = collectionNames.first
    }

    func removeFromCollection(_ name: String) {
        collectionNames.removeAll { $0 == name }
        collectionName = collectionNames.first
    }

    /// Toggle membership; returns the new state (true = now in the collection).
    @discardableResult
    func toggleCollection(_ name: String) -> Bool {
        if inCollection(name) { removeFromCollection(name); return false }
        addToCollection(name); return true
    }

    /// Replace the full set of collections (de-duplicated, blanks dropped).
    func setCollections(_ names: [String]) {
        var seen = Set<String>()
        var result: [String] = []
        for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !name.isEmpty && seen.insert(name).inserted {
            result.append(name)
        }
        collectionNames = result
        collectionName = result.first
    }

    var aspectRatio: CGFloat {
        guard imageHeight > 0 else { return 1.0 }
        return CGFloat(imageWidth / imageHeight)
    }

    /// Returns the file extension uppercased (e.g. "JPEG", "PNG")
    var fileFormat: String {
        if assetType == .webLink { return "URL" }
        if assetType == .codeSnippet { return codeLanguage?.uppercased() ?? "CODE" }
        if assetType == .mcpServer { return "MCP" }
        if assetType == .skill { return "SKILL" }

        let ext = (relativeFilePath as NSString).pathExtension.uppercased()
        if ext == "JPG" { return "JPEG" }
        return ext.isEmpty ? "IMG" : ext
    }

    init(
        title: String,
        relativeFilePath: String,
        sourceURL: String = "",
        prompt: String = "",
        notes: String = "",
        imageWidth: Double = 0,
        imageHeight: Double = 0,
        typeRaw: String = "image",
        codeLanguage: String? = nil,
        codeContent: String? = nil,
        dominantColorsHex: [String]? = nil,
        collectionName: String? = nil,
        collectionNames: [String] = [],
        spaceName: String? = nil,
        libraryID: UUID? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.relativeFilePath = relativeFilePath
        self.sourceURL = sourceURL
        self.prompt = prompt
        self.notes = notes
        self.isTrash = false
        self.dateAdded = Date()
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.typeRaw = typeRaw
        self.codeLanguage = codeLanguage
        self.codeContent = codeContent
        self.dominantColorsHex = dominantColorsHex
        // Reconcile the two membership fields: prefer an explicit list, else derive
        // it from the single legacy name. Keep `collectionName` pointed at the first.
        let resolved = collectionNames.isEmpty
            ? (collectionName.flatMap { $0.isEmpty ? nil : [$0] } ?? [])
            : collectionNames
        self.collectionNames = resolved
        self.collectionName = resolved.first
        self.spaceName = spaceName
        // Fall back to whatever library is active so anything created through the
        // normal UI lands in the right place; the importer passes an explicit id.
        self.libraryID = libraryID ?? LibraryManager.activeLibraryID
        self.isDeleted = false
        self.tags = tags
    }
}
