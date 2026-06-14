//
//  BoardCanvasView.swift
//  manather
//
//  The board canvas: a dot grid that pans and zooms with the camera, plus the
//  zoom controls in the bottom-right. Phase 2 ships an empty, navigable canvas;
//  items and toolbars arrive in later phases (see SPACE_BOARD_SPEC.md §9).
//

import SwiftUI
import SwiftData
import AppKit

struct BoardCanvasView: View {
    @Bindable var board: Board
    @Bindable var vm: BoardViewModel
    let assetByID: [UUID: AssetItem]
    let onItemInteractionBegan: () -> Void
    let onBackgroundTap: (CGPoint) -> Void   // screen point of a tap on empty canvas

    @Environment(\.modelContext) private var modelContext

    // Gesture baselines (captured on gesture start).
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var scrollMonitor: Any?
    @State private var viewSize: CGSize = .zero

    // Rubber-band shape being drawn (shape tools).
    @State private var draftItem: BoardItem?
    @State private var draftStart: CGPoint = .zero

    private let baseGridSpacing: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            canvasBody(geo: geo)
        }
    }

    // Reading vm.zoom / vm.pan here (during body evaluation) registers them as
    // dependencies, so the Canvas redraws whenever the camera moves.
    private func canvasBody(geo: GeometryProxy) -> some View {
        let zoom = vm.zoom
        let pan = vm.pan

        return ZStack {
            // Dark canvas backdrop with a dot grid that tracks the camera.
            Canvas { context, size in
                drawDotGrid(context: context, size: size, zoom: zoom, pan: pan)
            }
            .background(ManatherTheme.viewerBackground)
            .contentShape(Rectangle())
            .gesture(backgroundDragGesture)
            .gesture(magnifyGesture)
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        switch vm.tool {
                        case .addNote, .addText:
                            onBackgroundTap(value.location)
                        default:
                            vm.selectedItemID = nil
                            vm.editingItemID = nil
                        }
                    }
            )

            // Item layer — each item computes its own screen rect from the camera.
            ForEach(board.items.sorted { $0.zIndex < $1.zIndex }, id: \.id) { item in
                BoardItemView(
                    item: item,
                    asset: item.assetID.flatMap { assetByID[$0] },
                    zoom: zoom,
                    pan: pan,
                    isSelected: vm.selectedItemID == item.id,
                    isInteractive: vm.tool == .select,
                    isEditing: vm.editingItemID == item.id,
                    onSelect: { vm.selectedItemID = item.id },
                    onBeginInteraction: onItemInteractionBegan,
                    onBeginEditing: {
                        vm.selectedItemID = item.id
                        vm.editingItemID = item.id
                    },
                    onEndEditing: {
                        if vm.editingItemID == item.id { vm.editingItemID = nil }
                    },
                    onCommit: {}
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(ManatherTheme.uiMotion, value: board.items.count)
        .onAppear {
            viewSize = geo.size
            vm.viewportSize = geo.size
            installScrollMonitor()
        }
        .onChange(of: geo.size) { _, newValue in
            viewSize = newValue
            vm.viewportSize = newValue
        }
        .onDisappear {
            removeScrollMonitor()
            vm.persist(to: board)
        }
        .overlay(alignment: .bottomTrailing) {
            zoomControls
                .padding(.trailing, 18)
                .padding(.bottom, 18)
        }
    }

    // MARK: - Dot grid

    private func drawDotGrid(context: GraphicsContext, size: CGSize, zoom: CGFloat, pan: CGSize) {
        let spacing = baseGridSpacing * zoom
        guard spacing >= 6 else { return } // too dense to be useful — skip

        let radius: CGFloat = max(0.8, 1.1 * min(zoom, 1.4))
        let color = Color.white.opacity(0.10)

        // First dot positions: pan offset wrapped into [-spacing, 0).
        var startX = pan.width.truncatingRemainder(dividingBy: spacing)
        if startX > 0 { startX -= spacing }
        var startY = pan.height.truncatingRemainder(dividingBy: spacing)
        if startY > 0 { startY -= spacing }

        var y = startY
        while y < size.height + spacing {
            var x = startX
            while x < size.width + spacing {
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                x += spacing
            }
            y += spacing
        }
    }

    // MARK: - Gestures

    /// Screen point → canvas point using the current camera.
    private func canvasPoint(_ screen: CGPoint) -> CGPoint {
        CGPoint(
            x: (screen.x - vm.pan.width) / vm.zoom,
            y: (screen.y - vm.pan.height) / vm.zoom
        )
    }

    /// One drag on empty canvas: pans, or rubber-band-draws a shape when a
    /// shape tool is active.
    private var backgroundDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if vm.tool.createsByDrag {
                    updateDraft(value)
                } else {
                    if panStart == nil { panStart = vm.pan }
                    let base = panStart ?? vm.pan
                    vm.pan = CGSize(
                        width: base.width + value.translation.width,
                        height: base.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if vm.tool.createsByDrag {
                    finishDraft()
                } else {
                    panStart = nil
                    vm.persist(to: board)
                }
            }
    }

    private func updateDraft(_ value: DragGesture.Value) {
        if draftItem == nil {
            onItemInteractionBegan() // undo snapshot before adding
            draftStart = canvasPoint(value.startLocation)
            let item = makeDraftItem(at: draftStart)
            guard let item else { return }
            modelContext.insert(item)
            item.board = board
            draftItem = item
        }
        let cur = canvasPoint(value.location)
        draftItem?.x = Double(min(draftStart.x, cur.x))
        draftItem?.y = Double(min(draftStart.y, cur.y))
        draftItem?.width = Double(max(1, abs(cur.x - draftStart.x)))
        draftItem?.height = Double(max(1, abs(cur.y - draftStart.y)))
    }

    /// Build the item being rubber-band-drawn for the current tool.
    private func makeDraftItem(at start: CGPoint) -> BoardItem? {
        switch vm.tool {
        case .addShape(let kind):
            let baseZ = board.items.map { $0.zIndex }.max() ?? 0
            let isStroke = kind == .line || kind == .arrow || kind == .elbowArrow
            let item = BoardItem(
                kind: .shape,
                x: Double(start.x), y: Double(start.y),
                width: 1, height: 1,
                zIndex: baseZ + 1,
                shapeKind: kind
            )
            item.fillColorHex = isStroke ? BoardPalette.defaultStroke : BoardPalette.defaultShapeFill
            return item
        case .addFrame:
            // Frames sit behind everything else so they act as containers.
            let minZ = board.items.map { $0.zIndex }.min() ?? 0
            let item = BoardItem(
                kind: .frame,
                x: Double(start.x), y: Double(start.y),
                width: 1, height: 1,
                zIndex: minZ - 1
            )
            item.frameTitle = "Frame"
            return item
        default:
            return nil
        }
    }

    private func finishDraft() {
        if let item = draftItem {
            if item.width < 6 && item.height < 6 {
                modelContext.delete(item) // a click, not a drag — discard
            } else {
                vm.selectedItemID = item.id
            }
            draftItem = nil
        }
        vm.tool = .select
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if zoomStart == nil { zoomStart = vm.zoom }
                let base = zoomStart ?? vm.zoom
                // Anchor pinch zoom at the viewport center (cursor anchoring for
                // pinch isn't exposed by SwiftUI; scroll-zoom uses the cursor).
                let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                let target = vm.clampedZoom(base * scale)
                vm.applyZoom(factor: target / vm.zoom, around: center)
            }
            .onEnded { _ in
                zoomStart = nil
                vm.persist(to: board)
            }
    }

    // MARK: - Scroll wheel (trackpad pan, ⌘-scroll zoom)

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.modifierFlags.contains(.command) {
                // Zoom toward the cursor.
                let factor = 1 - event.scrollingDeltaY * 0.01
                let anchor = cursorPoint(for: event)
                vm.applyZoom(factor: factor, around: anchor)
            } else {
                vm.pan = CGSize(
                    width: vm.pan.width + event.scrollingDeltaX,
                    height: vm.pan.height + event.scrollingDeltaY
                )
            }
            vm.persist(to: board)
            return nil // consume so the gallery underneath doesn't also scroll
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    /// Best-effort cursor location in this view's coordinate space (top-left
    /// origin). Falls back to the viewport center if the window isn't found.
    private func cursorPoint(for event: NSEvent) -> CGPoint {
        guard let window = event.window, let contentView = window.contentView else {
            return CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        }
        let inContent = contentView.convert(event.locationInWindow, from: nil)
        // AppKit's content view is bottom-left origin; flip to top-left.
        return CGPoint(x: inContent.x, y: contentView.bounds.height - inContent.y)
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        HStack(spacing: 2) {
            zoomButton(symbol: "minus") {
                let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                vm.applyZoom(factor: 0.9, around: center)
                vm.persist(to: board)
            }

            Text("\(Int((vm.zoom * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 52)
                .contentShape(Rectangle())
                .onTapGesture {
                    let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                    vm.applyZoom(factor: 1.0 / vm.zoom, around: center) // reset to 100%
                    vm.persist(to: board)
                }

            zoomButton(symbol: "plus") {
                let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                vm.applyZoom(factor: 1.1, around: center)
                vm.persist(to: board)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private func zoomButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
    }
}
