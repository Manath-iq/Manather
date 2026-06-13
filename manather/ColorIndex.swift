//
//  ColorIndex.swift
//  manather
//
//  7 base color buckets for palette filtering. Each asset's dominant colors
//  are classified by hue into buckets; the toolbar swatches filter by bucket.
//

import SwiftUI
import AppKit

// MARK: - Base Colors (filter swatches)

enum BaseColor: String, CaseIterable, Identifiable, Codable {
    case red, orange, yellow, green, blue, purple, pink

    var id: String { rawValue }

    /// Swatch color shown in the filter row
    var swatch: Color {
        switch self {
        case .red:    return Color(red: 0.91, green: 0.26, blue: 0.21)
        case .orange: return Color(red: 0.96, green: 0.55, blue: 0.14)
        case .yellow: return Color(red: 0.98, green: 0.80, blue: 0.18)
        case .green:  return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .blue:   return Color(red: 0.22, green: 0.51, blue: 0.92)
        case .purple: return Color(red: 0.58, green: 0.34, blue: 0.92)
        case .pink:   return Color(red: 0.93, green: 0.38, blue: 0.65)
        }
    }

    var label: String { rawValue.capitalized }

    /// Classify a hue (0–360) into a bucket. Caller must pre-filter grays.
    static func bucket(forHue hue: Double) -> BaseColor {
        switch hue {
        case ..<15:    return .red
        case ..<45:    return .orange
        case ..<70:    return .yellow
        case ..<170:   return .green
        case ..<260:   return .blue
        case ..<300:   return .purple
        case ..<345:   return .pink
        default:       return .red
        }
    }
}

// MARK: - Hex Classification

enum ColorIndex {

    /// Parse "#RRGGBB" → (r, g, b) in 0–1, or nil.
    static func parseHex(_ hexString: String) -> (r: Double, g: Double, b: Double)? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        return (
            Double((int >> 16) & 0xFF) / 255.0,
            Double((int >> 8) & 0xFF) / 255.0,
            Double(int & 0xFF) / 255.0
        )
    }

    /// RGB (0–1) → (hue 0–360, saturation 0–1, brightness 0–1)
    static func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue: Double = 0
        if delta > 0.0001 {
            if maxC == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = maxC > 0.0001 ? delta / maxC : 0
        return (hue, saturation, maxC)
    }

    /// Classify one hex color into a bucket; nil for grays / too dark / too light.
    static func bucket(forHex hex: String) -> BaseColor? {
        guard let rgb = parseHex(hex) else { return nil }
        let hsb = rgbToHSB(r: rgb.r, g: rgb.g, b: rgb.b)
        // Grays and extremes carry no hue information
        guard hsb.s >= 0.18, hsb.v >= 0.14, hsb.v <= 0.98 || hsb.s > 0.3 else { return nil }
        return BaseColor.bucket(forHue: hsb.h)
    }

    /// All buckets present in an asset's dominant palette.
    /// First colors in the palette are most frequent — weight them by requiring
    /// at least one of the top-4 to match for a "strong" classification.
    static func buckets(forHexes hexes: [String]) -> Set<BaseColor> {
        var result = Set<BaseColor>()
        for hex in hexes.prefix(5) {
            if let bucket = bucket(forHex: hex) {
                result.insert(bucket)
            }
        }
        return result
    }
}

// MARK: - Background Color Indexer

/// Extracts dominant colors for assets that don't have them yet (backfill +
/// at-import). Serial queue so we never decode many images at once.
@MainActor
final class ColorIndexer {
    static let shared = ColorIndexer()

    private var inFlight = Set<UUID>()

    /// Extract and persist dominant colors for one asset (no-op if present).
    func ensureColors(for asset: AssetItem) {
        guard asset.dominantColorsHex == nil || asset.dominantColorsHex?.isEmpty == true,
              !asset.relativeFilePath.isEmpty,
              asset.assetType == .image || asset.assetType == .gif || asset.assetType == .video,
              !inFlight.contains(asset.id)
        else { return }

        inFlight.insert(asset.id)
        let path = asset.relativeFilePath
        let id = asset.id

        Task {
            // Small thumbnail is plenty for palette extraction (decoded off-main by ImageCache)
            guard let thumb = await ImageCache.shared.thumbnail(for: path, maxSize: 200) else {
                inFlight.remove(id)
                return
            }

            // 40×40 sample extraction is a few ms — fine on main; yield to stay responsive
            await Task.yield()
            let nsColors = DominantColorExtractor.extractColors(from: thumb, count: 8)
            let hexes = nsColors.map { color -> String in
                guard let rgb = color.usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
                return String(
                    format: "#%02X%02X%02X",
                    Int(rgb.redComponent * 255),
                    Int(rgb.greenComponent * 255),
                    Int(rgb.blueComponent * 255)
                )
            }

            if !hexes.isEmpty {
                asset.dominantColorsHex = hexes
            }
            inFlight.remove(id)
        }
    }

    /// Backfill colors for a batch of assets missing them.
    func backfill(assets: [AssetItem]) {
        for asset in assets where asset.dominantColorsHex == nil || asset.dominantColorsHex?.isEmpty == true {
            ensureColors(for: asset)
        }
    }
}
