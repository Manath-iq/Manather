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
    @FocusState private var isEditorFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!command.trimmingCharacters(in: .whitespaces).isEmpty || !configJSON.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManatherTheme.accent)
                Text("Add MCP Server")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

            fieldLabel("Name")
            sheetTextField("e.g. filesystem, github, puppeteer", text: $name)

            fieldLabel("Launch Command")
            sheetTextField("npx -y @modelcontextprotocol/server-github", text: $command)

            fieldLabel("Config JSON (optional)")
            TextEditor(text: $configJSON)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .focused($isEditorFocused)
                .padding(8)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ManatherTheme.viewerBorder, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture { isEditorFocused = true }

            fieldLabel("Notes (optional)")
            sheetTextField("What this server is for", text: $notes)

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

                Button("Save Server") {
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
        .frame(width: 460, height: 470)
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

    private func sheetTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
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
