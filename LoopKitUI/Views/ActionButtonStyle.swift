//
//  ActionButtonStyle.swift
//  LoopKitUI
//
//  Created by Michael Pangburn on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


public struct ActionButtonStyle: ButtonStyle {
    public enum ButtonType {
        case primary
        case secondary
        case destructive
    }

    private let fontColor: Color
    private let backgroundColor: Color
    private let edgeColor: Color
    private let cornerRadius: CGFloat = 10
    // Universal press feedback: fluidly expand on press instead of dimming.
    // Mirrors the app design system (see Loop/AICarbEstimation/UI/GlassStyles.swift
    // and docs/DESIGN_SYSTEM.md); kept as literals here because LoopKitUI can't
    // import the app target. Full-width buttons use the smaller scale so they
    // don't clip at the screen edges.
    private let pressScale: CGFloat = 1.03
    private let pressAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.62)

    @Environment(\.isEnabled) private var isEnabled: Bool

    public init(_ style: ButtonType = .primary) {
        switch style {
        case .primary:
            fontColor = .white
            backgroundColor = .accentColor
            edgeColor = .clear
        case .destructive:
            fontColor = .white
            backgroundColor = .red
            edgeColor = .clear
        case .secondary:
            fontColor = .accentColor
            backgroundColor = .clear
            edgeColor = .accentColor
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .foregroundColor(fontColor)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? backgroundColor : Color(UIColor.lightGray))
            .cornerRadius(cornerRadius)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(edgeColor))
            .contentShape(Rectangle())
            // Fluidly expand on press (never dim) — shared app-wide feel.
            .scaleEffect(configuration.isPressed ? pressScale : 1)
            .animation(pressAnimation, value: configuration.isPressed)
    }
}
