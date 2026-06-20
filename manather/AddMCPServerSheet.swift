//
//  AddMCPServerSheet.swift
//  manather
//
//  Save an MCP server config: name, launch command, JSON config, notes.
//  Stored as AssetItem(type: mcpServer) — command in codeLanguage, JSON in codeContent.
//

import SwiftUI
import SwiftData

struct AddMCPServerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var configJSON = ""
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isEditorFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!command.trimmingCharacters(in: .whitespaces).isEmpty || !configJSON.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(icon: "server.rack", title: "Add MCP Server")

            SheetFieldLabel("Name")
            TextField("e.g. filesystem, github, puppeteer", text: $name)
                .sheetField()
                .focused($isNameFocused)

            SheetFieldLabel("Launch Command")
            TextField("npx -y @modelcontextprotocol/server-github", text: $command)
                .sheetField()

            SheetFieldLabel("Config JSON (optional)")
            TextEditor(text: $configJSON)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(ManatherTheme.ink)
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(8)
                .frame(height: 120)
                .background(SheetFieldBackground())
                .contentShape(Rectangle())
                .onTapGesture { isEditorFocused = true }

            SheetFieldLabel("Notes (optional)")
            TextField("What this server is for", text: $notes)
                .sheetField()

            SheetFooter(
                primaryTitle: "Save Server",
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
            typeRaw: "mcpServer",
            codeLanguage: command.trimmingCharacters(in: .whitespaces),
            codeContent: configJSON
        )
        modelContext.insert(asset)
        dismiss()
    }
}
