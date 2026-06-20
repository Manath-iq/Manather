//
//  MCPLibraryService.swift
//  manather
//
//  The "core" of the MCP server: every library operation an agent can perform,
//  expressed as plain Swift methods on the app's own ModelContext. It knows
//  nothing about networking or the MCP protocol — the HTTP/MCP layers on top just
//  translate requests into calls here.
//
//  Because every write goes through `container.mainContext` (the same context the
//  UI's @Query observes), the grid updates live the moment an agent adds or
//  changes something — no relaunch, no fighting SwiftData from the outside.
//
//  Reuses the existing ingest/export plumbing (FileManagerHelper, ColorIndexer,
//  WebsiteScreenshotManager, ContextPackExporter) so assets created by an agent
//  behave identically to ones added by hand.
//

import Foundation
import SwiftData

// MARK: - Errors

enum MCPServiceError: LocalizedError {
    case assetNotFound(String)
    case badInput(String)
    case fileNotFound(String)
    case downloadFailed(String)
    case writeFailed(String)
    case collectionEmpty(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let id):     return "No asset with id \(id)."
        case .badInput(let msg):         return msg
        case .fileNotFound(let path):    return "File not found: \(path)."
        case .downloadFailed(let url):   return "Couldn't download \(url)."
        case .writeFailed(let msg):      return "Couldn't save: \(msg)."
        case .collectionEmpty(let name): return "Collection \"\(name)\" has no assets to export."
        }
    }
}

// MARK: - DTOs (what the MCP tools return)

/// A library, with quick counts.
struct MCPLibraryDTO: Codable {
    let id: String
    let name: String
    let dateCreated: String
    let isActive: Bool
    let assetCount: Int
    let collectionCount: Int
}

/// A collection (folder) within a library.
struct MCPCollectionDTO: Codable {
    let id: String
    let name: String
    let libraryID: String
    let assetCount: Int
}

/// One asset. `filePath` is the absolute path on disk for media (so a local agent
/// can read the bytes itself); `codeContent` carries full text for snippet / skill
/// / MCP-server assets and is only filled in when `detailed` is requested.
struct MCPAssetDTO: Codable {
    let id: String
    let title: String
    let type: String
    let prompt: String
    let notes: String
    let tags: [String]
    let sourceURL: String
    let collections: [String]
    let dominantColors: [String]
    let width: Int
    let height: Int
    let codeLanguage: String?
    let dateAdded: String
    let filePath: String?
    let codePreview: String?
    let codeContent: String?
}

/// Result of an export.
struct MCPExportResultDTO: Codable {
    let path: String
    let assetCount: Int
    let format: String
}

// MARK: - Image source for add_image

enum MCPImageSource {
    case remoteURL(URL)
    case localPath(String)
    case base64(Data, ext: String)
}

// MARK: - Service

@MainActor
final class MCPLibraryService {
    let container: ModelContainer
    private var ctx: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    private let iso = ISO8601DateFormatter()
    private static let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
    private static let videoExtensions = ["mp4", "mov", "m4v", "avi"]

    // MARK: - Read

    func listLibraries() -> [MCPLibraryDTO] {
        let libs = (try? ctx.fetch(FetchDescriptor<Library>())) ?? []
        let allAssets = (try? ctx.fetch(FetchDescriptor<AssetItem>())) ?? []
        let allCollections = (try? ctx.fetch(FetchDescriptor<AssetCollection>())) ?? []
        let active = LibraryManager.activeLibraryID
        return libs.sorted { $0.dateCreated < $1.dateCreated }.map { lib in
            MCPLibraryDTO(
                id: lib.id.uuidString,
                name: lib.name,
                dateCreated: iso.string(from: lib.dateCreated),
                isActive: lib.id == active,
                assetCount: allAssets.filter { $0.libraryID == lib.id && !$0.isDeleted && !$0.isTrash }.count,
                collectionCount: allCollections.filter { $0.libraryID == lib.id }.count
            )
        }
    }

