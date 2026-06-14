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

    var body: some View {
        VStack(spacing: 4) {
            toolButton(
                symbol: "cursorarrow",
                help: "Select / Move",
                isActive: vm.tool == .select
            ) {
                vm.tool = .select
            }

            toolButton(
                symbol: "photo.badge.plus",
                help: "Add image",
                isActive: vm.showLibraryPanel
            ) {
                vm.tool = .select
                vm.showLibraryPanel = true
            }
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
    }

    private func toolButton(
        symbol: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive ? ManatherTheme.accent.opacity(0.9) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help(help)
    }
}
