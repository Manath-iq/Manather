//
//  ClaudeImporter.swift
//  manather
//
//  Pulls the building blocks the user already has set up for Claude Code into the
//  library, so they don't have to re-add them by hand:
//    • skills      — ~/.claude/skills/<slug>/SKILL.md
//    • MCP servers — the "mcpServers" entries in ~/.claude.json (global + per project)
//
//  Each becomes an AssetItem stored exactly like the manual "Add skill" / "Add MCP
//  server" sheets, so it behaves identically afterwards. Anything already in the
//  library (matched by name + type) is skipped, so re-running is safe.
//

import Foundation
import SwiftData

@MainActor
enum ClaudeImporter {

    struct ImportResult {
        var skillsAdded = 0
        var serversAdded = 0
        var skipped = 0
        var added: Int { skillsAdded + serversAdded }

        /// Short, human-readable summary for the Settings UI.
        var summary: String {
            if added == 0 && skipped == 0 {
                return "Nothing found in ~/.claude to import."
            }
            if added == 0 {
                return "Already up to date — \(skipped) item\(skipped == 1 ? "" : "s") already in your library."
            }
            var parts: [String] = []
            if skillsAdded > 0 { parts.append("\(skillsAdded) skill\(skillsAdded == 1 ? "" : "s")") }
            if serversAdded > 0 { parts.append("\(serversAdded) MCP server\(serversAdded == 1 ? "" : "s")") }
            var msg = "Imported \(parts.joined(separator: " and "))."
            if skipped > 0 { msg += " Skipped \(skipped) already present." }
            return msg
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var skillsDir: URL { home.appendingPathComponent(".claude/skills", isDirectory: true) }
    static var configFile: URL { home.appendingPathComponent(".claude.json") }

    /// Whether there's anything on disk worth importing (drives the button's enabled state).
    static var hasSource: Bool {
        FileManager.default.fileExists(atPath: skillsDir.path)
            || FileManager.default.fileExists(atPath: configFile.path)
    }

    /// Import skills and MCP servers into the library, skipping any already present.
    @discardableResult
    static func importAll(into context: ModelContext) -> ImportResult {
        var result = ImportResult()

        let existing = (try? context.fetch(FetchDescriptor<AssetItem>())) ?? []
        let existingSkills = Set(existing.filter { $0.assetType == .skill }.map { $0.title.lowercased() })
        let existingServers = Set(existing.filter { $0.assetType == .mcpServer }.map { $0.title.lowercased() })

        for skill in scanSkills() {
            guard !existingSkills.contains(skill.title.lowercased()) else { result.skipped += 1; continue }
            context.insert(AssetItem(
                title: skill.title, relativeFilePath: "",
                typeRaw: "skill", codeLanguage: "Markdown", codeContent: skill.markdown
            ))
            result.skillsAdded += 1
        }

        for server in scanServers() {
            guard !existingServers.contains(server.name.lowercased()) else { result.skipped += 1; continue }
            context.insert(AssetItem(
                title: server.name, relativeFilePath: "",
                typeRaw: "mcpServer", codeLanguage: server.command, codeContent: server.json
            ))
            result.serversAdded += 1
        }

        return result
    }

    // MARK: - Skills

    private struct ScannedSkill { let title: String; let markdown: String }

    private static func scanSkills() -> [ScannedSkill] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        var skills: [ScannedSkill] = []
        for dir in dirs {
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path),
                  let markdown = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }
            let title = frontmatterName(markdown) ?? dir.lastPathComponent
            skills.append(ScannedSkill(title: title, markdown: markdown))
        }
        return skills
    }

    /// Reads `name:` out of a leading `--- … ---` YAML frontmatter block, if any.
    private static func frontmatterName(_ markdown: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.lowercased().hasPrefix("name:") {
                let value = trimmed.dropFirst("name:".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !value.isEmpty { return String(value) }
            }
        }
        return nil
    }

    // MARK: - MCP servers

    private struct ScannedServer { let name: String; let command: String; let json: String }

    private static func scanServers() -> [ScannedServer] {
        guard let data = try? Data(contentsOf: configFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var byName: [String: [String: Any]] = [:]

        // Global servers take precedence.
        if let global = root["mcpServers"] as? [String: Any] {
            for (name, cfg) in global where byName[name] == nil {
                if let cfg = cfg as? [String: Any] { byName[name] = cfg }
            }
        }
        // Then per-project servers (deduped by name — don't shadow a global one).
        if let projects = root["projects"] as? [String: Any] {
            for (_, projectValue) in projects {
                guard let project = projectValue as? [String: Any],
                      let servers = project["mcpServers"] as? [String: Any] else { continue }
                for (name, cfg) in servers where byName[name] == nil {
                    if let cfg = cfg as? [String: Any] { byName[name] = cfg }
                }
            }
        }

        return byName.map { name, cfg in
            let command = (cfg["command"] as? String) ?? (cfg["url"] as? String) ?? ""
            return ScannedServer(name: name, command: command, json: prettyJSON(cfg) ?? "{}")
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
