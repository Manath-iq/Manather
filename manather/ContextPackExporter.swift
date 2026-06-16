//
//  ContextPackExporter.swift
//  manather
//
//  One-click export of a collection as an "AI context pack". The user picks a
//  target agent and Manather lays the files out the way that agent expects:
//
//  • Claude Code    — CLAUDE.md, .claude/skills/<name>/SKILL.md, .mcp.json
//  • AGENTS.md      — a single AGENTS.md (the cross-tool open standard read by
//                     Codex, Cursor, Copilot, Gemini, Windsurf, …) + mcp.json
//  • Generic        — CONTEXT.md + manifest.json (the original neutral format)
//
//  All profiles also copy media into assets/ and code snippets into snippets/.
//

import Foundation
import AppKit

/// Which agent the exported pack is tailored for.
enum ExportTarget: String, CaseIterable, Identifiable {
    case claudeCode
    case agentsMD
    case generic

    var id: String { rawValue }

    /// Label shown in the export menu.
    var menuLabel: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .agentsMD:   return "AGENTS.md (universal)"
        case .generic:    return "Generic context pack"
        }
    }

    /// Suffix appended to the default folder name in the save panel.
    var folderSuffix: String {
        switch self {
        case .claudeCode: return "-claude"
        case .agentsMD:   return "-agents"
        case .generic:    return "-context-pack"
        }
    }
}

enum ContextPackExporter {

