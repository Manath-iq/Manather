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

struct BoardView: View {
    @Bindable var board: Board
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allAssets: [AssetItem]
    @FocusState private var isTitleFocused: Bool
    @State private var vm: BoardViewModel

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The canvas (dot grid + pan/zoom + items). Fills the whole screen.
            BoardCanvasView(board: board, vm: vm, assetByID: assetByID)
                .ignoresSafeArea()

            // Top bar floats over the canvas.
            VStack(spacing: 0) {
                topBar
                Spacer()
            }

            // Left tool palette.
            BoardToolbar(vm: vm)
                .padding(.leading, 16)
                .padding(.top, 70)
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
        .onAppear { pruneDanglingItems() }
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
        .padding(.vertical, 12)
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