    func listCollections(libraryID requested: UUID?) -> [MCPCollectionDTO] {
        let libraryID = resolveLibraryID(requested)
        let collections = ((try? ctx.fetch(FetchDescriptor<AssetCollection>())) ?? [])
            .filter { $0.libraryID == libraryID }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        let assets = assets(inLibrary: libraryID)
        return collections.map { col in
            MCPCollectionDTO(
                id: col.id.uuidString,
                name: col.name,
                libraryID: libraryID.uuidString,
                assetCount: assets.filter { $0.inCollection(col.name) }.count
            )
        }
    }

    /// Full-text + filter search. All filters are optional and combine with AND.
    func searchAssets(query: String?, type: String?, tags: [String], color: String?,
                      collection: String?, libraryID requested: UUID?, limit: Int) -> [MCPAssetDTO] {
        let libraryID = resolveLibraryID(requested)
        var results = assets(inLibrary: libraryID)

        if let type, !type.isEmpty {
            results = results.filter { $0.typeRaw.caseInsensitiveCompare(type) == .orderedSame }
        }
        if let collection, !collection.isEmpty {
            results = results.filter { $0.inCollection(collection) }
        }
        if !tags.isEmpty {
            let wanted = Set(tags.map { $0.lowercased() })
            results = results.filter { asset in
                let assetTags = Set(asset.tags.map { $0.lowercased() })
                return !wanted.isDisjoint(with: assetTags)
            }
        }
        if let color, let bucket = BaseColor(rawValue: color.lowercased()) {
            results = results.filter {
                ColorIndex.buckets(forHexes: $0.dominantColorsHex ?? []).contains(bucket)
            }
        }
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = query.lowercased()
            results = results.filter { asset in
                asset.title.lowercased().contains(q)
                    || asset.prompt.lowercased().contains(q)
                    || asset.notes.lowercased().contains(q)
                    || asset.tags.contains { $0.lowercased().contains(q) }
                    || (asset.codeContent?.lowercased().contains(q) ?? false)
            }
        }

