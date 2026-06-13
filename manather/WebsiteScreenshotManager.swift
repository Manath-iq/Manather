//
//  WebsiteScreenshotManager.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import Foundation
import WebKit
import SwiftData
import AppKit

@MainActor
final class WebsiteScreenshotManager {
    static let shared = WebsiteScreenshotManager()
    
    private var activeTasks: [UUID: ScreenshotTask] = [:]
    private var pendingAssets: [(UUID, URL, ModelContext)] = []
    private let maxConcurrent = 2 // Limit WKWebViews to prevent memory spikes
    
    private init() {}
    
    func generateScreenshot(for asset: AssetItem, in context: ModelContext) {
        guard asset.assetType == .webLink else { return }
        // Only generate if we don't have a relativeFilePath yet
        guard asset.relativeFilePath.isEmpty else { return }
        guard let url = URL(string: asset.sourceURL) else { return }
        
        let assetID = asset.id
        
        // Check if there is already an active task for this asset
        if activeTasks[assetID] != nil {
            return
        }
        
        // Check if the asset is already in the pending queue
        if pendingAssets.contains(where: { $0.0 == assetID }) {
            return
        }
        
        // Queue if at capacity
        if activeTasks.count >= maxConcurrent {
            pendingAssets.append((assetID, url, context))
            return
        }
        
        startTask(for: assetID, url: url, in: context)
    }
    
    private func startTask(for assetID: UUID, url: URL, in context: ModelContext) {
        let task = ScreenshotTask(url: url, assetID: assetID) { [weak self] nsImage in
            guard let self = self else { return }
            self.activeTasks.removeValue(forKey: assetID)
            
            // Process next pending task
            self.processPending()
            
            guard let nsImage = nsImage else { return }
            
            // Save image to sandbox
            let filename = "web_\(assetID.uuidString).jpg"
            let destinationURL = FileManagerHelper.assetsDirectory.appendingPathComponent(filename)
            
            let size = nsImage.size
            let tiffData = nsImage.tiffRepresentation
            
            Task.detached {
                if let tiffData = tiffData,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                    do {
                        try jpegData.write(to: destinationURL)
                        
                        await MainActor.run {
                            let descriptor = FetchDescriptor<AssetItem>(predicate: #Predicate { $0.id == assetID })
                            if let fetchedAsset = try? context.fetch(descriptor).first {
                                fetchedAsset.relativeFilePath = filename
                                fetchedAsset.imageWidth = Double(size.width)
                                fetchedAsset.imageHeight = Double(size.height)
                                try? context.save()
                            }
                        }
                    } catch {
                        // Silently fail
                    }
                }
            }
        }
        
        activeTasks[assetID] = task
        task.start()
    }
    
    private func processPending() {
        while activeTasks.count < maxConcurrent, !pendingAssets.isEmpty {
            let (assetID, url, context) = pendingAssets.removeFirst()
            // Verify asset still exists and doesn't have a path
            let descriptor = FetchDescriptor<AssetItem>(predicate: #Predicate { $0.id == assetID })
            if let asset = try? context.fetch(descriptor).first, asset.relativeFilePath.isEmpty {
                startTask(for: assetID, url: url, in: context)
            }
        }
    }
}

@MainActor
private final class ScreenshotTask: NSObject, WKNavigationDelegate {
    let url: URL
    let assetID: UUID
    let completion: (NSImage?) -> Void
    
    private var webView: WKWebView?
    private var timeoutWorkItem: DispatchWorkItem?
    private var hasFinished = false
    
    init(url: URL, assetID: UUID, completion: @escaping (NSImage?) -> Void) {
        self.url = url
        self.assetID = assetID
        self.completion = completion
    }
    
    func start() {
        let config = WKWebViewConfiguration()
        // Default size of 1280x800 for the snapshot rendering
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        
        // Timeout after 15 seconds
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !self.hasFinished {
                print("Screenshot timeout for: \(self.url)")
                self.finish(with: nil)
            }
        }
        self.timeoutWorkItem = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWork)
        
        webView.load(URLRequest(url: url))
    }
    
    private func finish(with image: NSImage?) {
        guard !hasFinished else { return }
        hasFinished = true
        
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        webView?.navigationDelegate = nil
        webView = nil
        completion(image)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait 1.5 seconds to make sure Javascript and CSS layout are fully loaded and settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let webView = self.webView, !self.hasFinished else { return }
            
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 1280, height: 800)
            
            webView.takeSnapshot(with: config) { image, error in
                if let error = error {
                    print("Error taking web view snapshot: \(error.localizedDescription)")
                    self.finish(with: nil)
                } else {
                    self.finish(with: image)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Web view load failed: \(error.localizedDescription)")
        finish(with: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Web view provisional load failed: \(error.localizedDescription)")
        finish(with: nil)
    }
}
