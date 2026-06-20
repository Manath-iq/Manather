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
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isEditorFocused: Bool

    let languages = ["Swift", "JavaScript", "TypeScript", "Python", "HTML", "CSS", "C++", "Rust", "Go", "JSON", "Markdown"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(icon: "curlybraces", title: "Add Code Snippet")

            // Title
            VStack(alignment: .leading, spacing: 6) {
                SheetFieldLabel("Title")
                TextField("Snippet Title", text: $title)
                    .sheetField()
                    .focused($isTitleFocused)
            }

            // Language picker
            VStack(alignment: .leading, spacing: 6) {
                SheetFieldLabel("Language")
                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(ManatherTheme.accent)
                .controlSize(.regular)
            }

            // Code TextEditor
            VStack(alignment: .leading, spacing: 6) {
                SheetFieldLabel("Code Content")
                TextEditor(text: $codeText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(ManatherTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .padding(8)
                    .frame(height: 180)
                    .background(SheetFieldBackground())
                    .contentShape(Rectangle())
                    .onTapGesture { isEditorFocused = true }
            }

            SheetFooter(
                primaryTitle: "Save Snippet",
                primaryEnabled: !title.isEmpty && !codeText.isEmpty,
                onCancel: { dismiss() },
                onPrimary: { saveSnippet() }
            )
        }
        .sheetCard()
        .onAppear { isTitleFocused = true }
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
