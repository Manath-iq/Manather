//
//  AddCodeSnippetSheet.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData

struct AddCodeSnippetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedLanguage = "Swift"
    @State private var codeText = ""

    let languages = ["Swift", "JavaScript", "TypeScript", "Python", "HTML", "CSS", "C++", "Rust", "Go", "JSON", "Markdown"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Code Snippet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.7)
                
                TextField("Snippet Title", text: $title)
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
            }

            // Language picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Language")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.7)
                
                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.regular)
            }

            // Code TextEditor
            VStack(alignment: .leading, spacing: 6) {
                Text("Code Content")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.7)
                
                TextEditor(text: $codeText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                            )
                    )
            }

            // Action buttons
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

                Button("Save Snippet") {
                    saveSnippet()
                }
                .buttonStyle(.microAnimated)
                .disabled(title.isEmpty || codeText.isEmpty)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(title.isEmpty || codeText.isEmpty ? ManatherTheme.accent.opacity(0.40) : ManatherTheme.accent)
                )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440, height: 440)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
        )
    }

    private func saveSnippet() {
        let asset = AssetItem(
            title: title,
            relativeFilePath: "",
            typeRaw: "codeSnippet",
            codeLanguage: selectedLanguage,
            codeContent: codeText
        )
        modelContext.insert(asset)
        dismiss()
    }
}
