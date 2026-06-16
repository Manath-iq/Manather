//
//  BoardItemView.swift
//  manather
//
//  Renders one element on the canvas and handles move + resize when selected.
//  Phase 3 covers image items; notes/text/shapes/frames are added in later
//  phases (see SPACE_BOARD_SPEC.md §7).
//

import SwiftUI
import AppKit

struct BoardItemView: View {
    @Bindable var item: BoardItem
    let asset: AssetItem?
    let zoom: CGFloat
    let pan: CGSize
    let isSelected: Bool
    let isInteractive: Bool   // true when the Select tool is active
    let isEditing: Bool       // text/note being typed into
    var isExport: Bool = false // static render for PNG export (no async images)
    let onSelect: () -> Void
    let onBeginInteraction: () -> Void  // snapshot for undo before a move/resize
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void
    let onCommit: () -> Void   // called when a move/resize finishes (persist hook)

    // Live drag/resize happen in local @State only (no per-tick database writes,
    // which is what made dragging stutter). The final geometry is committed to
    // the model once, on gesture end.
    @State private var isDragging = false
    @State private var dragTranslation: CGSize = .zero
    @State private var resizingCorner: Corner?
    @State private var resizeTranslation: CGSize = .zero
    @State private var isRotating = false
    @FocusState private var isTextFocused: Bool

