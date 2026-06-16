//
//  Library.swift
//  manather
//
//  A "library" is a top-level workspace: its own set of saved assets and
//  collections. The user can keep several (e.g. one per client or per topic),
//  switch between them from the "Library ▾" menu, and export/import a whole
//  library as a ZIP to share it (see LibraryArchive).
//
//  Assets and collections point at their library by id (AssetItem.libraryID /
//  AssetCollection.libraryID). Boards are intentionally NOT scoped to a library
//  — they stay global, shared across all libraries (owner decision, June 2026).
//

import Foundation
import SwiftData

@Model
final class Library {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
    }
}

/// Small helper around the "currently-active library" selection. The active id
/// lives in `UserDefaults` (mirrored by `@AppStorage("activeLibraryID")` in the
/// views), so even non-SwiftUI code — like `AssetItem.init` — can stamp newly
/// created content with the right library without threading the id through every
/// call site.
enum LibraryManager {
    static let activeKey = "activeLibraryID"

    /// The active library id, or nil before the first library has been seeded.
    static var activeLibraryID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: activeKey) else { return nil }
        return UUID(uuidString: raw)
    }

    /// Switch the active library. Updates `UserDefaults`, which `@AppStorage`
    /// observers pick up automatically to re-filter the UI.
    static func setActive(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
    }

    /// Guarantee there is at least one library and that the active selection is
    /// valid. On the very first run this creates a default library and adopts any
    /// pre-existing (library-less) assets and collections into it. Idempotent —
    /// safe to call on every launch.
    @MainActor
    @discardableResult
    static func ensureActive(context: ModelContext) -> Library {
        var libraries = (try? context.fetch(FetchDescriptor<Library>())) ?? []

        if libraries.isEmpty {
            let lib = Library(name: "My Library")
            context.insert(lib)
            adoptOrphans(into: lib, context: context)
            libraries = [lib]
        }

        let defaultLibrary = libraries.sorted { $0.dateCreated < $1.dateCreated }.first!

        let active = activeLibraryID
        if active == nil || !libraries.contains(where: { $0.id == active }) {
            setActive(defaultLibrary.id)
        }
        return defaultLibrary
    }

    /// Assign every asset and collection that has no library yet to `lib`.
    /// Runs once, when the first library is created.
    @MainActor
    static func adoptOrphans(into lib: Library, context: ModelContext) {
        let assets = (try? context.fetch(FetchDescriptor<AssetItem>())) ?? []
        for asset in assets where asset.libraryID == nil {
            asset.libraryID = lib.id
        }
        let collections = (try? context.fetch(FetchDescriptor<AssetCollection>())) ?? []
        for collection in collections where collection.libraryID == nil {
            collection.libraryID = lib.id
        }
    }

    /// A library name not already used (case-insensitive); appends " 2", " 3"…
    /// Used when importing so two imports of the same pack don't collide.
    @MainActor
    static func uniqueName(_ base: String, context: ModelContext) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = trimmed.isEmpty ? "Imported Library" : trimmed
        let existing = ((try? context.fetch(FetchDescriptor<Library>())) ?? []).map { $0.name.lowercased() }
        if !existing.contains(wanted.lowercased()) { return wanted }
        var n = 2
        while existing.contains("\(wanted) \(n)".lowercased()) { n += 1 }
        return "\(wanted) \(n)"
    }
}
