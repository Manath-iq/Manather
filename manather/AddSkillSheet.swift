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
    @FocusState private var isEditorFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !markdown.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("Add Skill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

            fieldLabel("Skill Name")
            TextField("e.g. pixel-perfect-landing, api-error-handling", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ManatherTheme.viewerField)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )

            fieldLabel("Instructions (Markdown)")
            TextEditor(text: $markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(8)
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if markdown.isEmpty {
                        Text("# When to use\n# Steps\n# Examples")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isEditorFocused = true }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.microAnimated)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

                Button("Save Skill") {
                    save()
                }
                .buttonStyle(.microAnimated)
                .disabled(!canSave)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(canSave ? ManatherTheme.accent : ManatherTheme.accent.opacity(0.40))
                )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460, height: 430)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, forceDark: true)
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .textCase(.uppercase)
            .tracking(0.7)
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
