//
//  BoardColorSwatches.swift
//  manather
//
//  A small grid of colour swatches used by the board's text/note formatting bar
//  and the shape colour picker. Visual circles instead of raw hex strings.
//

import SwiftUI

struct BoardColorSwatches: View {
    let colors: [String]
    let selected: String?
    let onPick: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                Button {
                    onPick(hex)
                } label: {
                    Circle()
                        .fill(Color(boardHex: hex))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(
                                selected == hex ? ManatherTheme.accent : Color.white.opacity(0.25),
                                lineWidth: selected == hex ? 2.5 : 1
                            )
                        )
                        .overlay {
                            if selected == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(contrastColor(for: hex))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 180)
        .background(Color(red: 0.14, green: 0.14, blue: 0.155))
    }

    /// Pick a readable check-mark colour for a given swatch.
    private func contrastColor(for hex: String) -> Color {
        let rgb = ColorIndex.parseHex(hex) ?? (r: 0, g: 0, b: 0)
        let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
        return luminance > 0.6 ? .black : .white
    }
}
