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

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

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
