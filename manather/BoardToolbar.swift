//
//  BoardToolbar.swift
//  manather
//
//  The left floating tool palette (dark, rounded — same look as our custom
//  context menu). Phase 3 ships Select + Add image; later phases add notes,
//  text, shapes, frames, undo/redo and export (see SPACE_BOARD_SPEC.md §5).
//

import SwiftUI

struct BoardToolbar: View {
    @Bindable var vm: BoardViewModel
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                toolButton(
                    symbol: "cursorarrow",
                    help: "Select / Move",
                    isActive: vm.tool == .select
                ) {
                    vm.tool = .select
                    vm.showShapeFlyout = false
                }

                toolButton(
                    symbol: "photo.badge.plus",
                    help: "Add image",
                    isActive: vm.showLibraryPanel
                ) {
                    vm.tool = .select
                    vm.showShapeFlyout = false
                    vm.showLibraryPanel = true
                }

                toolButton(
                    symbol: "note.text",
                    help: "Add note (click the canvas)",
                    isActive: vm.tool == .addNote
                ) {
                    vm.tool = .addNote
                    vm.showShapeFlyout = false
                }

                toolButton(
                    symbol: "textformat",
                    help: "Add text (click the canvas)",
                    isActive: vm.tool == .addText
                ) {
                    vm.tool = .addText
                    vm.showShapeFlyout = false
                }

                toolButton(
                    symbol: "square.on.circle",
                    help: "Shapes",
                    isActive: vm.tool.isShape || vm.showShapeFlyout
                ) {
                    vm.showShapeFlyout.toggle()
                }

                divider

                toolButton(
                    symbol: "arrow.uturn.backward",
                    help: "Undo",
                    isActive: false,
                    isEnabled: vm.canUndo,
                    action: onUndo
                )

                toolButton(
                    symbol: "arrow.uturn.forward",
                    help: "Redo",
                    isActive: false,
                    isEnabled: vm.canRedo,
                    action: onRedo
                )
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)

            if vm.showShapeFlyout {
                shapeFlyout
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .animation(ManatherTheme.uiMotion, value: vm.showShapeFlyout)
    }

    // MARK: - Shape flyout

    private var shapeFlyout: some View {
        VStack(spacing: 2) {
            flyoutRow("Rectangle", "rectangle", "R", .rectangle)
            flyoutRow("Ellipse", "circle", "E", .ellipse)
            flyoutRow("Triangle", "triangle", "Y", .triangle)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 4).padding(.vertical, 2)
            flyoutRow("Line", "line.diagonal", "L", .line)
            flyoutRow("Arrow", "line.diagonal.arrow", "A", .arrow)
            flyoutRow("Elbow arrow", "arrow.turn.right.down", "B", .elbowArrow)
        }
        .padding(6)
        .frame(width: 188)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.40), radius: 22, x: 0, y: 12)
        .fixedSize()
    }

    private func flyoutRow(_ title: String, _ symbol: String, _ key: String, _ kind: ShapeKind) -> some View {
        ShapeFlyoutRow(title: title, symbol: symbol, key: key) {
            vm.tool = .addShape(kind)
            vm.showShapeFlyout = false
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 24, height: 1)
            .padding(.vertical, 2)
    }

    private func toolButton(
        symbol: String,
        help: String,
        isActive: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? .white : .white.opacity(isEnabled ? 0.65 : 0.25))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive ? ManatherTheme.accent.opacity(0.9) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .disabled(!isEnabled)
        .help(help)
    }
}

/// One row in the shape flyout (icon + name + hotkey hint), with hover highlight.
private struct ShapeFlyoutRow: View {
    let title: String
    let symbol: String
    let key: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(key)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
