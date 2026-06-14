//
//  BoardModels.swift
//  manather
//
//  Data model for the Space / Board feature — an infinite mood-board canvas
//  that lives inside a Project. A Project (AssetItem.spaceName) can have many
//  Boards; each Board holds free-form BoardItems (images, notes, text, shapes,
//  frames). See SPACE_BOARD_SPEC.md for the full design.
//

import Foundation
import SwiftData

// MARK: - Enums
// Computed wrappers over raw strings (like AssetType) so unknown values from an
// older/newer store never crash — they fall back to a sensible default.

enum BoardItemKind: String, Codable {
    case image
    case note
    case text
    case shape
    case frame
}

enum ShapeKind: String, Codable {
    case rectangle
    case ellipse
    case triangle
    case line
    case arrow
    case elbowArrow
}

enum TextAlign: String, Codable {
    case leading
    case center
    case trailing
}

// MARK: - Board

/// Metadata for one board. Many boards can belong to a single project
/// (linked by `projectName == AssetItem.spaceName`).
@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var projectName: String
    var dateCreated: Date
    var dateModified: Date

    // Viewport state — so the board reopens exactly where it was left.
    var cameraX: Double
    var cameraY: Double
    var zoom: Double

    // Cascade delete: removing a board removes all of its items.
    @Relationship(deleteRule: .cascade, inverse: \BoardItem.board)
    var items: [BoardItem] = []

    init(
        title: String = "Untitled board",
        details: String = "",
        projectName: String,
        cameraX: Double = 0,
        cameraY: Double = 0,
        zoom: Double = 1.0
    ) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.projectName = projectName
        self.dateCreated = Date()
        self.dateModified = Date()
        self.cameraX = cameraX
        self.cameraY = cameraY
        self.zoom = zoom
    }
}

// MARK: - BoardItem

/// One element on the canvas. A single universal model (kind in `kindRaw`)
/// keeps us from multiplying model types.
@Model
final class BoardItem {
    @Attribute(.unique) var id: UUID
    var board: Board?

    var kindRaw: String

    // Geometry in canvas coordinates (not screen pixels).
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double = 0
    var zIndex: Int
    var isLocked: Bool = false

    // image: reference to a library AssetItem (resolved by id).
    var assetID: UUID? = nil

    // note / text:
    var text: String? = nil
    var fontName: String? = nil
    var fontSize: Double? = nil
    var isBold: Bool = false
    var isItalic: Bool = false
    var textAlignRaw: String? = nil
    var textColorHex: String? = nil
    var fillColorHex: String? = nil

    // shape:
    var shapeKindRaw: String? = nil

    // frame:
    var frameTitle: String? = nil

    var kind: BoardItemKind {
        get { BoardItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var shapeKind: ShapeKind {
        get { ShapeKind(rawValue: shapeKindRaw ?? "") ?? .rectangle }
        set { shapeKindRaw = newValue.rawValue }
    }

    var textAlign: TextAlign {
        get { TextAlign(rawValue: textAlignRaw ?? "") ?? .leading }
        set { textAlignRaw = newValue.rawValue }
    }

    init(
        kind: BoardItemKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        zIndex: Int = 0,
        assetID: UUID? = nil,
        text: String? = nil,
        fillColorHex: String? = nil,
        shapeKind: ShapeKind? = nil,
        frameTitle: String? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.zIndex = zIndex
        self.assetID = assetID
        self.text = text
        self.fillColorHex = fillColorHex
        self.shapeKindRaw = shapeKind?.rawValue
        self.frameTitle = frameTitle
    }
}

// MARK: - Undo snapshot

/// A plain-value copy of a BoardItem's state. The undo/redo history stores
/// arrays of these so we can restore the whole layout (including re-creating
/// deleted items) without holding onto SwiftData objects. See spec §6.4.
struct BoardItemSnapshot {
    var id: UUID
    var kindRaw: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var zIndex: Int
    var isLocked: Bool
    var assetID: UUID?
    var text: String?
    var fontName: String?
    var fontSize: Double?
    var isBold: Bool
    var isItalic: Bool
    var textAlignRaw: String?
    var textColorHex: String?
    var fillColorHex: String?
    var shapeKindRaw: String?
    var frameTitle: String?

    init(_ item: BoardItem) {
        id = item.id
        kindRaw = item.kindRaw
        x = item.x
        y = item.y
        width = item.width
        height = item.height
        rotation = item.rotation
        zIndex = item.zIndex
        isLocked = item.isLocked
        assetID = item.assetID
        text = item.text
        fontName = item.fontName
        fontSize = item.fontSize
        isBold = item.isBold
        isItalic = item.isItalic
        textAlignRaw = item.textAlignRaw
        textColorHex = item.textColorHex
        fillColorHex = item.fillColorHex
        shapeKindRaw = item.shapeKindRaw
        frameTitle = item.frameTitle
    }

    /// Copy this state onto an existing item.
    func apply(to item: BoardItem) {
        item.kindRaw = kindRaw
        item.x = x
        item.y = y
        item.width = width
        item.height = height
        item.rotation = rotation
        item.zIndex = zIndex
        item.isLocked = isLocked
        item.assetID = assetID
        item.text = text
        item.fontName = fontName
        item.fontSize = fontSize
        item.isBold = isBold
        item.isItalic = isItalic
        item.textAlignRaw = textAlignRaw
        item.textColorHex = textColorHex
        item.fillColorHex = fillColorHex
        item.shapeKindRaw = shapeKindRaw
        item.frameTitle = frameTitle
    }

    /// Re-create a deleted item, preserving its id so references stay stable.
    func makeItem() -> BoardItem {
        let item = BoardItem(
            kind: BoardItemKind(rawValue: kindRaw) ?? .note,
            x: x, y: y, width: width, height: height, zIndex: zIndex
        )
        item.id = id
        apply(to: item)
        return item
    }
}