    /// Shows a save panel, then writes the pack for the chosen target.
    /// Call from the main actor.
    static func export(projectName: String, assets: [AssetItem], target: ExportTarget = .generic) {
        let panel = NSSavePanel()
        panel.title = "Export — \(target.menuLabel)"
        panel.nameFieldStringValue = sanitized(projectName) + target.folderSuffix
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writePack(to: url, projectName: projectName, assets: assets, target: target)
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

    private static func writePack(to root: URL, projectName: String, assets: [AssetItem], target: ExportTarget) throws {
        switch target {
        case .generic:    try writeGenericPack(to: root, projectName: projectName, assets: assets)
        case .claudeCode: try writeClaudePack(to: root, projectName: projectName, assets: assets)
        case .agentsMD:   try writeAgentsPack(to: root, projectName: projectName, assets: assets)
        }
    }

    // MARK: - Generic pack (original neutral format)

    private static func writeGenericPack(to root: URL, projectName: String, assets: [AssetItem]) throws {
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

    // MARK: - Claude Code pack

    private static func writeClaudePack(to root: URL, projectName: String, assets: [AssetItem]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let live = assets.filter { !$0.isTrash && !$0.isDeleted }
        let files = try copyMediaAndSnippets(live, root: root, fm: fm)

        // Skills → .claude/skills/<name>/SKILL.md (Claude loads these automatically).
        let skills = live.filter { $0.assetType == .skill }
        var skillRefs: [(title: String, path: String)] = []
        if !skills.isEmpty {
            let skillsRoot = root.appendingPathComponent(".claude/skills", isDirectory: true)
            var usedDirs = Set<String>()
            for skill in skills {
                let dirName = uniqueSlug(skill.title, used: &usedDirs)
                let dir = skillsRoot.appendingPathComponent(dirName, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let body = skillDocument(name: dirName, asset: skill)
                let rel = ".claude/skills/\(dirName)/SKILL.md"
                try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
                skillRefs.append((skill.title, rel))
            }
        }

        // MCP servers → .mcp.json
        let mcpServers = live.filter { $0.assetType == .mcpServer }
        var wroteMCP = false
        if !mcpServers.isEmpty {
            let json = try buildMCPConfig(mcpServers)
            try json.write(to: root.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
            wroteMCP = true
        }

        // CLAUDE.md — project memory pointing at everything above.
        let md = buildAgentInstructions(
            projectName: projectName,
            headerName: "CLAUDE.md",
            assets: live,
            files: files,
            skillRefs: skillRefs,
            inlineSkills: false,
            mcpConfigPath: wroteMCP ? ".mcp.json" : nil,
            mcpServers: mcpServers
        )
        try md.write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - AGENTS.md pack (cross-tool standard)

    private static func writeAgentsPack(to root: URL, projectName: String, assets: [AssetItem]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let live = assets.filter { !$0.isTrash && !$0.isDeleted }
        let files = try copyMediaAndSnippets(live, root: root, fm: fm)

        // There is no universal "skills" mechanism, so skills are inlined into
        // AGENTS.md and also dropped into skills/ as standalone files.
        let skills = live.filter { $0.assetType == .skill }
        var skillRefs: [(title: String, path: String)] = []
        if !skills.isEmpty {
            let skillsDir = root.appendingPathComponent("skills", isDirectory: true)
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            var used = Set<String>()
            for skill in skills {
                let name = uniqueSlug(skill.title, used: &used)
                let rel = "skills/\(name).md"
                try (skill.codeContent ?? "").write(to: skillsDir.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
                skillRefs.append((skill.title, rel))
            }
        }

        // MCP servers → mcp.json (no standard path under AGENTS.md, so keep it
        // at the root and reference it from the doc).
        let mcpServers = live.filter { $0.assetType == .mcpServer }
        var wroteMCP = false
        if !mcpServers.isEmpty {
            let json = try buildMCPConfig(mcpServers)
            try json.write(to: root.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)
            wroteMCP = true
        }

        let md = buildAgentInstructions(
            projectName: projectName,
            headerName: "AGENTS.md",
            assets: live,
            files: files,
            skillRefs: skillRefs,
            inlineSkills: true,
            mcpConfigPath: wroteMCP ? "mcp.json" : nil,
            mcpServers: mcpServers
        )
        try md.write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - Shared file copying

    /// Copies media into assets/ and code snippets into snippets/.
    /// Returns each copied asset's relative path keyed by its id.
    private static func copyMediaAndSnippets(_ assets: [AssetItem], root: URL, fm: FileManager) throws -> [UUID: String] {
        let assetsDir = root.appendingPathComponent("assets", isDirectory: true)
        let snippetsDir = root.appendingPathComponent("snippets", isDirectory: true)
        var files: [UUID: String] = [:]

        for asset in assets {
            switch asset.assetType {
            case .image, .gif, .video:
                guard !asset.relativeFilePath.isEmpty else { continue }
                let src = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                let destName = uniqueName(for: asset, ext: src.pathExtension)
                try? fm.copyItem(at: src, to: assetsDir.appendingPathComponent(destName))
                files[asset.id] = "assets/\(destName)"

            case .codeSnippet:
                try fm.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
                let ext = fileExtension(forLanguage: asset.codeLanguage)
                let destName = sanitized(asset.title) + "." + ext
                try (asset.codeContent ?? "").write(to: snippetsDir.appendingPathComponent(destName), atomically: true, encoding: .utf8)
                files[asset.id] = "snippets/\(destName)"

            default:
                break
            }
        }
        return files
    }

    // MARK: - MCP config

    /// Builds a `{ "mcpServers": { … } }` JSON string from MCP-server assets.
    /// Each asset stores a launch command in `codeLanguage` and a JSON config
    /// in `codeContent`; we parse the config when possible and fall back to a
    /// command-only entry otherwise.
    private static func buildMCPConfig(_ servers: [AssetItem]) throws -> String {
        var entries: [String: Any] = [:]
        var used = Set<String>()

        for server in servers {
            let parsed = server.codeContent.flatMap { content -> [String: Any]? in
                guard let data = content.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }

            // A user may have pasted a full { "mcpServers": { … } } block —
            // merge those entries directly instead of nesting them.
            if let parsed, let nested = parsed["mcpServers"] as? [String: Any] {
                for (key, value) in nested {
                    entries[uniqueKey(key, used: &used)] = value
                }
                continue
            }

            let key = uniqueKey(slug(server.title), used: &used)
            if var entry = parsed {
                if entry["command"] == nil, let cmd = server.codeLanguage, !cmd.isEmpty {
                    entry["command"] = cmd
                }
                entries[key] = entry
            } else {
                var entry: [String: Any] = [:]
                if let cmd = server.codeLanguage, !cmd.isEmpty { entry["command"] = cmd }
                if let cfg = server.codeContent, !cfg.isEmpty { entry["config"] = cfg }
                entries[key] = entry
            }
        }

        let root: [String: Any] = ["mcpServers": entries]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Skill documents

    /// A SKILL.md body with the YAML frontmatter Claude Code expects. If the
    /// stored markdown already starts with frontmatter, it's used verbatim.
    private static func skillDocument(name: String, asset: AssetItem) -> String {
        let body = asset.codeContent ?? ""
        if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            return body
        }
        let description = skillDescription(for: asset)
        return """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
    }

    /// One-line description for skill frontmatter: notes → prompt → title.
    private static func skillDescription(for asset: AssetItem) -> String {
        let candidate = !asset.notes.isEmpty ? asset.notes
            : (!asset.prompt.isEmpty ? asset.prompt : asset.title)
        return candidate
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Agent instructions (CLAUDE.md / AGENTS.md body)

    private static func buildAgentInstructions(
        projectName: String,
        headerName: String,
        assets: [AssetItem],
        files: [UUID: String],
        skillRefs: [(title: String, path: String)],
        inlineSkills: Bool,
        mcpConfigPath: String?,
        mcpServers: [AssetItem]
    ) -> String {
        var md = """
        # \(projectName)

        > Project context exported from Manather (`\(headerName)`). It collects the
        > reference materials, skills, MCP servers, and code snippets for building
        > this project. Read everything below before starting work.

        """

        let skills = assets.filter { $0.assetType == .skill }
        let snippets = assets.filter { $0.assetType == .codeSnippet }
        let links = assets.filter { $0.assetType == .webLink }
        let media = assets.filter { $0.assetType == .image || $0.assetType == .gif || $0.assetType == .video }

        // Skills
        if !skills.isEmpty {
            if inlineSkills {
                md += "\n## Skills (follow these instructions)\n"
                for skill in skills {
                    md += "\n### \(skill.title)\n"
                    if let ref = skillRefs.first(where: { $0.title == skill.title }) {
                        md += "\nFull file: `\(ref.path)`\n"
                    }
                    if let content = skill.codeContent, !content.isEmpty {
                        md += "\n\(content)\n"
                    }
                }
            } else {
                md += "\n## Skills\n\nThese are installed under `.claude/skills/` and load automatically:\n\n"
                for ref in skillRefs {
                    md += "- **\(ref.title)** — `\(ref.path)`\n"
                }
            }
        }

        // MCP servers
        if !mcpServers.isEmpty {
            md += "\n## MCP Servers (connect these before working)\n"
            if let path = mcpConfigPath {
                md += "\nConfig: `\(path)`\n"
            }
            for server in mcpServers {
                md += "\n### \(server.title)\n"
                if let cmd = server.codeLanguage, !cmd.isEmpty {
                    md += "\nLaunch command:\n```\n\(cmd)\n```\n"
                }
                if !server.notes.isEmpty { md += "\n\(server.notes)\n" }
            }
        }

        // Code snippets
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

        // Visual references
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

        // Reference links
        if !links.isEmpty {
            md += "\n## Reference Links\n"
            for link in links {
                md += "\n- [\(link.title)](\(link.sourceURL))"
                if !link.notes.isEmpty { md += " — \(link.notes)" }
            }
            md += "\n"
        }

        return md
    }

    // MARK: - CONTEXT.md Generation (generic pack)

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

    /// Lowercase-hyphen identifier used for skill names and MCP keys.
    private static func slug(_ name: String) -> String { sanitized(name) }

    /// A slug guaranteed unique within `used` (appends -2, -3, … on collision).
    private static func uniqueSlug(_ name: String, used: inout Set<String>) -> String {
        uniqueKey(slug(name), used: &used)
    }

    private static func uniqueKey(_ base: String, used: inout Set<String>) -> String {
        var candidate = base.isEmpty ? "untitled" : base
        var n = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        used.insert(candidate)
        return candidate
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
