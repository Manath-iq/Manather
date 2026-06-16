//
//  CLIAgent.swift
//  manather
//
//  Catalog of terminal AI coding agents the user might have installed, plus a
//  detector that checks whether each command exists and what version it is.
//
//  Detection runs an external process, which is only possible because the app
//  ships WITHOUT the App Sandbox (see manather.entitlements). A GUI app doesn't
//  inherit the shell's PATH, so we resolve commands through a login shell and
//  also probe the usual install locations. Command names come from this fixed
//  catalog — never from user input — so there is no shell-injection surface.
//

import Foundation
import Observation

struct CLIAgent: Identifiable, Sendable {
    let id: String
    let displayName: String
    let command: String          // the executable name, e.g. "codex"
    let summary: String
    let installCommand: String
    let authCommand: String      // how to sign in (shown, copyable)
    let docsURL: String
    let isLegacy: Bool           // dimmed / "being replaced"

    static let all: [CLIAgent] = [
        CLIAgent(
            id: "claude", displayName: "Claude Code", command: "claude",
            summary: "Anthropic's terminal coding agent. Reads CLAUDE.md packs directly.",
            installCommand: "npm install -g @anthropic-ai/claude-code",
            authCommand: "claude  (then /login)",
            docsURL: "https://docs.claude.com/en/docs/claude-code", isLegacy: false
        ),
        CLIAgent(
            id: "codex", displayName: "Codex CLI", command: "codex",
            summary: "OpenAI's terminal coding agent.",
            installCommand: "npm install -g @openai/codex",
            authCommand: "codex  (then sign in with ChatGPT or set OPENAI_API_KEY)",
            docsURL: "https://github.com/openai/codex", isLegacy: false
        ),
        CLIAgent(
            id: "antigravity", displayName: "Antigravity CLI", command: "antigravity",
            summary: "Google's terminal agent — the successor to Gemini CLI.",
            installCommand: "npm install -g @google/antigravity-cli",
            authCommand: "antigravity  (then sign in with Google)",
            docsURL: "https://antigravity.google/docs/cli-overview", isLegacy: false
        ),
        CLIAgent(
            id: "gemini", displayName: "Gemini CLI", command: "gemini",
            summary: "Google's earlier terminal agent (being replaced by Antigravity CLI).",
            installCommand: "npm install -g @google/gemini-cli",
            authCommand: "gemini  (then sign in with Google)",
            docsURL: "https://github.com/google-gemini/gemini-cli", isLegacy: true
        ),
    ]
}

/// Whether a CLI command was found and, if so, its version string.
enum CLIStatus: Equatable {
    case unknown
    case detecting
    case installed(version: String, path: String)
    case notFound
}

@Observable
final class CLIAgentDetector {
    private(set) var statuses: [String: CLIStatus] = [:]

    func status(for agent: CLIAgent) -> CLIStatus { statuses[agent.id] ?? .unknown }

    /// Kicks off detection for every catalog agent.
    func detectAll() {
        for agent in CLIAgent.all { detect(agent) }
    }

    func detect(_ agent: CLIAgent) {
        statuses[agent.id] = .detecting
        Task.detached {
            let status = CLIAgentDetector.probe(agent)
            await MainActor.run { self.statuses[agent.id] = status }
        }
    }

    // MARK: - Probing (runs off the main actor)

    private nonisolated static func probe(_ agent: CLIAgent) -> CLIStatus {
        guard let path = resolvePath(for: agent.command) else { return .notFound }
        let version = run(path, ["--version"])?
            .split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "installed"
        return .installed(version: version, path: path)
    }

    /// Finds the absolute path of `command`: first via a login shell (to pick up
    /// the user's PATH), then by probing the common install directories.
    private nonisolated static func resolvePath(for command: String) -> String? {
        if let viaShell = run("/bin/zsh", ["-lic", "command -v \(command) 2>/dev/null"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !viaShell.isEmpty,
            FileManager.default.isExecutableFile(atPath: viaShell) {
            return viaShell
        }
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin",
            "\(home)/.volta/bin", "\(home)/.deno/bin"
        ]
        for dir in candidates {
            let full = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    /// Runs an executable and returns its trimmed stdout, or nil on failure.
    private nonisolated static func run(_ launchPath: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
