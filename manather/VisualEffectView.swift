//
//  VisualEffectView.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    /// Force dark appearance — sheets use white text, so the blur must stay dark
    /// even when the system is in light mode.
    var forceDark: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        if forceDark {
            view.appearance = NSAppearance(named: .darkAqua)
        }
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.appearance = forceDark ? NSAppearance(named: .darkAqua) : nil
    }
}
