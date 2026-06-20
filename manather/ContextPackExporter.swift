//
//  ContextPackExporter.swift
//  manather
//
//  One-click export of a collection as an AI "build pack" — a self-contained
//  folder an agent can open and start building from. The layout is two-tier:
//
//  • Entry file  — CLAUDE.md / AGENTS.md / README.md depending on the target.
//                  A short "control panel": what the pack is, a map of the
//                  folders, and a ▶ Start workflow the agent follows when the
//                  user says "start".
//  • context.md  — the catalog. Every file described with its title, notes,
//                  generation prompt, palette, tags and source.
//
//  Per target only the files that target needs are written (no clutter):
//
//  • Claude Code — CLAUDE.md, .claude/skills/<name>/SKILL.md, .mcp.json
//                  (skills + MCP are wired up so a Claude Code session in the
//                  folder works immediately).
//  • AGENTS.md   — AGENTS.md, skills/<name>.md, mcp/mcp.json
//  • Generic     — README.md, skills/<name>.md, mcp/mcp.json
//
//  All targets also copy media into images/, code snippets into snippets/, and
//  write a machine-readable manifest.json.
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
        case .generic:    return "Generic build pack"
        }
    }

    /// Suffix appended to the default folder name in the save panel.
    var folderSuffix: String {
        switch self {
        case .claudeCode: return "-claude"
        case .agentsMD:   return "-agents"
        case .generic:    return "-pack"
        }
    }
}

enum ContextPackExporter {

    // MARK: - Layout per target

    /// Where each kind of file lands for a given target. Keeping this in one
    /// place is what lets a single `writePack` serve all three targets.
    private struct Layout {
        let entryName: String
        /// true → skills go to `.claude/skills/<slug>/SKILL.md` (auto-loaded);
        /// false → `skills/<slug>.md`.
        let skillsClaudeStyle: Bool
        /// true → MCP config at root `.mcp.json`; false → `mcp/mcp.json`.
        let mcpAtRoot: Bool

        /// Claude Code packs are "wired up" — skills auto-load and MCP is at the
        /// path Claude reads by default.
        var autoWired: Bool { skillsClaudeStyle && mcpAtRoot }

        var skillsDirLabel: String { skillsClaudeStyle ? ".claude/skills/" : "skills/" }
        var mcpPathLabel: String { mcpAtRoot ? ".mcp.json" : "mcp/mcp.json" }

        static func of(_ target: ExportTarget) -> Layout {
            switch target {
            case .claudeCode: return Layout(entryName: "CLAUDE.md", skillsClaudeStyle: true,  mcpAtRoot: true)
            case .agentsMD:   return Layout(entryName: "AGENTS.md", skillsClaudeStyle: false, mcpAtRoot: false)
            case .generic:    return Layout(entryName: "README.md", skillsClaudeStyle: false, mcpAtRoot: false)
            }
        }
    }

    private static let mediaDir = "images"
    private static let snippetsDir = "snippets"

    // MARK: - Entry point

