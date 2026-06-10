//
//  AnimatedGifView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import AppKit

struct AnimatedGifView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Only reload if the URL actually changed
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        // Load off main thread to prevent jank
        let targetURL = url
        DispatchQueue.global(qos: .utility).async {
            let image = NSImage(contentsOf: targetURL)
            DispatchQueue.main.async {
                // Verify URL hasn't changed during load
                if context.coordinator.loadedURL == targetURL {
                    nsView.image = image
                }
            }
        }
    }

    class Coordinator {
        var loadedURL: URL?
    }
}
