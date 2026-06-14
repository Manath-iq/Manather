//
//  BoardViewModel.swift
//  manather
//
//  Shared state for one open board: the canvas camera (pan + zoom), and — in
//  later phases — the active tool, selection and undo/redo history. Kept in one
//  place so the canvas and every toolbar work off the same source of truth.
//

import SwiftUI

/// Which tool the canvas is currently in. Grows in later phases (shapes, frame);
/// Phase 5 adds note + text on top of select / addImage.
enum BoardTool: Equatable {
    case select
    case addImage
    case addNote
    case addText
    case addShape(ShapeKind)

    var isShape: Bool {
        if case .addShape = self { return true }
        return false
    }
}

/// Colors used by the board text/note toolbar.
enum BoardPalette {
    /// Note / shape fill swatches (yellow sticky is the default).
    static let fills = ["#FCEFA8", "#FFD3B6", "#FFAAA5", "#D5F5E3", "#AED9E0", "#C9C7F5", "#FFFFFF", "#2B2B2B"]
    /// Text color swatches.
    static let texts = ["#1A1A1A", "#FFFFFF", "#E74C3C", "#27AE60", "#2980B9", "#8E44AD", "#F39C12"]

    static let defaultNoteFill = "#FCEFA8"
    static let defaultNoteText = "#1A1A1A"
    static let defaultText = "#FFFFFF"
    static let defaultShapeFill = "#C9C7F5"
    static let defaultStroke = "#FFFFFF"
}

extension Color {
    /// Build a Color from a "#RRGGBB" string, falling back to a neutral gray.
    init(boardHex hex: String) {
        let rgb = ColorIndex.parseHex(hex) ?? (r: 0.5, g: 0.5, b: 0.5)
        self = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

@Observable
final class BoardViewModel {
    // Canvas camera. `pan` is the screen-space offset of the canvas origin;
    // `zoom` is the canvas scale (1.0 == 100%). A canvas point p maps to screen
    // as:  screen = p * zoom + pan.
    var zoom: CGFloat
    var pan: CGSize

    // Interaction state.
    var tool: BoardTool = .select
    var selectedItemID: UUID?
    var editingItemID: UUID?           // note/text currently being typed into
    var showLibraryPanel: Bool = false
    var showShapeFlyout: Bool = false
    /// Current size of the canvas viewport (kept in sync by the canvas) so we
    /// can place new items near the center of what the user is looking at.
    var viewportSize: CGSize = .zero

    // Undo / redo history — arrays of layout snapshots (see BoardItemSnapshot).
    // Kept in memory only, capped so the history can't grow without bound.
    var undoStack: [[BoardItemSnapshot]] = []
    var redoStack: [[BoardItemSnapshot]] = []
    static let maxHistory = 40

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 4.0

    init(board: Board) {
        let z = CGFloat(board.zoom)
        self.zoom = z > 0 ? min(max(z, BoardViewModel.minZoom), BoardViewModel.maxZoom) : 1.0
        self.pan = CGSize(width: board.cameraX, height: board.cameraY)
    }

    /// Clamp a zoom value into the allowed range.
    func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, BoardViewModel.minZoom), BoardViewModel.maxZoom)
    }

    /// Zoom by a factor while keeping the canvas point under `anchor`
    /// (a screen-space point) fixed on screen.
    func applyZoom(factor: CGFloat, around anchor: CGPoint) {
        let newZoom = clampedZoom(zoom * factor)
        guard newZoom != zoom else { return }
        // canvas point currently under the anchor
        let canvasX = (anchor.x - pan.width) / zoom
        let canvasY = (anchor.y - pan.height) / zoom
        zoom = newZoom
        // keep that canvas point under the anchor after zooming
        pan = CGSize(
            width: anchor.x - canvasX * newZoom,
            height: anchor.y - canvasY * newZoom
        )
    }

    /// The canvas point currently at the center of the viewport.
    func viewportCenterInCanvas() -> CGPoint {
        let screenCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (screenCenter.x - pan.width) / zoom,
            y: (screenCenter.y - pan.height) / zoom
        )
    }

    /// Save the camera back into the board so it reopens where it was left.
    func persist(to board: Board) {
        board.cameraX = Double(pan.width)
        board.cameraY = Double(pan.height)
        board.zoom = Double(zoom)
    }
}
