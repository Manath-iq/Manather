//
//  SidebarView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData

enum SidebarCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case unsorted = "Unsorted"
    case trash = "Trash"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .unsorted: return "tray"
        case .trash: return "trash"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedCategory: SidebarCategory
    @Query private var allItems: [AssetItem]

    private var allCount: Int {
        allItems.filter { !$0.isDeleted && !$0.isTrash }.count
    }

    private var trashCount: Int {
        allItems.filter { !$0.isDeleted && $0.isTrash }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App branding header
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Library")
                    .font(.system(size: 15, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    // Search action
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.microAnimated)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Category list
            VStack(spacing: 2) {
                ForEach(SidebarCategory.allCases) { category in
                    sidebarRow(category: category)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
    }

    private func sidebarRow(category: SidebarCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if badgeCount(for: category) > 0 {
                    Text("\(badgeCount(for: category))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.microAnimated)
    }

    private func badgeCount(for category: SidebarCategory) -> Int {
        switch category {
        case .all: return allCount
        case .unsorted: return allCount
        case .trash: return trashCount
        }
    }
}
