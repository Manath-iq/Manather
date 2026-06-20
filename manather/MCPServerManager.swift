//
//  MCPServerManager.swift
//  manather
//
//  Owns the lifetime of the local MCP server: holds the token/port, starts and
//  stops the loopback HTTP listener, and wires it to the MCP protocol layer. A
//  single shared instance (like ImageCache.shared) so the server outlives the
//  Settings window that toggles it.
//
//  Preferences (enabled flag, port) live in UserDefaults so the Settings view can
//  bind to them with @AppStorage; the access token is generated once and kept in
//  UserDefaults too — it only guards a 127.0.0.1-only endpoint.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class MCPServerManager {
    static let shared = MCPServerManager()

    static let enabledKey = "mcpEnabled"
    static let portKey = "mcpPort"
    private static let tokenKey = "mcpToken"
    static let defaultPort: UInt16 = 4319

    /// Runtime status (observed by the Settings view).
    private(set) var isRunning = false
    private(set) var lastError: String?

    /// Stable access token for this install.
    let token: String

    private var container: ModelContainer?
    private var httpServer: MCPHTTPServer?
    private var mcpServer: MCPServer?

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.tokenKey), !saved.isEmpty {
            token = saved
        } else {
            let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(generated, forKey: Self.tokenKey)
            token = generated
        }
    }

    /// The port read from preferences, clamped to a sane range.
    var port: UInt16 {
        let raw = UserDefaults.standard.integer(forKey: Self.portKey)
        guard raw >= 1024, raw <= 65535 else { return Self.defaultPort }
        return UInt16(raw)
    }

    var endpointURL: String { "http://127.0.0.1:\(port)/mcp" }

    // MARK: - Lifecycle

    /// Must be called once at launch with the app's container.
    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Start the server if the user has it enabled (called at launch).
    func startIfEnabled() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) { start() }
    }

    /// React to the Settings toggle.
    func apply(enabled: Bool) {
        enabled ? start() : stop()
    }

    /// Re-bind on a port change while running.
    func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    func start() {
        guard let container else { lastError = "Library data isn't ready yet."; return }
        guard !isRunning else { return }
        lastError = nil

        let service = MCPLibraryService(container: container)
        let mcp = MCPServer(service: service)
        let http = MCPHTTPServer(port: port, token: token)
        do {
            try http.start(handler: { request in
                await mcp.handle(request)
            }, onStatus: { running, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isRunning = running
                    if let error, !running { self.lastError = error }
                }
            })
            self.mcpServer = mcp
            self.httpServer = http
            self.isRunning = true
        } catch {
            self.lastError = "Couldn't start on port \(port): \(error.localizedDescription)"
            self.isRunning = false
        }
    }

    func stop() {
        httpServer?.stop()
        httpServer = nil
        mcpServer = nil
        isRunning = false
    }
}