    private var textBinding: Binding<String> {
        Binding(get: { item.text ?? "" }, set: { item.text = $0 })
    }
    private var frameTitleBinding: Binding<String> {
        Binding(get: { item.frameTitle ?? "" }, set: { item.frameTitle = $0 })
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private static let minSize: CGFloat = 30

    // The item's canvas-space (unrotated) rect, with any in-progress resize
    // applied live. Rotation is applied separately when rendering; here we work
    // out the new box so that the corner opposite the dragged one stays put on
    // screen even when the item is rotated.
    private var canvasRect: CGRect {
        let w0 = CGFloat(item.width)
        let h0 = CGFloat(item.height)

        guard let corner = resizingCorner else {
            return CGRect(x: item.x, y: item.y, width: w0, height: h0)
        }

        let cx0 = CGFloat(item.x) + w0 / 2   // old center, canvas space
        let cy0 = CGFloat(item.y) + h0 / 2

        // The drag is in screen space; convert to canvas units, then rotate into
        // the item's own (unrotated) axes so a corner drag resizes along the
        // item's edges no matter how it's turned.
        let theta = CGFloat(item.rotation) * .pi / 180
        let cosT = cos(theta), sinT = sin(theta)
        let dCanvasX = resizeTranslation.width / zoom
        let dCanvasY = resizeTranslation.height / zoom
        let localDx =  cosT * dCanvasX + sinT * dCanvasY
        let localDy = -sinT * dCanvasX + cosT * dCanvasY

        let rightSide = corner == .bottomRight || corner == .topRight
        let bottomSide = corner == .bottomRight || corner == .bottomLeft

        var w = w0
        var h = h0
        if item.kind == .image, w0 > 0, h0 > 0 {
            // Images keep their aspect ratio; the axis you move more leads.
            let assetRatio = asset?.aspectRatio ?? 0
            let ratio = assetRatio > 0 ? assetRatio : (w0 / h0)
            if abs(localDx) >= abs(localDy) {
                w = w0 + (rightSide ? localDx : -localDx)
                h = w / ratio
            } else {
                h = h0 + (bottomSide ? localDy : -localDy)
                w = h * ratio
            }
            if w < Self.minSize { w = Self.minSize; h = w / ratio }
            if h < Self.minSize { h = Self.minSize; w = h * ratio }
        } else {
            w = max(Self.minSize, w0 + (rightSide ? localDx : -localDx))
            h = max(Self.minSize, h0 + (bottomSide ? localDy : -localDy))
        }

        // Keep the opposite corner fixed in canvas space. Its local sign is the
        // negation of the side being dragged.
        let fx: CGFloat = rightSide ? -1 : 1
        let fy: CGFloat = bottomSide ? -1 : 1
        let f0x = fx * w0 / 2, f0y = fy * h0 / 2
        let fixedX = cx0 + (cosT * f0x - sinT * f0y)
        let fixedY = cy0 + (sinT * f0x + cosT * f0y)
        let f1x = fx * w / 2, f1y = fy * h / 2
        let cx = fixedX - (cosT * f1x - sinT * f1y)
        let cy = fixedY - (sinT * f1x + cosT * f1y)

        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    // Screen geometry derived from the camera + live drag offset.
    private var screenSize: CGSize {
        CGSize(width: canvasRect.width * zoom, height: canvasRect.height * zoom)
    }
    private var screenCenter: CGPoint {
        CGPoint(
            x: canvasRect.midX * zoom + pan.width + dragTranslation.width,
            y: canvasRect.midY * zoom + pan.height + dragTranslation.height
        )
    }

    private var isTextual: Bool { item.kind == .note || item.kind == .text }
    private var isEditable: Bool { item.kind == .note || item.kind == .text || item.kind == .frame }

    var body: some View {
        ZStack {
            content
                .frame(width: screenSize.width, height: screenSize.height)
                .modifier(ConditionalRoundedClip(radius: 8, enabled: item.kind == .image || item.kind == .note))
                .shadow(color: .black.opacity(item.kind == .image || item.kind == .note ? 0.30 : 0), radius: 8, y: 4)
                .contentShape(Rectangle())
                .gesture(moveGesture, including: (isInteractive && !isEditing) ? .all : .subviews)
                .modifier(DoubleTapToEdit(enabled: isEditable && isInteractive, action: onBeginEditing))

            if isSelected {
                selectionOverlay
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        // Rotate around the item's OWN center. This must come BEFORE .position:
        // .position expands to fill the whole canvas, so a .rotationEffect placed
        // after it would pivot around the canvas center instead — which made a
        // rotated item drift away from its toolbar/handles and drag in the wrong
        // direction (drag up → moved sideways).
        .rotationEffect(.degrees(item.rotation))
        .position(screenCenter)
        .onChange(of: isEditing) { _, editing in
            isTextFocused = editing
        }
        .onChange(of: isTextFocused) { _, focused in
            if !focused && isEditing { onEndEditing() }
        }
        .onAppear {
            if isEditing { isTextFocused = true }
        }
    }

    // MARK: - Content per kind

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let asset, !asset.relativeFilePath.isEmpty {
                if isExport {
                    SyncImageView(path: asset.relativeFilePath)
                } else {
                    CachedImageView(
                        relativePath: asset.relativeFilePath,
                        maxSize: max(120, min(1600, screenSize.width * 2))
                    )
                }
            } else {
                placeholder
            }
        case .note:
            textBody(isNote: true)
        case .text:
            textBody(isNote: false)
        case .shape:
            shapeBody
        case .frame:
            frameBody
        }
    }

    // MARK: - Frame

    @ViewBuilder
    private var frameBody: some View {
        let titleSize = max(8, 12 * zoom)
        let lineWidth = max(1, 1.5 * zoom)
        let radius = max(2, 6 * zoom)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.02))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    Color.white.opacity(0.35),
                    style: StrokeStyle(lineWidth: lineWidth, dash: [6 * zoom, 4 * zoom])
                )

