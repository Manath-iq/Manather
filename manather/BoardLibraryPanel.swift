//
//  BoardLibraryPanel.swift
//  manather
//
//  The right slide-in panel for picking library images to drop on the board.
//  Multi-select thumbnails, then "Add" places them on the canvas. Dark glass
//  styling like InspectorView (see SPACE_BOARD_SPEC.md §8).
//

import SwiftUI

struct BoardLibraryPanel: View {
    let assets: [AssetItem]          // image / gif assets from the library
    let onAdd: ([AssetItem]) -> Void
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []

    private var filtered: [AssetItem] {
        let pool = assets.filter { $0.assetType == .image || $0.assetType == .gif }
        guard !searchText.isEmpty else { return pool }
        let q = searchText.lowercased()
        return pool.filter { $0.title.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }
    }

    // Fixed 3-column grid so each cell width is predictable and the selection
    // border lines up with the cell (no overflow into neighbours).
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            countRow
            Divider().overlay(Color.white.opacity(0.08))
            grid
            footer
        }
        .frame(width: 280)
        .background(
            ManatherTheme.viewerPanel
                .overlay(Color.black.opacity(0.10))
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Library")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.microAnimated)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search images…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ManatherTheme.viewerField)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var countRow: some View {
        HStack {
            Text("\(filtered.count) image\(filtered.count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if !selectedIDs.isEmpty {
                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ManatherTheme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var grid: some View {
        ScrollView {
            if filtered.isEmpty {
                Text("No images in the library yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filtered, id: \.id) { asset in
                        thumbnail(asset)
                    }
                }
                .padding(14)
            }
        }
    }

    private func thumbnail(_ asset: AssetItem) -> some View {
        let isSelected = selectedIDs.contains(asset.id)
        return CachedImageView(relativePath: asset.relativeFilePath, maxSize: 200)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)   // square cell sized to the column
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? ManatherTheme.accent : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? ManatherTheme.accent : .white.opacity(0.55))
                    .background(Circle().fill(.black.opacity(0.35)))
                    .padding(5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected { selectedIDs.remove(asset.id) }
                else { selectedIDs.insert(asset.id) }
            }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                let chosen = filtered.filter { selectedIDs.contains($0.id) }
                onAdd(chosen)
            } label: {
                Text(selectedIDs.isEmpty ? "Add to board" : "Add \(selectedIDs.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(selectedIDs.isEmpty ? ManatherTheme.accent.opacity(0.35) : ManatherTheme.accent)
                    )
            }
            .buttonStyle(.microAnimated)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(14)
    }
}
