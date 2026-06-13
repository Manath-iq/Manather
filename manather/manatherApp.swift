//
//  manatherApp.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import SwiftData

@main
struct manatherApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AssetItem.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [modelConfiguration])
        }

        do {
            return try makeContainer()
        } catch {
            // The on-disk database couldn't be opened — usually because the data
            // model changed since it was last written, or the store got corrupted.
            // Instead of crashing on every launch (which would lock the user out
            // of the app entirely), move the old store aside and start fresh.
            print("ModelContainer failed to open (\(error)). Resetting local store.")
            manatherApp.resetStore(for: modelConfiguration)

            do {
                return try makeContainer()
            } catch {
                // Last resort: keep the app usable this session with an in-memory store.
                print("Reset did not help (\(error)). Falling back to in-memory store.")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memoryConfig])
            }
        }
    }()

    /// Deletes the SwiftData store files so a fresh, compatible store can be created.
    private static func resetStore(for configuration: ModelConfiguration) {
        let storeURL = configuration.url
        let fileManager = FileManager.default
        // SwiftData/SQLite keeps companion files alongside the main store.
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? fileManager.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1100, height: 700)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }
    }
}
