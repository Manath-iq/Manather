//
//  BoardExportView.swift
//  manather
//
//  Static, off-screen rendering of a board used to produce a PNG snapshot via
//  ImageRenderer (no grid, no toolbars, no selection). See SPACE_BOARD_SPEC.md §10.
//

import SwiftUI

struct BoardExportView: View {
    let items: [BoardItem]
    let assetByID: [UUID: AssetItem]
    let origin: CGPoint   // canvas-space top-left of the export region
    let size: CGSize      // pixel size at scale 1

    var body: some View {
        ZStack {
            ManatherTheme.viewerBackground

            ForEach(items.sorted { $0.zIndex < $1.zIndex }, id: \.id) { item in
                BoardItemView(
                    item: item,
                    asset: item.assetID.flatMap { assetByID[$0] },
                    zoom: 1,
                    pan: CGSize(width: -origin.x, height: -origin.y),
                    isSelected: false,
                    isInteractive: false,
                    isEditing: false,
                    isExport: true,
                    onSelect: {},
                    onBeginInteraction: {},
                    onBeginEditing: {},
                    onEndEditing: {},
                    onCommit: {}
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