    /// Shows a save panel, then writes the pack for the chosen target.
    /// `goal` is the free-text project brief the user typed at export time
    /// (what they want built); empty means "let the agent infer from materials".
    /// Call from the main actor.
    static func export(projectName: String, assets: [AssetItem], target: ExportTarget = .generic,
                       goal: String = "", gitInit: Bool = false) {
        let panel = NSSavePanel()
        panel.title = "Export — \(target.menuLabel)"
        panel.nameFieldStringValue = sanitized(projectName) + target.folderSuffix
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writePack(to: url, projectName: projectName, assets: assets, target: target, goal: goal)
                // Optionally turn the pack into a git repo with a first commit. A
                // git failure shouldn't lose the export — warn but keep the folder.
                if gitInit {
                    do {
                        try GitExporter.initRepo(at: url)
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = "Exported, but git init failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
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

    // MARK: - Pack writer (shared by all targets)

    /// Writes a pack directly to `root` with no save panel. Used by the interactive
    /// `export(…)` above and by the MCP server (which already knows the destination).
    static func writePack(to root: URL, projectName: String, assets: [AssetItem], target: ExportTarget, goal: String) throws {
        let fm = FileManager.default
        let layout = Layout.of(target)
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let live = assets.filter { !$0.isTrash && !$0.isDeleted }

        // 1. Copy media → images/ and snippets → snippets/.
        let files = try copyMediaAndSnippets(live, root: root, fm: fm)

        // 2. Skills → per-layout location.
        let skills = live.filter { $0.assetType == .skill }
        let skillRefs = try writeSkills(skills, root: root, layout: layout, fm: fm)

        // 3. MCP servers → per-layout config file.
        let mcpServers = live.filter { $0.assetType == .mcpServer }
        var mcpPath: String? = nil
        var mcpKeys: [UUID: [String]] = [:]
        if !mcpServers.isEmpty {
            let built = try buildMCPConfig(mcpServers)
            mcpKeys = built.keys
            let dest: URL
            if layout.mcpAtRoot {
                dest = root.appendingPathComponent(".mcp.json")
            } else {
                let mcpDir = root.appendingPathComponent("mcp", isDirectory: true)
                try fm.createDirectory(at: mcpDir, withIntermediateDirectories: true)
                dest = mcpDir.appendingPathComponent("mcp.json")
            }
            try built.json.write(to: dest, atomically: true, encoding: .utf8)
            mcpPath = layout.mcpPathLabel
        }

        // 4. context.md — the catalog.
        let catalog = buildCatalog(
            projectName: projectName,
            entryName: layout.entryName,
            goal: trimmedGoal,
            assets: live,
            files: files,
            skillRefs: skillRefs,
            mcpPath: mcpPath,
            mcpKeys: mcpKeys
        )
        try catalog.write(to: root.appendingPathComponent("context.md"), atomically: true, encoding: .utf8)

        // 5. Entry file — the control panel + ▶ Start workflow.
        let entry = buildEntryDoc(projectName: projectName, layout: layout, goal: trimmedGoal, assets: live, mcpPath: mcpPath)
        try entry.write(to: root.appendingPathComponent(layout.entryName), atomically: true, encoding: .utf8)

        // 6. manifest.json — machine-readable index.
        let manifest = buildManifest(
            projectName: projectName,
            goal: trimmedGoal,
            assets: live,
            files: files,
            skillRefs: skillRefs,
            mcpKeys: mcpKeys
        )
        let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: root.appendingPathComponent("manifest.json"))
    }

    // MARK: - File copying

    /// Copies media into images/ and code snippets into snippets/.
    /// Returns each copied asset's relative path keyed by its id.
    private static func copyMediaAndSnippets(_ assets: [AssetItem], root: URL, fm: FileManager) throws -> [UUID: String] {
        let imagesDir = root.appendingPathComponent(mediaDir, isDirectory: true)
        let snippets = root.appendingPathComponent(snippetsDir, isDirectory: true)
        var files: [UUID: String] = [:]

        for asset in assets {
            switch asset.assetType {
            case .image, .gif, .video:
                guard !asset.relativeFilePath.isEmpty else { continue }
                let src = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                let destName = uniqueName(for: asset, ext: src.pathExtension)
                try? fm.copyItem(at: src, to: imagesDir.appendingPathComponent(destName))
                files[asset.id] = "\(mediaDir)/\(destName)"

            case .codeSnippet:
                try fm.createDirectory(at: snippets, withIntermediateDirectories: true)
                let ext = fileExtension(forLanguage: asset.codeLanguage)
                let destName = sanitized(asset.title) + "." + ext
                try (asset.codeContent ?? "").write(to: snippets.appendingPathComponent(destName), atomically: true, encoding: .utf8)
                files[asset.id] = "\(snippetsDir)/\(destName)"

            default:
                break
            }
        }
        return files
    }

    /// Writes skill assets to the location dictated by `layout`. Returns each
    /// skill's relative path keyed by its id.
    private static func writeSkills(_ skills: [AssetItem], root: URL, layout: Layout, fm: FileManager) throws -> [UUID: String] {
        guard !skills.isEmpty else { return [:] }
        var refs: [UUID: String] = [:]
        var used = Set<String>()

        if layout.skillsClaudeStyle {
            let skillsRoot = root.appendingPathComponent(".claude/skills", isDirectory: true)
            for skill in skills {
                let slugName = uniqueSlug(skill.title, used: &used)
                let dir = skillsRoot.appendingPathComponent(slugName, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try skillDocument(name: slugName, asset: skill)
                    .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
                refs[skill.id] = ".claude/skills/\(slugName)/SKILL.md"
            }
        } else {
            let skillsDir = root.appendingPathComponent("skills", isDirectory: true)
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            for skill in skills {
                let slugName = uniqueSlug(skill.title, used: &used)
                try (skill.codeContent ?? "")
                    .write(to: skillsDir.appendingPathComponent("\(slugName).md"), atomically: true, encoding: .utf8)
                refs[skill.id] = "skills/\(slugName).md"
            }
        }
        return refs
    }

    // MARK: - MCP config

    /// Builds a `{ "mcpServers": { … } }` JSON string from MCP-server assets and
    /// reports which config keys each asset contributed (for the catalog).
    ///
    /// Each asset stores a launch command in `codeLanguage` and a JSON config in
    /// `codeContent`; we parse the config when possible and fall back to a
    /// command-only entry otherwise.
    private static func buildMCPConfig(_ servers: [AssetItem]) throws -> (json: String, keys: [UUID: [String]]) {
        var entries: [String: Any] = [:]
        var used = Set<String>()
        var keysByAsset: [UUID: [String]] = [:]

        for server in servers {
            let parsed = server.codeContent.flatMap { content -> [String: Any]? in
                guard let data = content.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }

            // A user may have pasted a full { "mcpServers": { … } } block —
            // merge those entries directly instead of nesting them.
            if let parsed, let nested = parsed["mcpServers"] as? [String: Any] {
                for (key, value) in nested {
                    let k = uniqueKey(key, used: &used)
                    entries[k] = value
                    keysByAsset[server.id, default: []].append(k)
                }
                continue
            }

            let key = uniqueKey(slug(server.title), used: &used)
            keysByAsset[server.id, default: []].append(key)
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

        let rootObj: [String: Any] = ["mcpServers": entries]
        let data = try JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "{}", keysByAsset)
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

    /// One-line description for a skill: notes → prompt → title.
    private static func skillDescription(for asset: AssetItem) -> String {
        let candidate = !asset.notes.isEmpty ? asset.notes
            : (!asset.prompt.isEmpty ? asset.prompt : asset.title)
        return candidate
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Entry document (CLAUDE.md / AGENTS.md / README.md)

    /// The short "control panel": what the pack is, a map of the folders that
    /// actually exist, and the universal ▶ Start workflow.
    private static func buildEntryDoc(projectName: String, layout: Layout, goal: String, assets: [AssetItem], mcpPath: String?) -> String {
        let hasImages = assets.contains { $0.assetType == .image || $0.assetType == .gif || $0.assetType == .video }
        let hasSkills = assets.contains { $0.assetType == .skill }
        let hasSnippets = assets.contains { $0.assetType == .codeSnippet }
        let hasMCP = mcpPath != nil

        var md = """
        # \(projectName)

        > **Build pack** exported from Manather. This folder is a self-contained brief
        > for building **\(projectName)**. Everything you need — references, skills, MCP
        > servers, code snippets and links — is here and catalogued in `context.md`.

        """

        if !goal.isEmpty {
            md += """

            ## 🎯 Goal

            \(goal)

            """
        }

        md += """

        ## How to use this pack

        1. **Read `context.md` first.** It is the full catalog: every file in this
           folder with its description, generation prompt, palette and notes.
        2. Then open the materials it points to and start building.

        ## What's inside

        - `context.md` — the catalog (read this first).

        """
        if hasImages { md += "- `\(mediaDir)/` — visual references: the look & feel to match.\n" }
        if hasSkills {
            let suffix = layout.autoWired ? " (loaded automatically)" : ""
            md += "- `\(layout.skillsDirLabel)` — skills to follow\(suffix).\n"
        }
        if hasMCP {
            let suffix = layout.autoWired ? " (already wired up)" : ""
            md += "- `\(layout.mcpPathLabel)` — MCP servers\(suffix).\n"
        }
        if hasSnippets { md += "- `\(snippetsDir)/` — reusable code patterns.\n" }
        md += "- `manifest.json` — machine-readable index of everything above.\n"

        // ▶ Start workflow (universal).
        let skillsClause: String = {
            guard hasSkills else { return "" }
            return layout.autoWired
                ? " Follow every skill in `\(layout.skillsDirLabel)` (they load automatically)."
                : " Follow every skill listed in `context.md`."
        }()
        let mcpClause: String = {
            guard let mcpPath else { return "" }
            return " Connect every MCP server from `\(mcpPath)`."
        }()
        let snippetsClause = hasSnippets ? " Reuse the `\(snippetsDir)/` patterns wherever they fit." : ""

        var steps: [String] = [
            "Read **`context.md`** end to end.",
            "Restate in 2–3 sentences what you're about to build and the stack you'll use. Ask only genuinely blocking questions; otherwise proceed."
        ]
        if hasImages {
            steps.append("Treat the files in `\(mediaDir)/` as the **visual target** — match their layout, spacing, colours (each image's palette is listed in `context.md`) and overall mood.")
        }
        let buildTarget = goal.isEmpty
            ? "the project described in `context.md`"
            : "toward the **Goal** stated above, using everything in `context.md`"
        steps.append("Build \(buildTarget).\(skillsClause)\(mcpClause)\(snippetsClause)")
        steps.append("Scaffold the project, then keep building until it actually runs.")
        steps.append("Finish with a short summary of what you built and how to run it.")

        let numbered = steps.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        md += """

        ## ▶ Start

        When the user says **start** (or "go" / "build it"), work through this without
        stopping for confirmation between steps:

        \(numbered)

        ---

        *Generated by Manather.*
        """
        return md
    }

    // MARK: - context.md (the catalog)

    private static func buildCatalog(
        projectName: String,
        entryName: String,
        goal: String,
        assets: [AssetItem],
        files: [UUID: String],
        skillRefs: [UUID: String],
        mcpPath: String?,
        mcpKeys: [UUID: [String]]
    ) -> String {
        var md = """
        # \(projectName) — Catalog

        > Index of everything in this pack, exported from Manather on \
        \(ISO8601DateFormatter().string(from: Date())). Paths are relative to this
        > folder. See `\(entryName)` for how to use it.

        """

        if !goal.isEmpty {
            md += """

            ## 🎯 Goal

            \(goal)

            """
        }

        let media    = assets.filter { $0.assetType == .image || $0.assetType == .gif || $0.assetType == .video }
        let skills   = assets.filter { $0.assetType == .skill }
        let mcp      = assets.filter { $0.assetType == .mcpServer }
        let snippets = assets.filter { $0.assetType == .codeSnippet }
        let links    = assets.filter { $0.assetType == .webLink }

        // Visual references
        if !media.isEmpty {
            md += "\n## Visual references\n"
            for item in media {
                md += "\n### \(item.title)\n"
                if let file = files[item.id] {
                    var line = "- File: `\(file)`"
                    if let dims = dimensions(item) { line += "  ·  \(dims)" }
                    md += line + "\n"
                }
                if !item.notes.isEmpty { md += "- Description: \(oneLine(item.notes))\n" }
                if !item.prompt.isEmpty { md += "- Generation prompt: \(oneLine(item.prompt))\n" }
                if let colors = item.dominantColorsHex, !colors.isEmpty {
                    md += "- Palette: " + colors.map { "`\($0)`" }.joined(separator: " ") + "\n"
                }
                if !item.tags.isEmpty { md += "- Tags: \(item.tags.joined(separator: ", "))\n" }
                if !item.sourceURL.isEmpty { md += "- Source: \(item.sourceURL)\n" }
            }
        }

        // Skills
        if !skills.isEmpty {
            md += "\n## Skills (follow these)\n"
            for skill in skills {
                md += "\n### \(skill.title)\n"
                if let file = skillRefs[skill.id] { md += "- File: `\(file)`\n" }
                md += "- Purpose: \(skillDescription(for: skill))\n"
            }
        }

        // MCP servers
        if !mcp.isEmpty {
            md += "\n## MCP servers (connect these)\n"
            for server in mcp {
                md += "\n### \(server.title)\n"
                if let path = mcpPath {
                    var line = "- Config: `\(path)`"
                    if let keys = mcpKeys[server.id], !keys.isEmpty {
                        line += " (key\(keys.count == 1 ? "" : "s"): " + keys.map { "`\($0)`" }.joined(separator: ", ") + ")"
                    }
                    md += line + "\n"
                }
                if let cmd = server.codeLanguage, !cmd.isEmpty { md += "- Command: `\(cmd)`\n" }
                if !server.notes.isEmpty { md += "- Notes: \(oneLine(server.notes))\n" }
            }
        }

        // Code snippets
        if !snippets.isEmpty {
            md += "\n## Code snippets (reuse these patterns)\n"
            for snippet in snippets {
                var heading = "\n### \(snippet.title)"
                if let lang = snippet.codeLanguage { heading += " (\(lang))" }
                md += heading + "\n"
                if let file = files[snippet.id] { md += "- File: `\(file)`\n" }
                if !snippet.notes.isEmpty { md += "- Notes: \(oneLine(snippet.notes))\n" }
                if !snippet.prompt.isEmpty { md += "- Prompt: \(oneLine(snippet.prompt))\n" }
            }
        }

        // Reference links
        if !links.isEmpty {
            md += "\n## Reference links\n\n"
            for link in links {
                md += "- [\(link.title)](\(link.sourceURL))"
                if !link.notes.isEmpty { md += " — \(oneLine(link.notes))" }
                md += "\n"
            }
        }

        return md
    }

    // MARK: - manifest.json

    private static func buildManifest(
        projectName: String,
        goal: String,
        assets: [AssetItem],
        files: [UUID: String],
        skillRefs: [UUID: String],
        mcpKeys: [UUID: [String]]
    ) -> [String: Any] {
        var entries: [[String: Any]] = []
        for asset in assets {
            var entry: [String: Any] = [
                "id": asset.id.uuidString,
                "title": asset.title,
                "type": asset.typeRaw
            ]
            if !asset.prompt.isEmpty { entry["prompt"] = asset.prompt }
            if !asset.notes.isEmpty { entry["notes"] = asset.notes }
            if !asset.sourceURL.isEmpty { entry["sourceURL"] = asset.sourceURL }
            if !asset.tags.isEmpty { entry["tags"] = asset.tags }
            if let file = files[asset.id] ?? skillRefs[asset.id] { entry["file"] = file }
            if let colors = asset.dominantColorsHex, !colors.isEmpty { entry["palette"] = colors }
            if let lang = asset.codeLanguage, asset.assetType == .codeSnippet { entry["language"] = lang }
            if asset.assetType == .mcpServer, let keys = mcpKeys[asset.id] { entry["mcpKeys"] = keys }
            entries.append(entry)
        }
        var manifest: [String: Any] = [
            "project": projectName,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "generator": "Manather",
            "assets": entries
        ]
        if !goal.isEmpty { manifest["goal"] = goal }
        return manifest
    }

    // MARK: - Helpers

    /// "1920×1080" when both dimensions are known, otherwise nil.
    private static func dimensions(_ asset: AssetItem) -> String? {
        guard asset.imageWidth > 0, asset.imageHeight > 0 else { return nil }
        return "\(Int(asset.imageWidth))×\(Int(asset.imageHeight))"
    }

    /// Collapses newlines so multi-line notes stay on a single catalog bullet.
    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        let safe = base.isEmpty ? "untitled" : base
        var candidate = safe
        var n = 2
        while used.contains(candidate) {
            candidate = "\(safe)-\(n)"
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
