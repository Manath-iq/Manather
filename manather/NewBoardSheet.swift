//
//  NewBoardSheet.swift
//  manather
//
//  Sheet for creating a new board (title + description). Used by the Boards
//  tab in GalleryGridView.
//

import SwiftUI
import SwiftData

// MARK: - New board sheet

struct NewBoardSheet: View {
    let projectName: String
    let onCreate: (Board) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("New Board")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

            fieldLabel("Board Name")
            TextField("e.g. Landing, Logo, Color mood", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(8)
                .background(fieldBackground)

            fieldLabel("Description (optional)")
            TextEditor(text: $details)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 90)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )

                Button("Create Board") { create() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ManatherTheme.accent)
                    )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440, height: 320)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(ManatherTheme.viewerField)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
            )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .textCase(.uppercase)
            .tracking(0.7)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let board = Board(
            title: trimmed.isEmpty ? "Untitled board" : trimmed,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            projectName: projectName
        )
        modelContext.insert(board)
        dismiss()
        onCreate(board)
    }
}
