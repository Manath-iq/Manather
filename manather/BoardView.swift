//
//  BoardView.swift
//  manather
//
//  Root screen of a single board: top bar (back + editable title), the canvas,
//  the left tool palette and the right Library panel. Images can be added from
//  the library and moved/resized on the canvas — see SPACE_BOARD_SPEC.md §9.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct BoardView: View {
    @Bindable var board: Board
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allAssets: [AssetItem]
    @FocusState private var isTitleFocused: Bool
    @State private var vm: BoardViewModel
    @State private var keyMonitor: Any?

    init(board: Board, onClose: @escaping () -> Void) {
        self._board = Bindable(board)
        self.onClose = onClose
        self._vm = State(initialValue: BoardViewModel(board: board))
    }

    // Live assets, used both to resolve image items and to feed the Library panel.
    private var liveAssets: [AssetItem] {
        allAssets.filter { !$0.isDeleted }
    }
    private var assetByID: [UUID: AssetItem] {
        Dictionary(liveAssets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var imageAssets: [AssetItem] {
        liveAssets.filter { !$0.isTrash && ($0.assetType == .image || $0.assetType == .gif) }
    }

    private var selectedItem: BoardItem? {
        guard let id = vm.selectedItemID else { return nil }
        return board.items.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The canvas (dot grid + pan/zoom + items). Fills the whole screen.
            BoardCanvasView(
                board: board,
                vm: vm,
                assetByID: assetByID,
                onItemInteractionBegan: { pushUndo() },
                onBackgroundTap: { handleCanvasTap(at: $0) }
            )
            .ignoresSafeArea()

            // Text/note formatting bar (top center) while a textual item is selected.
            if let item = selectedItem, item.kind == .note || item.kind == .text {
                BoardTextToolbar(item: item, onBeginChange: { pushUndo() })
                    .padding(.top, 64)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Floating action bar above the selected element.
            if let item = selectedItem {
                BoardSelectionToolbar(
                    item: item,
                    onBeginChange: { pushUndo() },
                    onDuplicate: duplicateSelected,
                    onCopy: copySelected,
                    onBringForward: bringSelectedForward,
                    onSendBackward: sendSelectedBackward,
                    onToggleLock: toggleSelectedLock,
                    onDelete: deleteSelected
                )
                .position(selectionToolbarPosition(for: item))
            }

            // Top bar floats over the canvas.
            VStack(spacing: 0) {
                topBar
                Spacer()
            }

            // Left tool palette.
            BoardToolbar(vm: vm, onUndo: undo, onRedo: redo, onExport: exportPNG)
                .padding(.leading, 16)
                .padding(.top, ManatherTheme.titleBarInset + 58)
        }
        .overlay(alignment: .trailing) {
            if vm.showLibraryPanel {
                BoardLibraryPanel(
                    assets: imageAssets,
                    onAdd: { addImages($0) },
                    onClose: { vm.showLibraryPanel = false }
                )
                .frame(maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.move(edge: .trailing))
            }
        }
        .background(KeyEventDismiss { close() })
        .animation(ManatherTheme.uiMotion, value: vm.showLibraryPanel)
        .onAppear {
            pruneDanglingItems()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Keyboard shortcuts

    /// A local key monitor handles board shortcuts. It deliberately ignores keys
    /// while a text field is editing, so typing in notes / titles still works.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let responder = event.window?.firstResponder
            if responder is NSTextView || responder is NSText {
                return event // a text field is focused — don't steal keys
            }

            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            let noModifiers = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Undo / redo
            if hasCommand && key == "z" {
                if hasShift { redo() } else { undo() }
                return nil
            }

            // Delete selected
            if event.keyCode == 51 || event.keyCode == 117 {
                if vm.selectedItemID != nil {
                    deleteSelected()
                    return nil
                }
                return event
            }

            // Tool shortcuts (no modifiers)
            if noModifiers {
                switch key {
                case "v": vm.tool = .select; return nil
                case "r": vm.tool = .addShape(.rectangle); return nil
                case "e": vm.tool = .addShape(.ellipse); return nil
                case "y": vm.tool = .addShape(.triangle); return nil
                case "l": vm.tool = .addShape(.line); return nil
                case "a": vm.tool = .addShape(.arrow); return nil
                case "b": vm.tool = .addShape(.elbowArrow); return nil
                default: break
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func close() {
        vm.persist(to: board)
        onClose()
    }

    // MARK: - Items

    /// Drop the chosen library images onto the canvas near the viewport center,
    /// cascaded slightly so they don't land exactly on top of each other.
    private func addImages(_ assets: [AssetItem]) {
        guard !assets.isEmpty else { return }
        let center = vm.viewportCenterInCanvas()
        let baseZ = board.items.map { $0.zIndex }.max() ?? 0

        for (index, asset) in assets.enumerated() {
            let width: Double = 240
            let ar = asset.aspectRatio > 0 ? Double(asset.aspectRatio) : 1
            let height = width / ar
            let shift = Double(index) * 28
            let item = BoardItem(
                kind: .image,
                x: Double(center.x) - width / 2 + shift,
                y: Double(center.y) - height / 2 + shift,
                width: width,
                height: height,
                zIndex: baseZ + 1 + index,
                assetID: asset.id
            )
            modelContext.insert(item)
            item.board = board
        }

        vm.showLibraryPanel = false
        vm.tool = .select
    }

    /// Create a note or text item where the user clicked (with the add tool).
    private func handleCanvasTap(at screenPoint: CGPoint) {
        let kind: BoardItemKind = vm.tool == .addText ? .text : .note
        pushUndo()
        let zoom = vm.zoom
        let pan = vm.pan
        let cx = Double((screenPoint.x - pan.width) / zoom)
        let cy = Double((screenPoint.y - pan.height) / zoom)
        let width: Double = kind == .note ? 170 : 200
        let height: Double = kind == .note ? 140 : 60
        let baseZ = board.items.map { $0.zIndex }.max() ?? 0

        let item = BoardItem(
            kind: kind,
            x: cx - width / 2,
            y: cy - height / 2,
            width: width,
            height: height,
            zIndex: baseZ + 1,
            text: "",
            fillColorHex: kind == .note ? BoardPalette.defaultNoteFill : nil
        )
        item.fontSize = kind == .note ? 16 : 20
        item.textColorHex = kind == .note ? BoardPalette.defaultNoteText : BoardPalette.defaultText
        item.textAlignRaw = TextAlign.leading.rawValue
        modelContext.insert(item)
        item.board = board

        vm.selectedItemID = item.id
        vm.editingItemID = item.id
        vm.tool = .select
    }

    // MARK: - Export

    /// Render the whole board (all items, with padding) to a PNG and save it via
    /// a save panel. No grid, no toolbars (spec §10).
    private func exportPNG() {
        let items = board.items
        guard !items.isEmpty else { return }

        let padding: CGFloat = 50

        // Compute the axis-aligned bounding box of every item accounting for
        // rotation — a rotated rect's extent is wider/taller than its raw w/h.
        var globalMinX = CGFloat.greatestFiniteMagnitude
        var globalMinY = CGFloat.greatestFiniteMagnitude
        var globalMaxX = -CGFloat.greatestFiniteMagnitude
        var globalMaxY = -CGFloat.greatestFiniteMagnitude

        for item in items {
            let cx = CGFloat(item.x) + CGFloat(item.width) / 2
            let cy = CGFloat(item.y) + CGFloat(item.height) / 2
            let w  = CGFloat(item.width)
            let h  = CGFloat(item.height)
            let θ  = CGFloat(item.rotation) * .pi / 180

            // Half-extents of the rotated rect projected onto the canvas axes.
            let halfW = (abs(w * cos(θ)) + abs(h * sin(θ))) / 2
            let halfH = (abs(w * sin(θ)) + abs(h * cos(θ))) / 2

            globalMinX = min(globalMinX, cx - halfW)
            globalMinY = min(globalMinY, cy - halfH)
            globalMaxX = max(globalMaxX, cx + halfW)
            globalMaxY = max(globalMaxY, cy + halfH)
        }

        let origin = CGPoint(x: globalMinX - padding, y: globalMinY - padding)
        let size = CGSize(
            width:  (globalMaxX - globalMinX) + padding * 2,
            height: (globalMaxY - globalMinY) + padding * 2
        )
        guard size.width > 1, size.height > 1 else { return }

        let renderer = ImageRenderer(
            content: BoardExportView(items: items, assetByID: assetByID, origin: origin, size: size)
        )
        renderer.scale = 2 // crisp on retina

        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (board.title.isEmpty ? "board" : board.title) + ".png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    /// Owner decision §12.4: if a board image's asset no longer exists in the
    /// library, just remove it from the board (no "unavailable" placeholder).
    private func pruneDanglingItems() {
        for item in board.items where item.kind == .image {
            let resolved = item.assetID.flatMap { assetByID[$0] }
            if resolved == nil {
                modelContext.delete(item)
            }
        }
    }

    // MARK: - Selection actions

    private func selectionToolbarPosition(for item: BoardItem) -> CGPoint {
        let zoom = vm.zoom
        let pan = vm.pan
        let centerX = (CGFloat(item.x) + CGFloat(item.width) / 2) * zoom + pan.width
        let topY = CGFloat(item.y) * zoom + pan.height
        // The rotation handle knob sits 22 pt above the item's top edge; push the
        // toolbar far enough above that so it never covers the handle.
        let y = max(60, topY - 54)
        let maxX = max(150, vm.viewportSize.width - 150)
        let x = min(max(centerX, 150), maxX)
        return CGPoint(x: x, y: y)
    }

    private func duplicateSelected() {
        guard let item = selectedItem else { return }
        pushUndo()
        let baseZ = board.items.map { $0.zIndex }.max() ?? 0
        let copy = BoardItem(
            kind: item.kind,
            x: item.x + 24,
            y: item.y + 24,
            width: item.width,
            height: item.height,
            zIndex: baseZ + 1,
            assetID: item.assetID,
            text: item.text,
            fillColorHex: item.fillColorHex,
            shapeKind: item.shapeKindRaw == nil ? nil : item.shapeKind,
            frameTitle: item.frameTitle
        )
        copy.rotation = item.rotation
        copy.flipH = item.flipH
        copy.flipV = item.flipV
        copy.fontName = item.fontName
        copy.fontSize = item.fontSize
        copy.isBold = item.isBold
        copy.isItalic = item.isItalic
        copy.textAlignRaw = item.textAlignRaw
        copy.textColorHex = item.textColorHex
        modelContext.insert(copy)
        copy.board = board
        vm.selectedItemID = copy.id
    }

    private func copySelected() {
        guard let item = selectedItem, item.kind == .image,
              let aid = item.assetID, let asset = assetByID[aid],
              !asset.relativeFilePath.isEmpty else { return }
        let url = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
        guard let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func bringSelectedForward() {
        guard let item = selectedItem else { return }
        pushUndo()
        let maxZ = board.items.map { $0.zIndex }.max() ?? 0
        item.zIndex = maxZ + 1
    }

    private func sendSelectedBackward() {
        guard let item = selectedItem else { return }
        pushUndo()
        let minZ = board.items.map { $0.zIndex }.min() ?? 0
        item.zIndex = minZ - 1
    }

    private func toggleSelectedLock() {
        guard let item = selectedItem else { return }
        pushUndo()
        item.isLocked.toggle()
    }

    private func deleteSelected() {
        guard let item = selectedItem else { return }
        pushUndo()
        modelContext.delete(item)
        vm.selectedItemID = nil
    }

    // MARK: - Undo / redo (snapshot-based, see spec §6.4)

    private func currentSnapshot() -> [BoardItemSnapshot] {
        board.items.map { BoardItemSnapshot($0) }
    }

    private func pushUndo() {
        vm.undoStack.append(currentSnapshot())
        if vm.undoStack.count > BoardViewModel.maxHistory {
            vm.undoStack.removeFirst()
        }
        vm.redoStack.removeAll()
    }

    private func undo() {
        guard let snapshot = vm.undoStack.popLast() else { return }
        vm.redoStack.append(currentSnapshot())
        applySnapshot(snapshot)
    }

    private func redo() {
        guard let snapshot = vm.redoStack.popLast() else { return }
        vm.undoStack.append(currentSnapshot())
        applySnapshot(snapshot)
    }

    /// Reconcile the board's items to match a snapshot: update existing items,
    /// delete extras, and re-create any that were removed.
    private func applySnapshot(_ snapshot: [BoardItemSnapshot]) {
        let byID = Dictionary(board.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let snapshotIDs = Set(snapshot.map { $0.id })

        // Remove items that aren't in the snapshot.
        for item in board.items where !snapshotIDs.contains(item.id) {
            modelContext.delete(item)
        }

        // Update existing items or re-create missing ones.
        for state in snapshot {
            if let item = byID[state.id] {
                state.apply(to: item)
            } else {
                let item = state.makeItem()
                modelContext.insert(item)
                item.board = board
            }
        }

        // Keep selection only if it still exists.
        if let id = vm.selectedItemID, !snapshotIDs.contains(id) {
            vm.selectedItemID = nil
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.microAnimated)
            .help("Back to boards")

            Spacer()

            TextField("Untitled board", text: $board.title)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .focused($isTitleFocused)
                .frame(maxWidth: 320)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isTitleFocused ? Color.white.opacity(0.10) : Color.clear)
                )
                .onChange(of: board.title) { _, _ in
                    board.dateModified = Date()
                }

            Spacer()

            // Right side intentionally empty (no Present mode — owner decision §12).
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, ManatherTheme.titleBarInset)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial.opacity(0.0)) // keep layout; bar floats over canvas
    }
}

/// Tiny helper so Esc closes the board (matches the viewer's Esc-to-close).
private struct KeyEventDismiss: NSViewRepresentable {
    var onEsc: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onEsc = onEsc
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyView)?.onEsc = onEsc
    }

    private final class KeyView: NSView {
        var onEsc: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Esc
                onEsc?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
