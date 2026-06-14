//
//  BoardTextToolbar.swift
//  manather
//
//  Top-center formatting bar shown when a note or text item is selected:
//  font, size, bold, italic, alignment, text color, and (for notes) fill
//  color. Dark styling like the other board panels (spec §7.6).
//

import SwiftUI

struct BoardTextToolbar: View {
    @Bindable var item: BoardItem
    let onBeginChange: () -> Void   // snapshot for undo before a formatting change

    @State private var showTextColor = false
    @State private var showFillColor = false

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { item.fontSize ?? 16 },
            set: { item.fontSize = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Font (placeholder — system font for now).
            Text("Sans")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))

            sizeStepper
            divider

            toggle("bold", isOn: item.isBold) { onBeginChange(); item.isBold.toggle() }
            toggle("italic", isOn: item.isItalic) { onBeginChange(); item.isItalic.toggle() }
            divider

            alignButton(.leading, "text.alignleft")
            alignButton(.center, "text.aligncenter")
            alignButton(.trailing, "text.alignright")
            divider

            textColorMenu
            if item.kind == .note {
                fillColorMenu
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.14, green: 0.14, blue: 0.155))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.40), radius: 16, y: 8)
    }

    // MARK: - Pieces

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18)
    }

    private var sizeStepper: some View {
        HStack(spacing: 4) {
            stepButton("minus") {
                onBeginChange()
                fontSizeBinding.wrappedValue = max(8, fontSizeBinding.wrappedValue - 1)
            }
            Text("\(Int(fontSizeBinding.wrappedValue))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22)
            stepButton("plus") {
                onBeginChange()
                fontSizeBinding.wrappedValue = min(200, fontSizeBinding.wrappedValue + 1)
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
    }

    private func toggle(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? .white : .white.opacity(0.6))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? ManatherTheme.accent.opacity(0.9) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
    }

    private func alignButton(_ align: TextAlign, _ symbol: String) -> some View {
        let isOn = item.textAlign == align
        return Button {
            onBeginChange()
            item.textAlign = align
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? .white : .white.opacity(0.6))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? ManatherTheme.accent.opacity(0.9) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
    }

    private var textColorMenu: some View {
        Button {
            showTextColor = true
        } label: {
            HStack(spacing: 3) {
                Text("A")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(boardHex: item.textColorHex ?? BoardPalette.defaultNoteText))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 30, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help("Text color")
        .popover(isPresented: $showTextColor, arrowEdge: .bottom) {
            BoardColorSwatches(colors: BoardPalette.texts, selected: item.textColorHex) { hex in
                onBeginChange()
                item.textColorHex = hex
                showTextColor = false
            }
        }
    }

    private var fillColorMenu: some View {
        Button {
            showFillColor = true
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color(boardHex: item.fillColorHex ?? BoardPalette.defaultNoteFill))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 34, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.microAnimated)
        .help("Note color")
        .popover(isPresented: $showFillColor, arrowEdge: .bottom) {
            BoardColorSwatches(colors: BoardPalette.fills, selected: item.fillColorHex) { hex in
                onBeginChange()
                item.fillColorHex = hex
                showFillColor = false
            }
        }
    }
}
