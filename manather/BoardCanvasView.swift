//
//  BoardCanvasView.swift
//  manather
//
//  The board canvas: a dot grid that pans and zooms with the camera, plus the
//  zoom controls in the bottom-right. Phase 2 ships an empty, navigable canvas;
//  items and toolbars arrive in later phases (see SPACE_BOARD_SPEC.md §9).
//

import SwiftUI
import AppKit

struct BoardCanvasView: View {
    @Bindable var board: Board
    @Bindable var vm: BoardViewModel

    // Gesture baselines (captured on gesture start).
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var scrollMonitor: Any?
    @State private var viewSize: CGSize = .zero

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
            .gesture(panGesture)
            .gesture(magnifyGesture)

            // Item layer (empty for now). Items will be placed in canvas
            // coordinates and transformed by the camera in later phases.
            Color.clear
                .allowsHitTesting(false)
        }
        .onAppear {
            viewSize = geo.size
            installScrollMonitor()
        }
        .onChange(of: geo.size) { _, newValue in
            viewSize = newValue
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

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if panStart == nil { panStart = vm.pan }
                let base = panStart ?? vm.pan
                vm.pan = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStart = nil
                vm.persist(to: board)
            }
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
