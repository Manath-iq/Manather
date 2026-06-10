//
//  MicroAnimationButtonStyle.swift
//  manather
//
//  Created by Максим on 6/5/26.
//

import SwiftUI

struct MicroAnimationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MicroAnimationButtonStyle {
    static var microAnimated: MicroAnimationButtonStyle {
        MicroAnimationButtonStyle()
    }
}
