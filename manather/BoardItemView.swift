//
//  BoardItemView.swift
//  manather
//
//  Renders one element on the canvas and handles move + resize when selected.
//  Phase 3 covers image items; notes/text/shapes/frames are added in later
//  phases (see SPACE_BOARD_SPEC.md §7).
//

import SwiftUI

struct BoardItemView: View {
    @Bindable var item: BoardItem
    let asset: AssetItem?
    let zoom: CGFloat
    let pan: CGSize
    let isSelected: Bool
    let isInteractive: Bool   // true when the Select tool is active
    let onSelect: () -> Void
    let onCommit: () -> Void   // called when a move/resize finishes (persist hook)

    @State private var moveStart: CGPoint?
    @State private var resizeStart: CGRect?

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    // Screen geometry derived from the camera. Item geometry is stored as
    // Double (canvas space); the camera is CGFloat — convert as we project.
    private var screenSize: CGSize {
        CGSize(width: CGFloat(item.width) * zoom, height: CGFloat(item.height) * zoom)
    }
    private var screenCenter: CGPoint {
        CGPoint(
            x: (CGFloat(item.x) + CGFloat(item.width) / 2) * zoom + pan.width,
            y: (CGFloat(item.y) + CGFloat(item.height) / 2) * zoom + pan.height
        )
    }

    var body: some View {
        ZStack {
            content
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.30), radius: 8, y: 4)
                .contentShape(Rectangle())
                .gesture(moveGesture, including: isInteractive ? .all : .subviews)

            if isSelected {
                selectionOverlay
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .position(screenCenter)
    }

    // MARK: - Content per kind

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let asset, !asset.relativeFilePath.isEmpty {
                CachedImageView(
                    relativePath: asset.relativeFilePath,
                    maxSize: max(120, min(1600, screenSize.width * 2))
                )
            } else {
                placeholder
            }
        default:
            // Other kinds land in later phases.
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Selection overlay (border + corner handles)

    private var selectionOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ManatherTheme.accent, lineWidth: 1.5)
                .allowsHitTesting(false)

            handle(.topLeft)
            handle(.topRight)
            handle(.bottomLeft)
            handle(.bottomRight)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    private func handle(_ corner: Corner) -> some View {
        let w = screenSize.width
        let h = screenSize.height
        let pos: CGPoint
        switch corner {
        case .topLeft:     pos = CGPoint(x: 0, y: 0)
        case .topRight:    pos = CGPoint(x: w, y: 0)
        case .bottomLeft:  pos = CGPoint(x: 0, y: h)
        case .bottomRight: pos = CGPoint(x: w, y: h)
        }
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(ManatherTheme.accent, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .position(pos)
            .gesture(resizeGesture(corner))
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if moveStart == nil {
                    moveStart = CGPoint(x: item.x, y: item.y)
                    onSelect()
                }
                guard let start = moveStart, !item.isLocked else { return }
                item.x = Double(start.x) + Double(value.translation.width / zoom)
                item.y = Double(start.y) + Double(value.translation.height / zoom)
            }
            .onEnded { _ in
                moveStart = nil
                onCommit()
            }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStart == nil {
                    resizeStart = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
                    onSelect()
                }
                guard let s = resizeStart, !item.isLocked else { return }
                let dx = value.translation.width / zoom
                let dy = value.translation.height / zoom
                let minSize: CGFloat = 30

                var nx = s.minX, ny = s.minY, nw = s.width, nh = s.height
                switch corner {
                case .bottomRight:
                    nw = s.width + dx; nh = s.height + dy
                case .bottomLeft:
                    nx = s.minX + dx; nw = s.width - dx; nh = s.height + dy
                case .topRight:
                    ny = s.minY + dy; nw = s.width + dx; nh = s.height - dy
                case .topLeft:
                    nx = s.minX + dx; ny = s.minY + dy; nw = s.width - dx; nh = s.height - dy
                }
                if nw >= minSize { item.x = Double(nx); item.width = Double(nw) }
                if nh >= minSize { item.y = Double(ny); item.height = Double(nh) }
            }
            .onEnded { _ in
                resizeStart = nil
                onCommit()
            }
    }
}
