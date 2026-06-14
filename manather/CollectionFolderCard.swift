//
//  CollectionFolderCard.swift
//  manather
//
//  The card shown for a collection on the Collections tab: a fanned stack of
//  square-cropped preview tiles with the name and save count below. Hovering
//  spreads the tiles apart for a tactile, "deck of cards" feel.
//

import SwiftUI

struct CollectionFolderCard: View {
    let title: String
    let count: Int
    let items: [AssetItem]
    let isDarkMode: Bool

    @State private var isHovered = false

    /// Up to four tiles make the fan; more than that just adds clutter.
    private var previews: [AssetItem] { Array(items.prefix(4)) }

    private let tileSize: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )

                if previews.isEmpty {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(ManatherTheme.accent.opacity(0.8))
                } else {
                    fannedStack
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isDarkMode ? Color.white : Color.primary)
                    .lineLimit(1)
                Text("\(count) \(count == 1 ? "save" : "saves")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDarkMode ? Color.white.opacity(0.5) : Color.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.68), value: isHovered)
    }

    // MARK: - Fanned tiles

    private var fannedStack: some View {
        ZStack {
            // Draw back-to-front so index 0 (the front tile) sits on top.
            ForEach(Array(previews.enumerated().reversed()), id: \.element.id) { index, item in
                let t = transform(for: index)
                tile(item)
                    .rotationEffect(.degrees(t.angle))
                    .scaleEffect(1 - CGFloat(index) * 0.035)
                    .offset(x: t.x, y: t.y)
                    .zIndex(Double(previews.count - index))
            }
        }
    }

    private func tile(_ item: AssetItem) -> some View {
        Group {
            if !item.relativeFilePath.isEmpty {
                CachedImageView(relativePath: item.relativeFilePath, maxSize: 240, contentMode: .fill)
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.22, blue: 0.26),
                                Color(red: 0.13, green: 0.14, blue: 0.17)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: tileSize, height: tileSize)
                    .overlay(
                        Image(systemName: item.assetType.iconName)
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
        // White photo frame + soft shadow, like a stack of prints.
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white)
        )
        .shadow(color: .black.opacity(0.18), radius: 5, x: -1, y: 3)
    }

    /// Per-tile rotation/offset. Tiles fan out to the left; hovering widens the
    /// spread. Index 0 is the front tile (tilted slightly the other way).
    private func transform(for index: Int) -> (angle: Double, x: CGFloat, y: CGFloat) {
        if index == 0 {
            return isHovered ? (7, 8, -2) : (4, 0, 0)
        }
        let i = Double(index)
        if isHovered {
            return (i * -12.5, CGFloat(i) * -13, CGFloat(i) * -10)
        } else {
            return (i * -6.5, CGFloat(i) * -5, CGFloat(i) * -4.5)
        }
    }
}
