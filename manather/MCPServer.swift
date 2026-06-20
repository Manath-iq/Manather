//
//  MCPServer.swift
//  manather
//
//  The MCP protocol layer. It speaks JSON-RPC 2.0 over the HTTP body delivered by
//  MCPHTTPServer, implements the MCP handshake (initialize / tools/list /
//  tools/call), and turns each tool call into a method on MCPLibraryService.
//
//  Tool results are returned as a single text block containing JSON — universally
//  understood by MCP clients, and easy for an agent to parse. For media assets the
//  JSON includes an absolute `filePath` so a local agent can read the bytes itself.
//
//  This type is @MainActor (it drives the app's ModelContext through the service),
//  which also makes it implicitly Sendable so it can be captured by the HTTP
//  server's connection handler.
//

import Foundation

/// Capability groups the user can switch off in Settings → MCP Server. Each tool
/// belongs to one group; a disabled group hides its tools from `tools/list` and is
/// rejected at call time. Read live from UserDefaults so toggles take effect
/// without restarting the server. Absent key == enabled (the default).
enum MCPCapability: String, CaseIterable {
    case browse, create, add, edit, export

    var key: String { "mcpCap_" + rawValue }

    /// Human label for the Settings toggle.
    var title: String {
        switch self {
        case .browse: return "Browse & search"
        case .create: return "Create libraries & collections"
        case .add:    return "Add assets"
        case .edit:   return "Edit assets"
        case .export: return "Export context packs"
        }
    }

    var subtitle: String {
        switch self {
        case .browse: return "List, search and read assets"
        case .create: return "Make new libraries and collections"
        case .add:    return "Add images, snippets, links, skills, MCP configs"
        case .edit:   return "Change collections, tags and prompts"
        case .export: return "Export a collection as a context pack folder"
        }
    }

    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    /// Which capability a tool belongs to.
    static func forTool(_ name: String) -> MCPCapability {
        switch name {
        case "create_library", "create_collection":
            return .create
        case "add_image", "add_snippet", "add_web_link", "add_skill", "add_mcp_server":
            return .add
        case "add_to_collection", "remove_from_collection", "set_tags", "set_prompt":
            return .edit
        case "export_context_pack":
            return .export
        default:
            return .browse
        }
    }

    static func allows(toolNamed name: String) -> Bool { forTool(name).isEnabled }
}