            Group {
                if isEditing {
                    TextField("Frame", text: frameTitleBinding)
                        .textFieldStyle(.plain)
                        .focused($isTextFocused)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(item.frameTitle?.isEmpty == false ? item.frameTitle! : "Frame")
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, max(3, 8 * zoom))
            .padding(.vertical, max(2, 5 * zoom))
        }
    }

    // MARK: - Shapes

    @ViewBuilder
    private var shapeBody: some View {
        let isStroke = item.shapeKind == .line || item.shapeKind == .arrow || item.shapeKind == .elbowArrow
        let hex = item.fillColorHex ?? (isStroke ? BoardPalette.defaultStroke : BoardPalette.defaultShapeFill)
        let color = Color(boardHex: hex)
        let lineWidth = max(1.5, 3 * zoom)
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        Group {
            switch item.shapeKind {
            case .rectangle:
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
            case .ellipse:
                Ellipse().fill(color)
            case .triangle:
                TriangleShape().fill(color)
            case .line:
                LineShape().stroke(color, style: strokeStyle)
            case .arrow:
                ArrowShape().stroke(color, style: strokeStyle)
            case .elbowArrow:
                ElbowArrowShape().stroke(color, style: strokeStyle)
            }
        }
        // Reflect line/arrow strokes to honor the drag direction (the box stays
        // the same; only the diagonal the stroke runs along flips). No effect on
        // filled shapes, whose flip flags are always false.
        .scaleEffect(
            x: isStroke && item.flipH ? -1 : 1,
            y: isStroke && item.flipV ? -1 : 1
        )
    }

    // MARK: - Note / text rendering

    private var textFont: Font {
        let size = CGFloat(item.fontSize ?? 16) * zoom
        var f = Font.system(size: max(4, size), weight: item.isBold ? .bold : .regular)
        if item.isItalic { f = f.italic() }
        return f
    }

    private var swiftAlignment: TextAlignment {
        switch item.textAlign {
        case .center: return .center
        case .trailing: return .trailing
        case .leading: return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch item.textAlign {
        case .center: return .top
        case .trailing: return .topTrailing
        case .leading: return .topLeading
        }
    }

    @ViewBuilder
    private func textBody(isNote: Bool) -> some View {
        let textColor = Color(boardHex: item.textColorHex ?? (isNote ? BoardPalette.defaultNoteText : BoardPalette.defaultText))
        let pad = max(4, 10 * zoom)

        ZStack {
            if isNote {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(boardHex: item.fillColorHex ?? BoardPalette.defaultNoteFill))
            }

            Group {
                if isEditing {
                    TextEditor(text: textBinding)
                        .focused($isTextFocused)
                        .font(textFont)
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(swiftAlignment)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .tint(ManatherTheme.accent)
                } else if isNote {
                    // A note shows its text in a scroll view so text that doesn't
                    // fit can be read by scrolling — no need to resize the note or
                    // double-click into edit mode. The canvas forwards wheel events
                    // to this view when the cursor is over a note (BoardCanvasView).
                    ScrollView(.vertical) {
                        Text(displayText)
                            .font(textFont)
                            .foregroundStyle(item.text?.isEmpty == false ? textColor : textColor.opacity(0.4))
                            .multilineTextAlignment(swiftAlignment)
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(displayText)
                        .font(textFont)
                        .foregroundStyle(item.text?.isEmpty == false ? textColor : textColor.opacity(0.4))
                        .multilineTextAlignment(swiftAlignment)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                }
            }
            .padding(pad)
        }
    }

    private var displayText: String {
        if let t = item.text, !t.isEmpty { return t }
        return item.kind == .note ? "Note" : "Text"
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
            rotationHandle
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    /// A small knob on a stalk above the top edge that rotates the item. It sits
    /// inside the selection overlay, so it rides along as the item turns.
    private var rotationHandle: some View {
        let w = screenSize.width
        let stalk: CGFloat = 22
        return ZStack {
            Rectangle()
                .fill(ManatherTheme.accent)
                .frame(width: 1.5, height: stalk)
                .position(x: w / 2, y: -stalk / 2)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(ManatherTheme.accent, lineWidth: 1.5))
                .frame(width: 12, height: 12)
                .position(x: w / 2, y: -stalk)
                .gesture(rotateGesture)
        }
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
        // Measure the drag in the window's coordinate space, NOT the item's own
        // (.local) space. The item moves while you drag it (via .position), so a
        // .local gesture's origin moves too — that feedback loop made dragging
        // stutter and the item jump to the wrong spot on release. .global is
        // fixed on screen, so the reported translation is the true pointer move.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onSelect()
                    if !item.isLocked { onBeginInteraction() }
                }
                guard !item.isLocked else { return }
                dragTranslation = value.translation // visual only — no DB write
            }
            .onEnded { value in
                defer {
                    dragTranslation = .zero
                    isDragging = false
                }
                guard !item.isLocked else { return }
                // Commit the final position to the model once.
                item.x += Double(value.translation.width / zoom)
                item.y += Double(value.translation.height / zoom)
                onCommit()
            }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        // Same reasoning as moveGesture: the handle rides along with the item as
        // it resizes, so measure in the fixed .global space to avoid feedback.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if resizingCorner == nil {
                    resizingCorner = corner
                    onSelect()
                    if !item.isLocked { onBeginInteraction() }
                }
                guard !item.isLocked else { return }
                resizeTranslation = value.translation // visual only — no DB write
            }
            .onEnded { _ in
                defer {
                    resizingCorner = nil
                    resizeTranslation = .zero
                }
                guard !item.isLocked else { return }
                // Commit the live rect (which already includes the resize) once.
                let rect = canvasRect
                item.x = Double(rect.minX)
                item.y = Double(rect.minY)
                item.width = Double(rect.width)
                item.height = Double(rect.height)
                onCommit()
            }
    }

    private var rotateGesture: some Gesture {
        // Measured in global space (the knob moves while you turn it, so a local
        // gesture would feed back). The angle is taken from the item's center to
        // the cursor; the knob sits above center, hence the +90° offset.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isRotating {
                    isRotating = true
                    onSelect()
                    if !item.isLocked { onBeginInteraction() }
                }
                guard !item.isLocked else { return }
                let center = screenCenter
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                let degrees = angle * 180 / .pi + 90
                item.rotation = Double(snappedAngle(degrees))
            }
            .onEnded { _ in
                defer { isRotating = false }
                guard !item.isLocked else { return }
                onCommit()
            }
    }

    /// Normalize to [0, 360) and gently snap near each 45° step so it's easy to
    /// land on straight angles.
    private func snappedAngle(_ degrees: CGFloat) -> CGFloat {
        var a = degrees.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        for step in stride(from: CGFloat(0), through: 360, by: 45) {
            if abs(a - step) <= 5 { return step.truncatingRemainder(dividingBy: 360) }
        }
        return a
    }
}

