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
    @Environment(\.modelContext) private var modelContext

    let asset: AssetItem
    let isSelected: Bool
    let isTrashView: Bool
    var maxImageSize: CGFloat = 500
    /// Passed in from parent — avoids a @Query per card (huge perf win)
    let availableCollections: [String]
    let availableSpaces: [String]
    let onSelect: () -> Void
    let onTrash: () -> Void
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

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
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onSelect()
            }
            .contextMenu {
                contextMenuItems
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

    // MARK: - MCP Server Card

    private var mcpServerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("MCP SERVER")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.8)
                Spacer()
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 6, height: 6)
            }

            Text(asset.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let command = asset.codeLanguage, !command.isEmpty {
                Text(command)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )
            }

            if !asset.notes.isEmpty {
                Text(asset.notes)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 110)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.15),
                    Color(red: 0.07, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Skill Card

    private var skillCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.30))
                Text("SKILL")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.8)
                Spacer()
            }

            Text(asset.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(asset.codeContent ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 110)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.11, blue: 0.08),
                    Color(red: 0.09, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Specialized Bookmark Card

    private var webLinkCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !asset.relativeFilePath.isEmpty {
                // Show the website screenshot
                CachedImageView(relativePath: asset.relativeFilePath, maxSize: maxImageSize)
                    .frame(height: 120)
                    .clipped()
            } else {
                // Show a nice placeholder
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.22, blue: 0.22),
                            Color(red: 0.07, green: 0.10, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 24))
                            .foregroundStyle(ManatherTheme.accent.opacity(0.88))
                        
                        if isPending {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Generating preview")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        } else {
                            Text("Preview unavailable")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(height: 120)
            }
            
            // Details area
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(ManatherTheme.accent)
                    
                    Text(URL(string: asset.sourceURL)?.host ?? "Web Link")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    
                    Spacer()
                }
                
                Text(asset.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if !asset.notes.isEmpty {
                    Text(asset.notes)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(Color(red: 0.07, green: 0.12, blue: 0.12))
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - Context Menu

    private var collectionsList: [String] { availableCollections }
    private var spacesList: [String] { availableSpaces }

    private func copyPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(asset.prompt, forType: .string)
    }

    private func duplicateAsset() {
        var newPath = asset.relativeFilePath
        if !asset.relativeFilePath.isEmpty {
            let srcURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
            let ext = srcURL.pathExtension
            let newFilename = "copy_\(UUID().uuidString).\(ext)"
            let destURL = FileManagerHelper.assetsDirectory.appendingPathComponent(newFilename)
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
            newPath = newFilename
        }
        
        let copy = AssetItem(
            title: "\(asset.title) (Copy)",
            relativeFilePath: newPath,
            sourceURL: asset.sourceURL,
            prompt: asset.prompt,
            notes: asset.notes,
            imageWidth: asset.imageWidth,
            imageHeight: asset.imageHeight,
            typeRaw: asset.typeRaw,
            codeLanguage: asset.codeLanguage,
            codeContent: asset.codeContent,
            dominantColorsHex: asset.dominantColorsHex,
            collectionName: asset.collectionName,
            spaceName: asset.spaceName
        )
        modelContext.insert(copy)
    }

    private func exportAsset() {
        guard !asset.relativeFilePath.isEmpty else { return }
        
        let savePanel = NSSavePanel()
        let ext = (asset.relativeFilePath as NSString).pathExtension
        if let type = UTType(filenameExtension: ext) {
            savePanel.allowedContentTypes = [type]
        } else {
            savePanel.allowedContentTypes = [.image]
        }
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = asset.title
        
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                let sourceURL = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                try? FileManager.default.removeItem(at: destinationURL)
                try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if isTrashView {
            Button {
                onRestore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button(role: .destructive) {
                onDeletePermanently()
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        } else {
            if !asset.prompt.isEmpty {
                Button {
                    copyPrompt()
                } label: {
                    Label("Copy Prompt", systemImage: "doc.on.doc")
                }
                
                Divider()
            }
            
            Menu {
                ForEach(collectionsList, id: \.self) { col in
                    Button(col) {
                        asset.collectionName = col
                    }
                }
                Divider()
                Button("Clear Collection") {
                    asset.collectionName = nil
                }
            } label: {
                Label("Add to Collection", systemImage: "folder")
            }
            
            Menu {
                ForEach(spacesList, id: \.self) { space in
                    Button(space) {
                        asset.spaceName = space
                    }
                }
                Divider()
                Button("Remove from Project") {
                    asset.spaceName = nil
                }
            } label: {
                Label("Add to Project", systemImage: "square.stack.3d.up")
            }
            
            Divider()
            
            Button {
                duplicateAsset()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            
            if !asset.relativeFilePath.isEmpty {
                Button {
                    exportAsset()
                } label: {
                    Label("Export...", systemImage: "square.and.arrow.up")
                }
            }
            
            Divider()

            Button(role: .destructive) {
                onTrash()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}
