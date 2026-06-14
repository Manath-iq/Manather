//
//  BoardSelectionToolbar.swift
//  manather
//
//  The floating dark action bar that appears above a selected element:
//  duplicate, copy, bring forward, send backward, lock, delete (spec §7.1).
//

import SwiftUI

struct BoardSelectionToolbar: View {
    let isLocked: Bool
    let canCopy: Bool

    let onDuplicate: () -> Void
    let onCopy: () -> Void
    let onBringForward: () -> Void
    let onSendBackward: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("plus.square.on.square", help: "Duplicate", action: onDuplicate)
            if canCopy {
                button("doc.on.doc", help: "Copy image", action: onCopy)
            }
            button("arrow.up.square", help: "Bring forward", action: onBringForward)
            button("arrow.down.square", help: "Send backward", action: onSendBackward)
            button(isLocked ? "lock.fill" : "lock.open", help: isLocked ? "Unlock" : "Lock", action: onToggleLock)
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
