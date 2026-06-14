//
//  BoardViewModel.swift
//  manather
//
//  Shared state for one open board: the canvas camera (pan + zoom), and — in
//  later phases — the active tool, selection and undo/redo history. Kept in one
//  place so the canvas and every toolbar work off the same source of truth.
//

import SwiftUI

@Observable
final class BoardViewModel {
    // Canvas camera. `pan` is the screen-space offset of the canvas origin;
    // `zoom` is the canvas scale (1.0 == 100%). A canvas point p maps to screen
    // as:  screen = p * zoom + pan.
    var zoom: CGFloat
    var pan: CGSize

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

    /// Save the camera back into the board so it reopens where it was left.
    func persist(to board: Board) {
        board.cameraX = Double(pan.width)
        board.cameraY = Double(pan.height)
        board.zoom = Double(zoom)
    }
}