@MainActor
final class MCPServer {
    private let service: MCPLibraryService

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    init(service: MCPLibraryService) {
        self.service = service
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    // MARK: - HTTP entry point

    /// Handles one POST /mcp body and produces the HTTP response.
    func handle(_ request: MCPHTTPServer.HTTPRequest) async -> MCPHTTPServer.HTTPResponse {
        guard let object = try? JSONSerialization.jsonObject(with: request.body) else {
            return jsonResponse(rpcError(id: nil, code: -32700, message: "Parse error"))
        }

        if let batch = object as? [[String: Any]] {
            var responses: [[String: Any]] = []
            for message in batch {
                if let response = await handleMessage(message) { responses.append(response) }
            }
            return responses.isEmpty
                ? MCPHTTPServer.HTTPResponse(status: 202, headers: [:], body: Data())
                : jsonResponse(responses)
        }

        if let message = object as? [String: Any] {
            if let response = await handleMessage(message) { return jsonResponse(response) }
            return MCPHTTPServer.HTTPResponse(status: 202, headers: [:], body: Data())
        }

        return jsonResponse(rpcError(id: nil, code: -32600, message: "Invalid Request"))
    }

    // MARK: - JSON-RPC dispatch

    /// Returns the JSON-RPC response object, or nil for notifications (no `id`).
    private func handleMessage(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : rpcError(id: id, code: -32600, message: "Missing method")
        }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return rpcResult(id: id, result: initializeResult(params))
        case "ping":
            return rpcResult(id: id, result: [:])
        case "tools/list":
            // Hide tools whose capability the user switched off.
            let tools = Self.toolSchemas().filter { tool in
                guard let name = tool["name"] as? String else { return false }
                return MCPCapability.allows(toolNamed: name)
            }
            return rpcResult(id: id, result: ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return rpcResult(id: id, result: await callTool(name: name, args: args))
        case let m where m.hasPrefix("notifications/"):
            return nil   // notifications get no response
        default:
            return id == nil ? nil : rpcError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(_ params: [String: Any]) -> [String: Any] {
        // Echo the client's protocol version so strict clients accept the handshake.
        let proto = params["protocolVersion"] as? String ?? "2024-11-05"
        return [
            "protocolVersion": proto,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "manather", "version": appVersion]
        ]
    }

    // MARK: - Tool dispatch

    private func callTool(name: String, args: [String: Any]) async -> [String: Any] {
        // Safety net in case a client cached a tool list from before the user
        // disabled its capability.
        guard MCPCapability.allows(toolNamed: name) else {
            return errorResult("The \"\(MCPCapability.forTool(name).title)\" capability is turned off in Manather (Settings → MCP Server).")
        }
        do {
            switch name {
            case "list_libraries":
                return ok(service.listLibraries())

            case "list_collections":
                return ok(service.listCollections(libraryID: uuid(args, "libraryId")))

            case "search_assets":
                return ok(service.searchAssets(
                    query: string(args, "query"),
                    type: string(args, "type"),
                    tags: stringArray(args, "tags"),
                    color: string(args, "color"),
                    collection: string(args, "collection"),
                    libraryID: uuid(args, "libraryId"),
                    limit: int(args, "limit") ?? 50))

            case "get_asset":
                return ok(try service.getAsset(id: requireString(args, "id")))

            case "create_library":
                return ok(service.createLibrary(name: try requireString(args, "name"),
                                                activate: bool(args, "activate") ?? false))

            case "create_collection":
                return ok(try service.createCollection(name: try requireString(args, "name"),
                                                       libraryID: uuid(args, "libraryId")))

            case "add_image":
                return ok(try await service.addImage(try imageSource(args),
                    title: string(args, "title"),
                    collection: string(args, "collection"),
                    prompt: string(args, "prompt") ?? "",
                    tags: stringArray(args, "tags"),
                    libraryID: uuid(args, "libraryId")))

            case "add_snippet":
                return ok(try service.addSnippet(
                    content: try requireString(args, "content"),
                    language: string(args, "language"),
                    title: string(args, "title"),
                    collection: string(args, "collection"),
                    prompt: string(args, "prompt") ?? "",
                    notes: string(args, "notes") ?? "",
                    tags: stringArray(args, "tags"),
                    libraryID: uuid(args, "libraryId")))

            case "add_web_link":
                return ok(try await service.addWebLink(
                    urlString: try requireString(args, "url"),
                    title: string(args, "title"),
                    collection: string(args, "collection"),
                    notes: string(args, "notes") ?? "",
                    tags: stringArray(args, "tags"),
                    libraryID: uuid(args, "libraryId")))

            case "add_skill":
                return ok(try service.addSkill(
                    markdown: try requireString(args, "markdown"),
                    title: string(args, "title"),
                    collection: string(args, "collection"),
                    notes: string(args, "notes") ?? "",
                    tags: stringArray(args, "tags"),
                    libraryID: uuid(args, "libraryId")))

            case "add_mcp_server":
                return ok(try service.addMCPServer(
                    name: try requireString(args, "name"),
                    command: string(args, "command") ?? "",
                    configJSON: string(args, "configJson") ?? "",
                    notes: string(args, "notes") ?? "",
                    collection: string(args, "collection"),
                    libraryID: uuid(args, "libraryId")))

            case "add_to_collection":
                return ok(try service.addToCollection(assetID: try requireString(args, "assetId"),
                                                      collection: try requireString(args, "collection")))

            case "remove_from_collection":
                return ok(try service.removeFromCollection(assetID: try requireString(args, "assetId"),
                                                           collection: try requireString(args, "collection")))

            case "set_tags":
                return ok(try service.setTags(assetID: try requireString(args, "assetId"),
                                              tags: stringArray(args, "tags")))

            case "set_prompt":
                return ok(try service.setPrompt(assetID: try requireString(args, "assetId"),
                                                prompt: try requireString(args, "prompt")))

            case "export_context_pack":
                return ok(try service.exportContextPack(
                    collection: try requireString(args, "collection"),
                    format: string(args, "format") ?? "generic",
                    goal: string(args, "goal") ?? "",
                    destinationPath: string(args, "destinationPath"),
                    libraryID: uuid(args, "libraryId")))

            default:
                return errorResult("Unknown tool: \(name)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Result builders

    private func ok<T: Encodable>(_ value: T) -> [String: Any] {
        let text = (try? jsonEncoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return ["content": [["type": "text", "text": text]]]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"]], "isError": true]
    }

    private func rpcResult(id: Any?, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func rpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func jsonResponse(_ object: Any) -> MCPHTTPServer.HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return .json(data)
    }

    // MARK: - Argument helpers

    private func string(_ args: [String: Any], _ key: String) -> String? {
        (args[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func requireString(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else {
            throw MCPServiceError.badInput("Missing required argument: \(key)")
        }
        return value
    }

    private func stringArray(_ args: [String: Any], _ key: String) -> [String] {
        (args[key] as? [String]) ?? []
    }

    private func int(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        return nil
    }

    private func bool(_ args: [String: Any], _ key: String) -> Bool? {
        args[key] as? Bool
    }

    private func uuid(_ args: [String: Any], _ key: String) -> UUID? {
        (args[key] as? String).flatMap { UUID(uuidString: $0) }
    }

    private func imageSource(_ args: [String: Any]) throws -> MCPImageSource {
        if let urlString = string(args, "url"), let url = URL(string: urlString) {
            return .remoteURL(url)
        }
        if let b64 = string(args, "base64"), let data = Data(base64Encoded: b64) {
            return .base64(data, ext: string(args, "ext") ?? "png")
        }
        if let path = string(args, "path") {
            return .localPath(path)
        }
        throw MCPServiceError.badInput("Provide one of: url, path, or base64.")
    }

    // MARK: - Tool schemas (tools/list)

    static func toolSchemas() -> [[String: Any]] {
        func p(_ type: String, _ description: String) -> [String: Any] {
            ["type": type, "description": description]
        }
        func arr(_ description: String) -> [String: Any] {
            ["type": "array", "items": ["type": "string"], "description": description]
        }
        func tool(_ name: String, _ description: String,
                  _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return ["name": name, "description": description, "inputSchema": schema]
        }

        let libraryId = p("string", "Library id to target. Defaults to the active library.")
        let collection = p("string", "Collection name to file the asset under (created if missing).")
        let tags = arr("Tags to attach.")

        return [
            tool("list_libraries",
                 "List all libraries (workspaces) with asset and collection counts."),

            tool("list_collections",
                 "List collections in a library.",
                 ["libraryId": libraryId]),

            tool("search_assets",
                 "Search assets by text and filters. Returns metadata incl. absolute filePath for media. Use this to find images, snippets, skills, MCP configs or links already in the library.",
                 ["query": p("string", "Free text matched against title, prompt, notes, tags and code."),
                  "type": p("string", "Filter by type: image, gif, video, webLink, codeSnippet, mcpServer, skill."),
                  "tags": arr("Match assets having any of these tags."),
                  "color": p("string", "Filter by dominant color: red, orange, yellow, green, blue, purple, pink."),
                  "collection": p("string", "Limit to a collection name."),
                  "libraryId": libraryId,
                  "limit": p("integer", "Max results (default 50).")]),

            tool("get_asset",
                 "Get full details for one asset by id, including absolute filePath (media) and full text content (snippet/skill/MCP).",
                 ["id": p("string", "Asset id (UUID).")], required: ["id"]),

            tool("create_library",
                 "Create a new library (workspace).",
                 ["name": p("string", "Library name."),
                  "activate": p("boolean", "Make it the active library (default false).")],
                 required: ["name"]),

            tool("create_collection",
                 "Create a collection (folder) in a library. Idempotent.",
                 ["name": p("string", "Collection name."), "libraryId": libraryId],
                 required: ["name"]),

            tool("add_image",
                 "Add an image to the library from a URL, a local file path, or base64 bytes. Provide exactly one source.",
                 ["url": p("string", "http(s) image URL to download."),
                  "path": p("string", "Absolute local file path to copy in."),
                  "base64": p("string", "Base64-encoded image bytes."),
                  "ext": p("string", "File extension for base64 input (e.g. png, jpg). Default png."),
                  "title": p("string", "Title (defaults to the file/url name)."),
                  "collection": collection,
                  "prompt": p("string", "Image/generation prompt to store on the asset."),
                  "tags": tags,
                  "libraryId": libraryId]),

            tool("add_snippet",
                 "Add a code snippet.",
                 ["content": p("string", "The code/text."),
                  "language": p("string", "Language label (e.g. Swift, TypeScript)."),
                  "title": p("string", "Title (defaults to first line)."),
                  "collection": collection,
                  "prompt": p("string", "Optional prompt to store."),
                  "notes": p("string", "Optional notes."),
                  "tags": tags,
                  "libraryId": libraryId],
                 required: ["content"]),

            tool("add_web_link",
                 "Add a web link (a page screenshot is generated automatically).",
                 ["url": p("string", "http(s) URL."),
                  "title": p("string", "Title (defaults to the page title)."),
                  "collection": collection,
                  "notes": p("string", "Optional notes."),
                  "tags": tags,
                  "libraryId": libraryId],
                 required: ["url"]),

            tool("add_skill",
                 "Add an AI agent skill (markdown).",
                 ["markdown": p("string", "Full SKILL.md markdown (optionally with YAML frontmatter)."),
                  "title": p("string", "Title (defaults to frontmatter name)."),
                  "collection": collection,
                  "notes": p("string", "Optional notes."),
                  "tags": tags,
                  "libraryId": libraryId],
                 required: ["markdown"]),

            tool("add_mcp_server",
                 "Add an MCP server config (launch command + optional JSON).",
                 ["name": p("string", "Server name."),
                  "command": p("string", "Launch command (e.g. npx -y @modelcontextprotocol/server-github)."),
                  "configJson": p("string", "Optional config JSON."),
                  "notes": p("string", "Optional notes."),
                  "collection": collection,
                  "libraryId": libraryId],
                 required: ["name"]),

            tool("add_to_collection",
                 "Add an existing asset to a collection (created if missing).",
                 ["assetId": p("string", "Asset id."), "collection": p("string", "Collection name.")],
                 required: ["assetId", "collection"]),

            tool("remove_from_collection",
                 "Remove an asset from a collection.",
                 ["assetId": p("string", "Asset id."), "collection": p("string", "Collection name.")],
                 required: ["assetId", "collection"]),

            tool("set_tags",
                 "Replace an asset's tags.",
                 ["assetId": p("string", "Asset id."), "tags": arr("New tag list.")],
                 required: ["assetId", "tags"]),

            tool("set_prompt",
                 "Set an asset's prompt text.",
                 ["assetId": p("string", "Asset id."), "prompt": p("string", "Prompt text.")],
                 required: ["assetId", "prompt"]),

            tool("export_context_pack",
                 "Export a collection as a ready-to-use context pack folder (CONTEXT.md + manifest.json + files). Returns the absolute folder path. Use this to hand a whole collection to an agent.",
                 ["collection": p("string", "Collection name to export."),
                  "format": ["type": "string", "enum": ["claude", "agents", "generic"],
                             "description": "Pack flavor: claude (Claude Code), agents (AGENTS.md), generic. Default generic."],
                  "goal": p("string", "Optional free-text project goal/brief."),
                  "destinationPath": p("string", "Parent directory for the pack (default ~/Downloads)."),
                  "libraryId": libraryId],
                 required: ["collection"]),
        ]
    }
}
