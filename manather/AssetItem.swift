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
        spaceName: String? = nil
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
    }
}
