//
//  AssetCardView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssetCardView: View {
    let asset: AssetItem
    let isSelected: Bool
    let isTrashView: Bool
    var maxImageSize: CGFloat = 500
    let onSelect: () -> Void
    /// Right-click — reports the card's frame (in the gallery space) so the
    /// custom context menu can position itself.
    let onContextMenu: (CGRect) -> Void

    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var isHovered = false

    private var isPending: Bool {
        Date().timeIntervalSince(asset.dateAdded) < 30.0
    }

    var body: some View {
        if asset.isDeleted {
            Color.clear
        } else {
            mainCardView
        }
    }

    private var mainCardView: some View {
        let cardBackground = isDarkMode ? Color.white.opacity(0.04) : Color.white.opacity(0.4)
        
        return imageContent
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(cardBorder)
            .overlay(hoverOverlay)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.16 : 0.04),
                radius: isHovered ? 12 : 4,
                y: isHovered ? 6 : 2
            )
            .animation(ManatherTheme.microMotion, value: isHovered)
            .animation(ManatherTheme.uiMotion, value: isSelected)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onSelect()
            }
            .onRightClick(in: .named("gallerySpace")) { frame in
                onContextMenu(frame)
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                isSelected ? ManatherTheme.accent : (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                lineWidth: isSelected ? 2 : 0.8
            )
    }

    private var hoverOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isDarkMode ? Color.white.opacity(isHovered && !isSelected ? 0.04 : 0) : Color.black.opacity(isHovered && !isSelected ? 0.02 : 0))
    }


    // MARK: - Image Content

    private var imageContent: some View {
        Group {
            switch asset.assetType {
            case .image:
                CachedImageView(relativePath: asset.relativeFilePath, maxSize: maxImageSize)
                
            case .gif:
                ZStack(alignment: .topLeading) {
                    CachedImageView(relativePath: asset.relativeFilePath, maxSize: maxImageSize)
                    
                    // GIF Badge
                    Text("GIF")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.black.opacity(0.65))
                        )
                        .padding(8)
                }
                
            case .video:
                ZStack(alignment: .bottomTrailing) {
                    CachedImageView(relativePath: asset.relativeFilePath, maxSize: maxImageSize)
                    
                    // Video Play Icon overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .padding(8)
                }
                
            case .webLink:
                webLinkCard

            case .codeSnippet:
                codeSnippetCard

            case .mcpServer:
                mcpServerCard

            case .skill:
                skillCard
            }
        }
    }

    // MARK: - MCP Server / Skill cards
    //
    // Both are "tool" assets with no visual of their own, so we give them a clean
    // square card: a tinted app-icon-style tile that signals the type at a glance,
    // a small type label, and the name. No command/JSON preview — that lives in
    // the detail view. Teal = MCP (+ a live status dot), amber = Skill.

    private var mcpServerCard: some View {
        toolCard(icon: "server.rack",
                 typeLabel: "MCP SERVER",
                 tint: ManatherTheme.accent)
    }

    private var skillCard: some View {
        toolCard(icon: "sparkles.rectangle.stack",
                 typeLabel: "SKILL",
                 tint: Color(red: 0.85, green: 0.62, blue: 0.28))
    }

    private func toolCard(icon: String, typeLabel: String, tint: Color) -> some View {
        let nameColor = isDarkMode ? Color.white : Color.black.opacity(0.85)

        // Centered composition: icon tile in the upper third, the type label +
        // name in the lower third. Even spacers keep it balanced (no empty gap).
        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 74, height: 74)
                    .shadow(color: tint.opacity(0.38), radius: 13, x: 0, y: 7)

                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                Text(typeLabel)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(tint)

                Text(asset.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(nameColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(toolCardBackground(tint: tint))
    }

    private func toolCardBackground(tint: Color) -> some View {
        ZStack {
            (isDarkMode ? Color.white.opacity(0.04) : Color.white.opacity(0.55))
            // Soft glow of the type color from the top, behind the centered icon.
            LinearGradient(
                colors: [tint.opacity(isDarkMode ? 0.13 : 0.10), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Specialized Bookmark Card

    private var webLinkCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed screenshot or placeholder
            if !asset.relativeFilePath.isEmpty {
                CachedImageView(
                    relativePath: asset.relativeFilePath,
                    maxSize: maxImageSize,
                    contentMode: .fill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                webLinkPlaceholder
            }

            // Gradient so text is always readable against any screenshot
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
                endPoint: .bottom
            )

            // Domain + title overlay
            VStack(alignment: .leading, spacing: 3) {
                if let host = URL(string: asset.sourceURL)?.host, !host.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 9))
                        Text(host)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.65))
                }
                Text(asset.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.6, contentMode: .fit)
        .clipped()
    }

    private var webLinkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.20),
                    Color(red: 0.06, green: 0.09, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if isPending {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white.opacity(0.55))
                    Text("Generating preview…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(ManatherTheme.accent.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Specialized Code Snippet Card

    private var codeSnippetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header bar
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 5, height: 5)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 5, height: 5)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 5, height: 5)
                
                Spacer()
                
                Text(asset.codeLanguage ?? "Code")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 2)
            
            // Monospaced content
            Text(asset.codeContent ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 120)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.09),
                    Color(red: 0.12, green: 0.14, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

}
