//
//  AddSkillSheet.swift
//  manather
//
//  Save an AI-agent skill: name + markdown instructions.
//  Stored as AssetItem(type: skill) — markdown in codeContent.
//

import SwiftUI
import SwiftData

struct AddSkillSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var markdown = ""
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isEditorFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !markdown.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(icon: "sparkles.rectangle.stack", title: "Add Skill")

            SheetFieldLabel("Skill Name")
            TextField("e.g. pixel-perfect-landing, api-error-handling", text: $name)
                .sheetField()
                .focused($isNameFocused)

            SheetFieldLabel("Instructions (Markdown)")
            TextEditor(text: $markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(ManatherTheme.ink)
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(8)
                .frame(height: 200)
                .background(SheetFieldBackground())
                .overlay(alignment: .topLeading) {
                    if markdown.isEmpty {
                        Text("# When to use\n# Steps\n# Examples")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(ManatherTheme.mutedInk.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isEditorFocused = true }

            SheetFooter(
                primaryTitle: "Save Skill",
                primaryEnabled: canSave,
                onCancel: { dismiss() },
                onPrimary: { save() }
            )
        }
        .sheetCard()
        .onAppear { isNameFocused = true }
    }

    private func save() {
        let asset = AssetItem(
            title: name.trimmingCharacters(in: .whitespaces),
            relativeFilePath: "",
            notes: notes,
            typeRaw: "skill",
            codeLanguage: "Markdown",
            codeContent: markdown
        )
        modelContext.insert(asset)
        dismiss()
    }
}
