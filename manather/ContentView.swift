//
//  ContentView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData

extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        })
    }
}

enum ManatherTheme {
    static let paper = Color.dynamic(
        light: Color(red: 0.97, green: 0.97, blue: 0.96),
        dark: Color(red: 0.08, green: 0.09, blue: 0.11)
    )
    static let paperDeep = Color.dynamic(
        light: Color(red: 0.93, green: 0.94, blue: 0.92),
        dark: Color(red: 0.05, green: 0.06, blue: 0.07)
    )
    static let ink = Color.dynamic(
        light: Color(red: 0.06, green: 0.07, blue: 0.07),
        dark: Color(red: 0.95, green: 0.95, blue: 0.95)
    )
    static let mutedInk = Color.dynamic(
        light: Color(red: 0.35, green: 0.36, blue: 0.34),
        dark: Color(red: 0.65, green: 0.66, blue: 0.64)
    )
    static let hairline = Color.dynamic(
        light: Color.black.opacity(0.07),
        dark: Color.white.opacity(0.08)
    )
    static let softPanel = Color.dynamic(
        light: Color.white.opacity(0.58),
        dark: Color.black.opacity(0.40)
    )
    static let accent = Color(red: 0.14, green: 0.54, blue: 0.52)

    static let viewerBackground = Color(red: 0.055, green: 0.11, blue: 0.13)
    static let viewerPanel = Color(red: 0.08, green: 0.14, blue: 0.16)
    static let viewerField = Color(red: 0.12, green: 0.16, blue: 0.16).opacity(0.72)
    static let viewerBorder = Color.white.opacity(0.10)

    static func glassStroke(_ tint: Color = .black, opacity: Double = 0.08) -> Color {
        tint.opacity(opacity)
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 10
    var material: Material = .thinMaterial
    var tint: Color = .white.opacity(0.10)
    var stroke: Color = ManatherTheme.hairline

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func manatherGlass(
        cornerRadius: CGFloat = 10,
        material: Material = .thinMaterial,
        tint: Color = .white.opacity(0.10),
        stroke: Color = ManatherTheme.hairline
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                material: material,
                tint: tint,
                stroke: stroke
            )
        )
    }
}

struct LibraryAmbientBackground: View {
    let featuredAsset: AssetItem?
    @State private var backgroundImage: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ManatherTheme.paper,
                    colorScheme == .dark ? Color(red: 0.06, green: 0.07, blue: 0.09) : Color(red: 0.96, green: 0.96, blue: 0.95),
                    ManatherTheme.paperDeep
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let backgroundImage {
                GeometryReader { geo in
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 76, opaque: true)
                        .saturation(1.12)
                        .opacity(colorScheme == .dark ? 0.18 : 0.24)
                        .scaleEffect(1.24)
                        .allowsHitTesting(false)
                        .clipped()
                        .drawingGroup() // Rasterize to GPU — prevents re-computing blur every frame
                }
            }

            LinearGradient(
                colors: [
                    colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.82),
                    colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.50),
                    ManatherTheme.paper.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .onAppear(perform: loadBackgroundImage)
        .onChange(of: featuredAsset?.id) { _, _ in
            loadBackgroundImage()
        }
    }

    private func loadBackgroundImage() {
        guard let featuredAsset,
              !featuredAsset.relativeFilePath.isEmpty,
              featuredAsset.assetType != .codeSnippet,
              featuredAsset.assetType != .webLink else {
            backgroundImage = nil
            return
        }

        Task {
            let image = await ImageCache.shared.thumbnail(
                for: featuredAsset.relativeFilePath,
                maxSize: 300 // Small is fine — it's heavily blurred and aligns with quantized size
            )
            await MainActor.run {
                if featuredAsset.id == self.featuredAsset?.id {
                    backgroundImage = image
                }
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AssetItem.dateAdded, order: .reverse) private var allAssets: [AssetItem]

    @AppStorage("isDarkMode") private var isDarkMode = false
    @Namespace private var galleryNamespace

    @State private var selectedCategory: SidebarCategory = .all
    @State private var selectedAsset: AssetItem?
    @State private var searchText: String = ""
    @State private var columnCount: Double = 4
    @State private var isImporting: Bool = false

    private var categoryAssets: [AssetItem] {
        let validAssets = allAssets.filter { !$0.isDeleted }
        switch selectedCategory {
        case .all, .unsorted:
            return validAssets.filter { !$0.isTrash }
        case .trash:
            return validAssets.filter { $0.isTrash }
        }
    }

    var body: some View {
        ZStack {
            LibraryAmbientBackground(featuredAsset: categoryAssets.first)

            GalleryGridView(
                assets: allAssets.filter { !$0.isDeleted },
                selectedCategory: $selectedCategory,
                selectedAsset: $selectedAsset,
                searchText: $searchText,
                columnCount: $columnCount,
                isImporting: $isImporting,
                animationNamespace: galleryNamespace
            )
            
            if selectedAsset != nil {
                // Detail/Viewer mode — image + inspector overlayed on top
                AssetDetailView(
                    selectedAsset: $selectedAsset,
                    assets: categoryAssets,
                    animationNamespace: galleryNamespace
                )
                .transition(.opacity)
            }
        }
        .focusEffectDisabled()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: selectedAsset != nil)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onChange(of: selectedCategory) { _, _ in
            selectedAsset = nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AssetItem.self, inMemory: true)
}
