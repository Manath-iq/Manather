//
//  GitExporter.swift
//  manather
//
//  Turns a freshly-written context pack into a ready-to-push git repository:
//  `git init` → `git add -A` → first commit. Lets a user export a project and
//  drop it straight into version control (or a new GitHub repo) in one step.
//
//  Runs the system git (App Sandbox is intentionally off — see CLAUDE.md). Uses
//  the user's own git identity when configured, otherwise a neutral fallback so
//  the initial commit always succeeds.
//

import Foundation

enum GitExporter {

    enum GitError: LocalizedError {
        case notInstalled
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Git isn't available. Install the Xcode Command Line Tools (run “xcode-select --install” in Terminal) and try again."
            case .commandFailed(let message):
                return message
            }
        }
    }

    private static let gitPath = "/usr/bin/git"

    /// Initialise a repo at `root`, stage everything and make the first commit.
    static func initRepo(at root: URL) throws {
        guard FileManager.default.fileExists(atPath: gitPath) else { throw GitError.notInstalled }

        try run(["init"], in: root)
        try run(["add", "-A"], in: root)

        var commitArgs = ["commit", "-m", "Initial commit — exported from Manather"]
        if !hasIdentity(in: root) {
            commitArgs = ["-c", "user.name=Manather", "-c", "user.email=manather@localhost"] + commitArgs
        }
        try run(commitArgs, in: root)
    }

    /// True if git can already resolve a commit identity (global or repo-local).
    private static func hasIdentity(in root: URL) -> Bool {
        let email = (try? exec(["config", "user.email"], in: root))?.output
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !email.isEmpty
    }

    @discardableResult
    private static func run(_ args: [String], in dir: URL) throws -> String {
        let result = try exec(args, in: dir)
        guard result.status == 0 else {
            throw GitError.commandFailed("git \(args.joined(separator: " ")) failed:\n\(result.output)")
        }
        return result.output
    }

    private static func exec(_ args: [String], in dir: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = dir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