        return results
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(max(0, limit))
            .map { dto($0, detailed: false) }
    }

    func getAsset(id: String) throws -> MCPAssetDTO {
        guard let asset = findAsset(id) else { throw MCPServiceError.assetNotFound(id) }
        return dto(asset, detailed: true)
    }

    // MARK: - Create libraries / collections

    func createLibrary(name: String, activate: Bool) -> MCPLibraryDTO {
        let unique = LibraryManager.uniqueName(name, context: ctx)
        let lib = Library(name: unique)
        ctx.insert(lib)
        if activate { LibraryManager.setActive(lib.id) }
        save()
        return MCPLibraryDTO(
            id: lib.id.uuidString, name: lib.name,
            dateCreated: iso.string(from: lib.dateCreated),
            isActive: LibraryManager.activeLibraryID == lib.id,
            assetCount: 0, collectionCount: 0
        )
    }

    /// Idempotent — returns the existing collection if one with this name already
    /// exists in the library.
    func createCollection(name: String, libraryID requested: UUID?) throws -> MCPCollectionDTO {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPServiceError.badInput("Collection name is empty.") }
        let libraryID = resolveLibraryID(requested)
        let col = ensureCollection(trimmed, libraryID: libraryID)
        save()
        let count = assets(inLibrary: libraryID).filter { $0.inCollection(col.name) }.count
        return MCPCollectionDTO(id: col.id.uuidString, name: col.name,
                                libraryID: libraryID.uuidString, assetCount: count)
    }

    // MARK: - Add assets

    func addImage(_ source: MCPImageSource, title: String?, collection: String?,
                  prompt: String, tags: [String], libraryID requested: UUID?) async throws -> MCPAssetDTO {
        let libraryID = resolveLibraryID(requested)

        let relativePath: String
        let resolvedTitle: String

        switch source {
        case .remoteURL(let url):
            let (data, ext) = try await download(url)
            let base = title ?? url.deletingPathExtension().lastPathComponent
            resolvedTitle = base.isEmpty ? "Image" : base
            guard let saved = FileManagerHelper.saveImageData(data, baseName: resolvedTitle, ext: ext) else {
                throw MCPServiceError.writeFailed("image bytes")
            }
            relativePath = saved

        case .localPath(let path):
            let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw MCPServiceError.fileNotFound(path)
            }
            guard let copied = FileManagerHelper.copyFileToSandbox(from: fileURL) else {
                throw MCPServiceError.writeFailed(path)
            }
            relativePath = copied
            resolvedTitle = title ?? fileURL.deletingPathExtension().lastPathComponent

        case .base64(let data, let ext):
            let base = title ?? "Image"
            resolvedTitle = base
            guard let saved = FileManagerHelper.saveImageData(data, baseName: base, ext: ext) else {
                throw MCPServiceError.writeFailed("image bytes")
            }
            relativePath = saved
        }

        let dims = await FileManagerHelper.imageDimensions(relativePath: relativePath)
        let ext = (relativePath as NSString).pathExtension.lowercased()
        let typeRaw = typeRaw(forExtension: ext)

        let asset = AssetItem(
            title: resolvedTitle,
            relativeFilePath: relativePath,
            prompt: prompt,
            imageWidth: dims?.width ?? 0,
            imageHeight: dims?.height ?? 0,
            typeRaw: typeRaw,
            collectionNames: normalizedCollections(collection, libraryID: libraryID),
            libraryID: libraryID,
            tags: tags
        )
        ctx.insert(asset)
        ColorIndexer.shared.ensureColors(for: asset)
        save()
        return dto(asset, detailed: true)
    }

    func addSnippet(content: String, language: String?, title: String?, collection: String?,
                    prompt: String, notes: String, tags: [String],
                    libraryID requested: UUID?) throws -> MCPAssetDTO {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPServiceError.badInput("Snippet content is empty.") }
        let libraryID = resolveLibraryID(requested)
        let resolvedTitle = title ?? String((trimmed.split(separator: "\n").first.map(String.init) ?? "Snippet").prefix(48))

        let asset = AssetItem(
            title: resolvedTitle,
            relativeFilePath: "",
            prompt: prompt,
            notes: notes,
            typeRaw: "codeSnippet",
            codeLanguage: language ?? "Text",
            codeContent: content,
            collectionNames: normalizedCollections(collection, libraryID: libraryID),
            libraryID: libraryID,
            tags: tags
        )
        ctx.insert(asset)
        save()
        return dto(asset, detailed: true)
    }

    func addWebLink(urlString: String, title: String?, collection: String?,
                    notes: String, tags: [String], libraryID requested: UUID?) async throws -> MCPAssetDTO {
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            throw MCPServiceError.badInput("Not a valid http(s) URL: \(urlString)")
        }
        let libraryID = resolveLibraryID(requested)

        var pageTitle = title ?? (url.host ?? "Web Link")
        if title == nil {
            if let fetched = try? await fetchPageTitle(url) { pageTitle = fetched }
        }

        let asset = AssetItem(
            title: pageTitle,
            relativeFilePath: "",
            sourceURL: url.absoluteString,
            notes: notes,
            typeRaw: "webLink",
            collectionNames: normalizedCollections(collection, libraryID: libraryID),
            libraryID: libraryID,
            tags: tags
        )
        ctx.insert(asset)
        WebsiteScreenshotManager.shared.generateScreenshot(for: asset, in: ctx)
        save()
        return dto(asset, detailed: true)
    }

    func addSkill(markdown: String, title: String?, collection: String?,
                  notes: String, tags: [String], libraryID requested: UUID?) throws -> MCPAssetDTO {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPServiceError.badInput("Skill content is empty.") }
        let libraryID = resolveLibraryID(requested)
        let resolvedTitle = title ?? frontmatterName(markdown) ?? "Untitled Skill"

        let asset = AssetItem(
            title: resolvedTitle,
            relativeFilePath: "",
            notes: notes,
            typeRaw: "skill",
            codeLanguage: "Markdown",
            codeContent: markdown,
            collectionNames: normalizedCollections(collection, libraryID: libraryID),
            libraryID: libraryID,
            tags: tags
        )
        ctx.insert(asset)
        save()
        return dto(asset, detailed: true)
    }

    func addMCPServer(name: String, command: String, configJSON: String, notes: String,
                      collection: String?, libraryID requested: UUID?) throws -> MCPAssetDTO {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPServiceError.badInput("MCP server name is empty.") }
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty
                || !configJSON.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MCPServiceError.badInput("Provide a launch command or a config JSON.")
        }
        let libraryID = resolveLibraryID(requested)

        let asset = AssetItem(
            title: trimmed,
            relativeFilePath: "",
            notes: notes,
            typeRaw: "mcpServer",
            codeLanguage: command,
            codeContent: configJSON,
            collectionNames: normalizedCollections(collection, libraryID: libraryID),
            libraryID: libraryID,
            tags: []
        )
        ctx.insert(asset)
        save()
        return dto(asset, detailed: true)
    }

    // MARK: - Edit assets

    func addToCollection(assetID: String, collection: String) throws -> MCPAssetDTO {
        guard let asset = findAsset(assetID) else { throw MCPServiceError.assetNotFound(assetID) }
        let name = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPServiceError.badInput("Collection name is empty.") }
        ensureCollection(name, libraryID: asset.libraryID ?? resolveLibraryID(nil))
        asset.addToCollection(name)
        save()
        return dto(asset, detailed: true)
    }

    func removeFromCollection(assetID: String, collection: String) throws -> MCPAssetDTO {
        guard let asset = findAsset(assetID) else { throw MCPServiceError.assetNotFound(assetID) }
        asset.removeFromCollection(collection.trimmingCharacters(in: .whitespacesAndNewlines))
        save()
        return dto(asset, detailed: true)
    }

    func setTags(assetID: String, tags: [String]) throws -> MCPAssetDTO {
        guard let asset = findAsset(assetID) else { throw MCPServiceError.assetNotFound(assetID) }
        var seen = Set<String>()
        asset.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        save()
        return dto(asset, detailed: true)
    }

    func setPrompt(assetID: String, prompt: String) throws -> MCPAssetDTO {
        guard let asset = findAsset(assetID) else { throw MCPServiceError.assetNotFound(assetID) }
        asset.prompt = prompt
        save()
        return dto(asset, detailed: true)
    }

    // MARK: - Export

    func exportContextPack(collection: String, format: String, goal: String,
                           destinationPath: String?, libraryID requested: UUID?) throws -> MCPExportResultDTO {
        let name = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPServiceError.badInput("Collection name is empty.") }
        let libraryID = resolveLibraryID(requested)
        let packAssets = assets(inLibrary: libraryID).filter { $0.inCollection(name) }
        guard !packAssets.isEmpty else { throw MCPServiceError.collectionEmpty(name) }

        let target = exportTarget(for: format)
        let folderName = sanitize(name) + target.folderSuffix

        let parent: URL
        if let destinationPath, !destinationPath.isEmpty {
            parent = URL(fileURLWithPath: (destinationPath as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            parent = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        }
        let root = uniqueDirectory(in: parent, base: folderName)

        do {
            try ContextPackExporter.writePack(to: root, projectName: name,
                                              assets: packAssets, target: target, goal: goal)
        } catch {
            throw MCPServiceError.writeFailed(error.localizedDescription)
        }
        return MCPExportResultDTO(path: root.path, assetCount: packAssets.count, format: target.rawValue)
    }

    // MARK: - Helpers

    private func resolveLibraryID(_ requested: UUID?) -> UUID {
        if let requested { return requested }
        if let active = LibraryManager.activeLibraryID { return active }
        let libs = (try? ctx.fetch(FetchDescriptor<Library>())) ?? []
        if let first = libs.sorted(by: { $0.dateCreated < $1.dateCreated }).first { return first.id }
        let lib = Library(name: "My Library")
        ctx.insert(lib)
        LibraryManager.setActive(lib.id)
        return lib.id
    }

    @discardableResult
    private func ensureCollection(_ name: String, libraryID: UUID) -> AssetCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = ((try? ctx.fetch(FetchDescriptor<AssetCollection>())) ?? [])
            .first { $0.libraryID == libraryID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        if let existing { return existing }
        let col = AssetCollection(name: trimmed, libraryID: libraryID)
        ctx.insert(col)
        return col
    }

    /// Ensures the named collection exists and returns the list to seed an asset with.
    private func normalizedCollections(_ collection: String?, libraryID: UUID) -> [String] {
        guard let collection else { return [] }
        let trimmed = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        ensureCollection(trimmed, libraryID: libraryID)
        return [trimmed]
    }

    private func assets(inLibrary libraryID: UUID, includeTrash: Bool = false) -> [AssetItem] {
        ((try? ctx.fetch(FetchDescriptor<AssetItem>())) ?? [])
            .filter { $0.libraryID == libraryID && !$0.isDeleted && (includeTrash || !$0.isTrash) }
    }

    private func findAsset(_ id: String) -> AssetItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<AssetItem>())) ?? [])
            .first { $0.id == uuid && !$0.isDeleted }
    }

    private func save() { try? ctx.save() }

    private func dto(_ asset: AssetItem, detailed: Bool) -> MCPAssetDTO {
        var filePath: String? = nil
        if !asset.relativeFilePath.isEmpty {
            let url = FileManagerHelper.absolutePath(for: asset.relativeFilePath)
            if FileManager.default.fileExists(atPath: url.path) { filePath = url.path }
        }

        let textTypes: Set<String> = ["codeSnippet", "skill", "mcpServer"]
        let hasText = textTypes.contains(asset.typeRaw)
        let preview = hasText ? asset.codeContent.map { String($0.prefix(280)) } : nil
        let fullText = (detailed && hasText) ? asset.codeContent : nil

        return MCPAssetDTO(
            id: asset.id.uuidString,
            title: asset.title,
            type: asset.typeRaw,
            prompt: asset.prompt,
            notes: asset.notes,
            tags: asset.tags,
            sourceURL: asset.sourceURL,
            collections: asset.collectionNames,
            dominantColors: asset.dominantColorsHex ?? [],
            width: Int(asset.imageWidth),
            height: Int(asset.imageHeight),
            codeLanguage: asset.codeLanguage,
            dateAdded: iso.string(from: asset.dateAdded),
            filePath: filePath,
            codePreview: detailed ? nil : preview,
            codeContent: fullText
        )
    }

    private func typeRaw(forExtension ext: String) -> String {
        if Self.videoExtensions.contains(ext) { return "video" }
        if ext == "gif" { return "gif" }
        return "image"
    }

    private func exportTarget(for format: String) -> ExportTarget {
        switch format.lowercased().replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: ".", with: "") {
        case "claude", "claudecode": return .claudeCode
        case "agents", "agentsmd":   return .agentsMD
        default:                     return .generic
        }
    }

    // MARK: - Networking helpers

    private func download(_ url: URL) async throws -> (Data, String) {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw MCPServiceError.badInput("Image URL must be http(s): \(url.absoluteString)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), !data.isEmpty else {
            throw MCPServiceError.downloadFailed(url.absoluteString)
        }
        return (data, imageExtension(url: url, response: response) ?? "png")
    }

    private func imageExtension(url: URL, response: URLResponse) -> String? {
        let pathExt = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(pathExt) { return pathExt == "jpeg" ? "jpg" : pathExt }
        if let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if mime.contains("png") { return "png" }
            if mime.contains("jpeg") || mime.contains("jpg") { return "jpg" }
            if mime.contains("gif") { return "gif" }
            if mime.contains("webp") { return "webp" }
            if mime.contains("heic") { return "heic" }
        }
        return nil
    }

    private func fetchPageTitle(_ url: URL) async throws -> String? {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: "<title>([^<]+)</title>",
                                     options: [.regularExpression, .caseInsensitive]) else { return nil }
        let clean = html[range]
            .replacingOccurrences(of: "<title>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// Reads `name:` out of a leading `--- … ---` YAML frontmatter block, if any.
    private func frontmatterName(_ markdown: String) -> String? {
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

    // MARK: - Filesystem helpers

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.lowercased().replacingOccurrences(of: " ", with: "-")
            .unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(mapped))
        return result.isEmpty ? "untitled" : result
    }

    /// A folder URL under `parent` that doesn't exist yet (appends -2, -3, …).
    private func uniqueDirectory(in parent: URL, base: String) -> URL {
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}
