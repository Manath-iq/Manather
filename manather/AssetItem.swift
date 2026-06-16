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
    
    // Grouping support
    var collectionName: String? = nil
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
        self.collectionName = collectionName
        self.spaceName = spaceName
        // Fall back to whatever library is active so anything created through the
        // normal UI lands in the right place; the importer passes an explicit id.
        self.libraryID = libraryID ?? LibraryManager.activeLibraryID
        self.isDeleted = false
        self.tags = tags
    }
}
