//
//  KeyboardTheme.swift
//  UnpackdKeyboard
//

import Foundation
import KeyboardKit
import SwiftUI
import UIKit

enum KeyboardTheme {
    static let ink = adaptive(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.945, blue: 0.925, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 0.48),
        dark: UIColor(red: 0.945, green: 0.945, blue: 0.925, alpha: 0.54)
    )
    static let keyboardBackground = adaptive(
        light: UIColor(red: 0.804, green: 0.820, blue: 0.839, alpha: 1),
        dark: UIColor(red: 0.145, green: 0.153, blue: 0.173, alpha: 1)
    )
    static let keyBackground = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.255, green: 0.267, blue: 0.298, alpha: 1)
    )
    static let specialKeyBackground = adaptive(
        light: UIColor(red: 0.678, green: 0.710, blue: 0.753, alpha: 1),
        dark: UIColor(red: 0.192, green: 0.204, blue: 0.235, alpha: 1)
    )
    static let panelBackground = adaptive(
        light: UIColor(red: 0.980, green: 0.980, blue: 0.973, alpha: 1),
        dark: UIColor(red: 0.118, green: 0.122, blue: 0.137, alpha: 1)
    )
    static let cardBackground = adaptive(
        light: UIColor.white.withAlphaComponent(0.88),
        dark: UIColor(red: 0.180, green: 0.188, blue: 0.212, alpha: 0.94)
    )
    static let border = adaptive(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    static let keyBorder = adaptive(
        light: UIColor.black.withAlphaComponent(0.03),
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let keyShadow = adaptive(
        light: UIColor.black.withAlphaComponent(0.30),
        dark: UIColor.black.withAlphaComponent(0.55)
    )
    // A filled button: `onAccent` is the label ON `accent`, so the two must
    // always flip together. Using a fixed .white label over `ink` gave white
    // on near-white in dark mode (~1.1:1) — the label vanished.
    static let accent = adaptive(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.945, blue: 0.925, alpha: 1)
    )
    static let onAccent = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.086, green: 0.090, blue: 0.106, alpha: 1)
    )

    // Surfaces for the choice cards. The light-mode originals were literal
    // whites, which stayed white on a dark panel.
    static let cardFillTop = adaptive(
        light: UIColor.white.withAlphaComponent(0.84),
        dark: UIColor(red: 0.243, green: 0.255, blue: 0.286, alpha: 0.92)
    )
    static let cardFillBottom = adaptive(
        light: UIColor.white.withAlphaComponent(0.64),
        dark: UIColor(red: 0.204, green: 0.216, blue: 0.247, alpha: 0.92)
    )
    // The icon disc on a card. On the iris gradient (a light pastel in both
    // schemes) it stays light, so its tinted glyph keeps contrast.
    static let iconDisc = adaptive(
        light: UIColor.white.withAlphaComponent(0.70),
        dark: UIColor.white.withAlphaComponent(0.82)
    )
    // The iris gradient is pastel in both schemes, so text on the primary
    // card is always dark — this is deliberately NOT adaptive.
    static let onIris = Color.black.opacity(0.82)
    static let onIrisMuted = Color.black.opacity(0.52)

    static let pressedOverlay = adaptive(
        light: UIColor.white.withAlphaComponent(0.14),
        dark: UIColor.white.withAlphaComponent(0.08)
    )

    static let iris = [
        Color(red: 0.855, green: 0.824, blue: 1.000),
        Color(red: 0.765, green: 0.886, blue: 1.000),
        Color(red: 0.961, green: 0.878, blue: 1.000),
        Color(red: 1.000, green: 0.824, blue: 0.925),
        Color(red: 1.000, green: 0.894, blue: 0.792)
    ]

    @MainActor
    static func style(for params: Keyboard.ButtonStyleBuilderParams) -> Keyboard.ButtonStyle {
        let base = params.standardStyle()
        let isSystem = isSystemAction(params.action)
        let isSpace = params.action == .space

        let background: Keyboard.Background?
        if isSpace {
            background = Keyboard.Background(
                backgroundGradient: iris,
                overlayGradient: [
                    .white.opacity(params.isPressed ? 0.18 : 0.34),
                    .white.opacity(0.04)
                ]
            )
        } else {
            background = nil
        }

        return base.extended(
            with: Keyboard.ButtonStyle(
                background: background,
                backgroundColor: isSpace ? nil : (isSystem ? specialKeyBackground : keyBackground),
                backgroundOpacity: params.isPressed ? 0.72 : 1,
                foregroundColor: ink,
                foregroundSecondaryOpacity: 0.55,
                font: .system(size: 16, weight: .regular),
                cornerRadius: 5,
                border: .init(color: keyBorder, size: 0.5),
                shadow: .init(color: keyShadow.opacity(params.isPressed ? 0.35 : 1), size: params.isPressed ? 0 : 1),
                pressedOverlayColor: isSpace ? pressedOverlay : pressedOverlay.opacity(0.82)
            )
        )
    }

    private static func isSystemAction(_ action: KeyboardAction) -> Bool {
        switch action {
        case .character(_), .characterMargin(_), .space:
            false
        default:
            true
        }
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum KeyboardPracticeSettings {
    private static let appGroupId = "group.com.hoamedigital.unpackd"
    private static let enabledPracticeKeysKey = "enabledPracticeKeys"
    private static let defaultEnabledKeys: Set<String> = ["B", "R"]

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    static func isEnabled(_ key: String) -> Bool {
        enabledKeys().contains(key.uppercased())
    }

    private static func enabledKeys() -> Set<String> {
        guard let values = defaults.array(forKey: enabledPracticeKeysKey) as? [String] else {
            return defaultEnabledKeys
        }
        return Set(values.map { $0.uppercased() })
    }
}
