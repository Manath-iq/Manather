//
//  AssetCollection.swift
//  manather
//
//  A user-created collection.
//
//  Before, a collection only "existed" while at least one asset wore its name —
//  so you could never make an empty one, and there was no obvious way to create
//  one at all. This is a real, persistent object: an empty collection (one you
//  just made, before adding anything) sticks around, exactly like a folder in
//  Finder or an album in Photos.
//
//  Assets still point at a collection by its `name` (AssetItem.collectionName),
//  so all the existing grouping / filtering / export code keeps working unchanged.
//  Named AssetCollection (not Collection) to avoid clashing with Swift's built-in
//  Collection protocol.
//

import Foundation
import SwiftData

@Model
final class AssetCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateAdded: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateAdded = Date()
    }
}
