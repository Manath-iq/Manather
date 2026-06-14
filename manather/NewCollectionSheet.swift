//
//  NewCollectionSheet.swift
//  manather
//
//  Sheet for creating a new (possibly empty) collection. Used by the "New
//  collection" card on the Collections tab in GalleryGridView.
//

import SwiftUI
import SwiftData

struct NewCollectionSheet: View {
    /// Existing collection names, used to avoid creating a duplicate.
    let existingNames: [String]
    /// Called with the final name after the collection is created.
    let onCreate: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        existingNames.contains { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("New Collection")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

            fieldLabel("Collection Name")
            TextField("e.g. Landing pages, Color mood, Buttons", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit { create() }
                .padding(8)
                .background(fieldBackground)

            if isDuplicate {
                Text("A collection with this name already exists.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.4))
            } else {
                Text("You can add saves to it now or later.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

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

                Button("Create") { create() }
                    .buttonStyle(.microAnimated)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(canCreate ? ManatherTheme.accent : Color.white.opacity(0.12))
                    )
                    .disabled(!canCreate)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
        .onAppear { isFocused = true }
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !isDuplicate
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
        guard canCreate else { return }
        modelContext.insert(AssetCollection(name: trimmedName))
        let created = trimmedName
        dismiss()
        onCreate(created)
    }
}
