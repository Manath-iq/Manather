//
//  BoardView.swift
//  manather
//
//  Root screen of a single board: a top bar (back + editable title) over the
//  dark canvas. Phase 1 ships an empty canvas; the canvas mechanics (grid,
//  pan/zoom, items, toolbars) arrive in later phases — see SPACE_BOARD_SPEC.md §9.
//

import SwiftUI
import SwiftData

struct BoardView: View {
    @Bindable var board: Board
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            // Dark canvas backdrop (same charcoal as the asset viewer).
            ManatherTheme.viewerBackground
                .ignoresSafeArea()

            // Empty-canvas hint (placeholder until Phase 2 adds the dot grid).
            VStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
                Text("Empty board")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.30))
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
            }
        }
        .background(KeyEventDismiss { onClose() })
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
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
