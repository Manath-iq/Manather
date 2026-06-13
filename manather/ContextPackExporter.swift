//
//  ContextPackExporter.swift
//  manather
//
//  One-click export of a project as an "AI context pack":
//  a folder with the asset files, a CONTEXT.md written for LLM consumption
//  (prompts, notes, links, snippets, skills, MCP configs), and manifest.json.
//  Drop the folder into a repo and point an AI agent at CONTEXT.md.
//

import Foundation
import AppKit

enum ContextPackExporter {

    /// Shows a save panel, then writes the pack. Call from the main actor.
    static func export(projectName: String, assets: [AssetItem]) {
        let panel = NSSavePanel()
        panel.title = "Export Context Pack"
        panel.nameFieldStringValue = sanitized(projectName) + "-context-pack"
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writePack(to: url, projectName: projectName, assets: assets)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    // MARK: - Pack Writing

    private static func writePack(to root: URL, projectName: String, assets: [AssetItem]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let assetsDir = root.appendingPathComponent("assets", isDirectory: true)
        let skillsDir = root.appendingPathComponent("skills", isDirectory: true)
        let snippetsDir = root.appendingPathComponent("snippets", isDirectory: true)

        var manifestEntries: [[String: Any]] = []
        var copiedFiles: [UUID: String] = [:] // asset id -> relative path inside pack

        for asset in assets where !asset.isTrash && !asset.isDeleted {
            var entry: [String: Any] = [
                "id": asset.id.uuidString,
                "title": asset.title,
                "type": asset.typeRaw
            ]
            if !asset.prompt.isEmpty { entry["prompt"] = asset.prompt }
            if !asset.notes.isEmpty { entry["notes"] = asset.notes }
            if !asset.sourceURL.isEmpty { entry["sourceURL"] = asset.sourceURL }
            if !asset.tags.isEmpty { entry["tags"] = asset.tags }

            switch asset.assetType {
            case .image, .gif, .video:
                if !asset.relativeFilePath.isEmpty {
                    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                    let src = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                    let destName = uniqueName(for: asset, ext: src.pathExtension)
                    let dest = assetsDir.appendingPathComponent(destName)
                    if fm.fileExists(atPath: src.path) {
                        try? fm.copyItem(at: src, to: dest)
                        copiedFiles[asset.id] = "assets/\(destName)"
                        entry["file"] = "assets/\(destName)"
                    }
                }

            case .skill:
                try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
                let destName = sanitized(asset.title) + ".md"
                let dest = skillsDir.appendingPathComponent(destName)
                let content = asset.codeContent ?? ""
                try content.write(to: dest, atomically: true, encoding: .utf8)
                copiedFiles[asset.id] = "skills/\(destName)"
                entry["file"] = "skills/\(destName)"

            case .codeSnippet:
                try fm.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
                let ext = fileExtension(forLanguage: asset.codeLanguage)
                let destName = sanitized(asset.title) + "." + ext
                let dest = snippetsDir.appendingPathComponent(destName)
                try (asset.codeContent ?? "").write(to: dest, atomically: true, encoding: .utf8)
                copiedFiles[asset.id] = "snippets/\(destName)"
                entry["file"] = "snippets/\(destName)"
                if let lang = asset.codeLanguage { entry["language"] = lang }

            case .mcpServer:
                if let cmd = asset.codeLanguage, !cmd.isEmpty { entry["command"] = cmd }
                if let cfg = asset.codeContent, !cfg.isEmpty { entry["config"] = cfg }

            case .webLink:
                break // URL already captured in sourceURL
            }

            manifestEntries.append(entry)
        }

        // CONTEXT.md — the file an AI agent reads first
        let contextMD = buildContextMarkdown(projectName: projectName, assets: assets, files: copiedFiles)
        try contextMD.write(to: root.appendingPathComponent("CONTEXT.md"), atomically: true, encoding: .utf8)

        // manifest.json — machine-readable index
        let manifest: [String: Any] = [
            "project": projectName,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "generator": "Manather",
            "assets": manifestEntries
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: root.appendingPathComponent("manifest.json"))
    }

    // MARK: - CONTEXT.md Generation

    private static func buildContextMarkdown(projectName: String, assets: [AssetItem], files: [UUID: String]) -> String {
        var md = """
        # \(projectName) — Project Context Pack

        > Exported from Manather. This folder contains the reference materials,
        > skills, MCP servers, and code snippets for building this project.
        > Read everything below before starting work.

        """

        let live = assets.filter { !$0.isTrash && !$0.isDeleted }

        let skills = live.filter { $0.assetType == .skill }
        let mcpServers = live.filter { $0.assetType == .mcpServer }
        let snippets = live.filter { $0.assetType == .codeSnippet }
        let links = live.filter { $0.assetType == .webLink }
        let media = live.filter { $0.assetType == .image || $0.assetType == .gif || $0.assetType == .video }

        if !skills.isEmpty {
            md += "\n## Skills (follow these instructions)\n"
            for skill in skills {
                md += "\n### \(skill.title)\n"
                if let file = files[skill.id] { md += "\nFull instructions: `\(file)`\n" }
                if let content = skill.codeContent, !content.isEmpty {
                    md += "\n\(content)\n"
                }
            }
        }

        if !mcpServers.isEmpty {
            md += "\n## MCP Servers (connect these before working)\n"
            for server in mcpServers {
                md += "\n### \(server.title)\n"
                if let cmd = server.codeLanguage, !cmd.isEmpty {
                    md += "\nLaunch command:\n```\n\(cmd)\n```\n"
                }
                if let cfg = server.codeContent, !cfg.isEmpty {
                    md += "\nConfig:\n```json\n\(cfg)\n```\n"
                }
                if !server.notes.isEmpty { md += "\n\(server.notes)\n" }
            }
        }

        if !snippets.isEmpty {
            md += "\n## Code Snippets (reuse these patterns)\n"
            for snippet in snippets {
                md += "\n### \(snippet.title)"
                if let lang = snippet.codeLanguage { md += " (\(lang))" }
                md += "\n"
                if let file = files[snippet.id] { md += "\nFile: `\(file)`\n" }
                if !snippet.notes.isEmpty { md += "\n\(snippet.notes)\n" }
                if !snippet.prompt.isEmpty { md += "\nPrompt: \(snippet.prompt)\n" }
            }
        }

        if !media.isEmpty {
            md += "\n## Visual References\n"
            for item in media {
                md += "\n### \(item.title)\n"
                if let file = files[item.id] { md += "\nFile: `\(file)`\n" }
                if !item.prompt.isEmpty { md += "\nPrompt: \(item.prompt)\n" }
                if !item.notes.isEmpty { md += "\nNotes: \(item.notes)\n" }
                if !item.tags.isEmpty { md += "\nTags: \(item.tags.joined(separator: ", "))\n" }
            }
        }

        if !links.isEmpty {
            md += "\n## Reference Links\n"
            for link in links {
                md += "\n- [\(link.title)](\(link.sourceURL))"
                if !link.notes.isEmpty { md += " — \(link.notes)" }
            }
            md += "\n"
        }

        md += "\n---\n\n*Machine-readable index: `manifest.json`*\n"
        return md
    }

    // MARK: - Helpers

    private static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(mapped))
        return result.isEmpty ? "untitled" : result
    }

    private static func uniqueName(for asset: AssetItem, ext: String) -> String {
        let base = sanitized(asset.title)
        let suffix = asset.id.uuidString.prefix(6)
        return ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
    }

    private static func fileExtension(forLanguage language: String?) -> String {
        switch language?.lowercased() {
        case "swift": return "swift"
        case "javascript": return "js"
        case "typescript": return "ts"
        case "python": return "py"
        case "html": return "html"
        case "css": return "css"
        case "c++": return "cpp"
        case "rust": return "rs"
        case "go": return "go"
        case "json": return "json"
        case "markdown": return "md"
        default: return "txt"
        }
    }
}
