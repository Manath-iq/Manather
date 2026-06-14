//
//  BoardSelectionToolbar.swift
//  manather
//
//  The floating dark action bar that appears above a selected element:
//  colour (shapes), duplicate, copy, bring forward, send backward, lock,
//  delete (spec §7.1).
//

import SwiftUI

struct BoardSelectionToolbar: View {
    @Bindable var item: BoardItem
    let onBeginChange: () -> Void   // snapshot for undo before a colour change

    let onDuplicate: () -> Void
    let onCopy: () -> Void
    let onBringForward: () -> Void
    let onSendBackward: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void

    @State private var showColorPopover = false

    private var canCopy: Bool { item.kind == .image }
    private var canColor: Bool { item.kind == .shape }

    var body: some View {
        HStack(spacing: 2) {
            if canColor {
                colorButton
            }
            button("plus.square.on.square", help: "Duplicate", action: onDuplicate)
            if canCopy {
                button("doc.on.doc", help: "Copy image", action: onCopy)
            }
            button("arrow.up.square", help: "Bring forward", action: onBringForward)
            button("arrow.down.square", help: "Send backward", action: onSendBackward)
            button(item.isLocked ? "lock.fill" : "lock.open", help: item.isLocked ? "Unlock" : "Lock", action: onToggleLock)
            button("trash", help: "Delete", action: onDelete, destructive: true)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.40), radius: 14, y: 6)
    }

    private var colorButton: some View {
        Button {
            showColorPopover = true
        } label: {
            Circle()
                .fill(Color(boardHex: item.fillColorHex ?? BoardPalette.defaultShapeFill))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help("Color")
        .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
            BoardColorSwatches(colors: BoardPalette.fills, selected: item.fillColorHex) { hex in
                onBeginChange()
                item.fillColorHex = hex
                showColorPopover = false
            }
        }
    }

    private func button(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void,
        destructive: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(destructive ? Color(red: 0.95, green: 0.42, blue: 0.40) : .white.opacity(0.85))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help(help)
    }
}
