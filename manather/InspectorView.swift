//
//  InspectorView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Color Constants

private enum InspectorColors {
    static let background = ManatherTheme.viewerBackground
    static let cardBackground = ManatherTheme.viewerPanel
    static let fieldBackground = ManatherTheme.viewerField
    static let fieldBorder = ManatherTheme.viewerBorder
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.82)
    static let tertiaryText = Color.white.opacity(0.38)
    static let accentTeal = ManatherTheme.accent
    static let divider = Color.white.opacity(0.06)
}

struct InspectorView: View {
    @Binding var asset: AssetItem?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AssetCollection.dateAdded, order: .reverse) private var savedCollections: [AssetCollection]

    private var collectionNames: [String] { savedCollections.map(\.name) }

    @State private var dominantColors: [Color] = []
    @State private var colorHexes: [String] = []
    @State private var isLoadingColors = false
    @State private var showCopiedToast = false
    @State private var copiedHex = ""
    @State private var isNoteExpanded = false
    @State private var isGenerating = false
    @State private var genMessage: String? = nil

    var body: some View {
        Group {
            if let asset = asset {
                inspectorContent(for: asset)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 270, idealWidth: 310, maxWidth: 380)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                Color(red: 0.045, green: 0.05, blue: 0.055, opacity: 0.85)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 15, x: 0, y: 5)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(InspectorColors.tertiaryText)
            Text("Select an item")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(InspectorColors.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector Content

    private func inspectorContent(for asset: AssetItem) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Details")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(InspectorColors.primaryText)

                    Spacer()

                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(InspectorColors.tertiaryText)
                }
                .padding(.bottom, 16)

                // Thumbnail with format badge
                thumbnailSection(for: asset)
                    .padding(.bottom, 12)

                // Color Palette
                colorPaletteSection(for: asset)
                    .padding(.bottom, 14)

                // Action button: Visit Site for web links, Generate Variation for
                // bitmap media. Code/MCP/skill assets get no image action.
                if asset.assetType == .webLink {
                    visitSiteButton(for: asset)
                        .padding(.bottom, 20)
                } else if asset.assetType == .image || asset.assetType == .gif {
                    generateVariationButton
                        .padding(.bottom, 20)
                }

                // Name
                sectionLabel("Name")
                darkTextField(
                    text: Binding(
                        get: { asset.title },
                        set: { asset.title = $0 }
                    ),
                    placeholder: "Untitled"
                )
                .padding(.bottom, 16)

                // URL
                sectionLabel("URL")
                darkTextField(
                    text: Binding(
                        get: { asset.sourceURL },
                        set: { asset.sourceURL = $0 }
                    ),
                    placeholder: "https://..."
                )
                .padding(.bottom, 16)

                // Note — collapsed "+ Add a note" until clicked or non-empty
                noteSection(for: asset)
                    .padding(.bottom, 20)

                // Image Prompt
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Text("✦")
                            .font(.system(size: 11))
                        Text("Image Prompt")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(InspectorColors.secondaryText)

                    Spacer()

                    Button("Copy") {
                        copyToClipboard(asset.prompt)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(InspectorColors.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.15))
                            )
                    )
                    .buttonStyle(.microAnimated)
                    .disabled(asset.prompt.isEmpty)
                    .opacity(asset.prompt.isEmpty ? 0.4 : 1.0)

                    Button {
                        copyToClipboard(asset.prompt)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(InspectorColors.tertiaryText)
                    }
                    .buttonStyle(.microAnimated)
                    .disabled(asset.prompt.isEmpty)
                }
                .padding(.bottom, 8)

                darkTextEditor(
                    text: Binding(
                        get: { asset.prompt },
                        set: { asset.prompt = $0 }
                    ),
                    minHeight: 90
                )
                .padding(.bottom, 20)

                // Collections — chips with × (an asset can be in several at once)
                ChipAssignSection(
                    icon: "folder",
                    title: "Collections",
                    values: Binding(
                        get: { asset.collectionNames },
                        set: { asset.setCollections($0) }
                    ),
                    options: collectionNames
                )
                .padding(.bottom, 16)

                // Tags
                TagsSection(asset: asset)
                    .padding(.bottom, 16)

                // Date info
                HStack {
                    Text("Added")
                        .font(.system(size: 11))
                        .foregroundStyle(InspectorColors.tertiaryText)
                    Spacer()
                    Text(asset.dateAdded, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(InspectorColors.tertiaryText)
                }

                Spacer(minLength: 30)
            }
            .padding(20)
        }
        .onAppear {
            if let currentAsset = self.asset {
                loadDominantColors(for: currentAsset)
            }
        }
        .onChange(of: self.asset) { oldValue, newValue in
            isNoteExpanded = false
            if let newValue = newValue {
                loadDominantColors(for: newValue)
            } else {
                dominantColors = []
                colorHexes = []
            }
        }
    }

    // MARK: - Visit Site (web links)

    private func visitSiteButton(for asset: AssetItem) -> some View {
        Button {
            if let url = URL(string: asset.sourceURL), !asset.sourceURL.isEmpty {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "safari")
                    .font(.system(size: 12))
                Text("Visit Site")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(InspectorColors.primaryText.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
            )
        }
        .buttonStyle(.microAnimated)
        .disabled(asset.sourceURL.isEmpty)
        .opacity(asset.sourceURL.isEmpty ? 0.4 : 1.0)
        .help("Open this website in your default browser")
    }

    // MARK: - Generate Variation (AI)

    private var generateVariationButton: some View {
        VStack(spacing: 6) {
            Button {
                generateVariation()
            } label: {
                HStack(spacing: 6) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Generating…")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("✦")
                            .font(.system(size: 12))
                        Text("Generate variation")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(InspectorColors.primaryText.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                )
            }
            .buttonStyle(.microAnimated)
            .disabled(isGenerating)
            .help("Generates a new image variation with your default AI provider")

            if let genMessage {
                Text(genMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(InspectorColors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    /// Generates one AI variation of the current image and adds it to the library
    /// (same collection, prompt copied, tagged "variation").
    private func generateVariation() {
        guard let asset, !isGenerating else { return }
        isGenerating = true
        withAnimation { genMessage = nil }

        Task {
            do {
                let data = try await AIClient.generateVariation(of: asset)
                guard let image = NSImage(data: data) else { throw AIError.badResponse }
                let baseTitle = asset.title.isEmpty ? "Variation" : "\(asset.title) variation"
                guard let relPath = FileManagerHelper.saveImageData(image.pngData() ?? data, baseName: baseTitle, ext: "png") else {
                    throw AIError.badResponse
                }
                var tags = asset.tags
                if !tags.contains("variation") { tags.append("variation") }
                let size = image.pixelSize
                let newAsset = AssetItem(
                    title: baseTitle,
                    relativeFilePath: relPath,
                    prompt: asset.prompt,
                    imageWidth: size.width,
                    imageHeight: size.height,
                    typeRaw: "image",
                    collectionNames: asset.collectionNames,
                    tags: tags
                )
                withAnimation(ManatherTheme.uiMotion) { modelContext.insert(newAsset) }
                ColorIndexer.shared.ensureColors(for: newAsset)

                isGenerating = false
                withAnimation { genMessage = "✓ Variation added to your library" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { if genMessage?.hasPrefix("✓") == true { genMessage = nil } }
                }
            } catch {
                isGenerating = false
                withAnimation {
                    genMessage = (error as? AIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: - Note (collapsed by default)

    @ViewBuilder
    private func noteSection(for asset: AssetItem) -> some View {
        if asset.notes.isEmpty && !isNoteExpanded {
            Button {
                withAnimation(ManatherTheme.uiMotion) {
                    isNoteExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Add a note")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(InspectorColors.secondaryText.opacity(0.7))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InspectorColors.secondaryText)
                darkTextEditor(
                    text: Binding(
                        get: { asset.notes },
                        set: { asset.notes = $0 }
                    ),
                    minHeight: 50
                )
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnailSection(for asset: AssetItem) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                if asset.assetType == .webLink {
                    webLinkThumbnail(for: asset)
                } else if asset.assetType == .codeSnippet || asset.assetType == .mcpServer || asset.assetType == .skill {
                    codeSnippetThumbnail(for: asset)
                } else {
                    CachedImageView(relativePath: asset.relativeFilePath, maxSize: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Format badge
                Text(asset.fileFormat)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Color Palette Section

    private func colorPaletteSection(for asset: AssetItem) -> some View {
        VStack(spacing: 8) {
            if isLoadingColors {
                ProgressView()
                    .controlSize(.mini)
                    .frame(height: 32)
            } else if dominantColors.isEmpty {
                Text("No colors extracted")
                    .font(.system(size: 11))
                    .foregroundStyle(InspectorColors.tertiaryText)
                    .italic()
                    .frame(height: 32)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<dominantColors.count, id: \.self) { index in
                        if index < dominantColors.count && index < colorHexes.count {
                            let color = dominantColors[index]
                            let hex = colorHexes[index]
                            
                            ColorCircle(color: color, hex: hex) {
                                copyToClipboard(hex)
                                copiedHex = hex
                                withAnimation(ManatherTheme.uiMotion) {
                                    showCopiedToast = true
                                }
                                // Reset toast after 1.5 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if copiedHex == hex {
                                        withAnimation {
                                            showCopiedToast = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 32)
            }
            
            if showCopiedToast {
                Text("Copied \(copiedHex)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(InspectorColors.accentTeal)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Dark-Themed Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(InspectorColors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.7)
            .padding(.bottom, 6)
    }

    private func darkTextField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(InspectorColors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    private func darkTextEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .foregroundStyle(InspectorColors.primaryText)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .padding(6)
            .frame(minHeight: minHeight, maxHeight: minHeight + 60)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func loadDominantColors(for asset: AssetItem) {
        if let hexes = asset.dominantColorsHex, !hexes.isEmpty {
            self.colorHexes = hexes
            self.dominantColors = hexes.compactMap { hexString -> Color? in
                let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                var int: UInt64 = 0
                Scanner(string: hex).scanHexInt64(&int)
                let r, g, b: UInt64
                if hex.count == 6 {
                    (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
                } else {
                    (r, g, b) = (255, 255, 255)
                }
                return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
            }
            self.isLoadingColors = false
            return
        }

        dominantColors = []
        colorHexes = []
        isLoadingColors = true
        
        let assetID = asset.id
        let path = asset.relativeFilePath
        
        Task {
            // Use a small thumbnail for color extraction — no need for full image
            let nsImage = await ImageCache.shared.thumbnail(for: path, maxSize: 200)
            
            guard let nsImage, self.asset?.id == assetID else {
                self.isLoadingColors = false
                return
            }
            
            let nsColors = DominantColorExtractor.extractColors(from: nsImage, count: 8)
            let hexes = nsColors.map { color -> String in
                guard let rgbColor = color.usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
                let r = Int(rgbColor.redComponent * 255)
                let g = Int(rgbColor.greenComponent * 255)
                let b = Int(rgbColor.blueComponent * 255)
                return String(format: "#%02X%02X%02X", r, g, b)
            }
            let colors = nsColors.map { Color(nsColor: $0) }
            
            if self.asset?.id == assetID {
                self.dominantColors = colors
                self.colorHexes = hexes
                self.asset?.dominantColorsHex = hexes
                self.isLoadingColors = false
            }
        }
    }

    private func webLinkThumbnail(for asset: AssetItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .foregroundStyle(InspectorColors.accentTeal)
                
                Text(URL(string: asset.sourceURL)?.host ?? "Web Link")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(InspectorColors.secondaryText)
                    .lineLimit(1)
            }
            .padding(.top, 4)
            
            Text(asset.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(InspectorColors.primaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            if !asset.notes.isEmpty {
                Text(asset.notes)
                    .font(.system(size: 11))
                    .foregroundStyle(InspectorColors.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(InspectorColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(InspectorColors.fieldBorder)
                )
        )
    }

    private func codeSnippetThumbnail(for asset: AssetItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 6, height: 6)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 6, height: 6)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                
                Spacer()
                
                Text(asset.codeLanguage ?? "Code")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(InspectorColors.secondaryText)
            }
            .padding(.bottom, 2)
            
            Text(asset.codeContent ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InspectorColors.primaryText.opacity(0.85))
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(InspectorColors.fieldBorder)
                )
        )
    }
}

// MARK: - Chip Assign Section (Collections / Spaces)

/// Renders a single-value assignment (collection or space) as a removable chip,
/// with an inline "+ Add" field — visual match for GatherOS chips.
struct ChipAssignSection: View {
    let icon: String
    let title: String
    @Binding var values: [String]
    var options: [String] = []

    @State private var showPicker = false
    @State private var newText = ""
    @FocusState private var isNewFieldFocused: Bool

    /// Options not already chosen — what the picker offers.
    private var available: [String] { options.filter { !values.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(InspectorColors.secondaryText)

            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .medium))
                        Text(value)
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            values.removeAll { $0 == value }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    )
                }

                // "Add" chip — always present so more collections can be added.
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("Add")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule().stroke(
                                Color.white.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                        )
                )
                .onTapGesture { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    collectionPickerPopover
                }
            }
        }
    }

    private var collectionPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !available.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(available, id: \.self) { name in
                            Button {
                                add(name)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ManatherTheme.accent)
                                    Text(name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 220)

                Divider()
            }

            // New collection inline
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("New collection…", text: $newText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isNewFieldFocused)
                    .onSubmit { commitNew() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 230)
        .onAppear {
            // Focus the text field only when there's nothing to pick from.
            if available.isEmpty {
                DispatchQueue.main.async { isNewFieldFocused = true }
            }
        }
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !values.contains(trimmed) else { return }
        values.append(trimmed)
        showPicker = false
    }

    private func commitNew() {
        add(newText)
        newText = ""
    }
}

// MARK: - Tags Section

struct TagsSection: View {
    let asset: AssetItem

    @State private var newTagText = ""
    @State private var isTagging = false
    @FocusState private var isAddingTag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "number")
                    .font(.system(size: 10, weight: .medium))
                Text("Tags")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(InspectorColors.secondaryText)

            FlowLayout(spacing: 6) {
                ForEach(asset.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            asset.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                }

                // Inline add tag field
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))

                    if isAddingTag {
                        TextField("tag", text: $newTagText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white)
                            .frame(minWidth: 40, maxWidth: 80)
                            .focused($isAddingTag)
                            .onSubmit { commitTag() }
                    } else {
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule().stroke(
                                Color.white.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                        )
                )
                .onTapGesture {
                    isAddingTag = true
                }

                // Auto-tag — vision model looks at the image (falls back to
                // deriving tags from title & prompt words if AI isn't available).
                Button {
                    autoTag()
                } label: {
                    HStack(spacing: 4) {
                        if isTagging {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text("✦")
                                .font(.system(size: 9))
                        }
                        Text(isTagging ? "Tagging…" : "Auto-tag")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    )
                }
                .buttonStyle(.microAnimated)
                .disabled(isTagging)
            }
        }
        .onChange(of: isAddingTag) { _, focused in
            if !focused { commitTag() }
        }
    }

    private func autoTag() {
        guard !isTagging else { return }
        // For images, ask a vision model to look at the picture. If no AI provider
        // is connected, or it fails, or the asset isn't an image, fall back to the
        // keyword heuristic so the button always does something useful.
        let isVisual = asset.assetType == .image || asset.assetType == .gif
        guard isVisual, !asset.relativeFilePath.isEmpty else {
            keywordAutoTag()
            return
        }

        isTagging = true
        let target = asset
        Task {
            do {
                let tags = try await AIClient.suggestTags(for: target)
                for tag in tags where !target.tags.contains(tag) {
                    target.tags.append(tag)
                }
            } catch {
                keywordAutoTag()
            }
            isTagging = false
        }
    }

    /// Offline fallback: derive a few tags from the title and prompt words.
    private func keywordAutoTag() {
        let stopWords: Set<String> = ["the", "and", "with", "for", "from", "this", "that", "into", "are", "was", "has", "have", "modern", "image", "untitled", "copy"]
        let source = "\(asset.title) \(asset.prompt)"
        let words = source
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) && Int($0) == nil }

        var added = 0
        for word in words {
            if !asset.tags.contains(word) {
                asset.tags.append(word)
                added += 1
            }
            if added >= 3 { break }
        }
    }

    private func commitTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !tag.isEmpty && !asset.tags.contains(tag) {
            asset.tags.append(tag)
        }
        newTagText = ""
        isAddingTag = false
    }
}

// MARK: - Flow Layout (wrapping chips row)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Color Circle Subview

struct ColorCircle: View {
    let color: Color
    let hex: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.2 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 4 : 1, y: isHovered ? 2 : 1)
            .animation(ManatherTheme.microMotion, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                action()
            }
            .help(hex)
    }
}