/// Loads an image synchronously for PNG export (ImageRenderer can't wait for
/// the async CachedImageView). Prefers the in-memory cache, else reads the file.
private struct SyncImageView: View {
    let path: String

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.white.opacity(0.06)
        }
    }

    private func loadImage() -> NSImage? {
        ImageCache.shared.cachedFullImage(for: path)
            ?? NSImage(contentsOf: FileManagerHelper.absolutePath(for: path))
    }
}

/// Adds a double-click-to-edit gesture only for editable (note/text) items.
private struct DoubleTapToEdit: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(count: 2, perform: action)
        } else {
            content
        }
    }
}

/// Rounds the corners only for items that should be clipped (image, note).
private struct ConditionalRoundedClip: ViewModifier {
    let radius: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
        }
    }
}

// MARK: - Shape geometry

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct LineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        addArrowHead(to: &p, from: start, to: end)
        return p
    }
}

struct ElbowArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let elbow = CGPoint(x: rect.maxX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        var p = Path()
        p.move(to: start)
        p.addLine(to: elbow)
        p.addLine(to: end)
        addArrowHead(to: &p, from: elbow, to: end)
        return p
    }
}

/// Append a small arrowhead at `to`, pointing along the `from`→`to` direction.
private func addArrowHead(to path: inout Path, from: CGPoint, to: CGPoint) {
    let angle = atan2(to.y - from.y, to.x - from.x)
    let length = max(8, min(22, hypot(to.x - from.x, to.y - from.y) * 0.25))
    let spread = CGFloat.pi * 0.82
    let p1 = CGPoint(x: to.x + cos(angle + spread) * length, y: to.y + sin(angle + spread) * length)
    let p2 = CGPoint(x: to.x + cos(angle - spread) * length, y: to.y + sin(angle - spread) * length)
    path.move(to: to)
    path.addLine(to: p1)
    path.move(to: to)
    path.addLine(to: p2)
}
