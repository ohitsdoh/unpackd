//
//  Typography.swift
//  Unpackd
//

import SwiftUI
import UIKit

/// Inter, with a system fallback.
///
/// WHY FACES ARE ADDRESSED BY POSTSCRIPT NAME, NOT BY FAMILY + WEIGHT
/// The obvious spelling is `.custom("Inter", size:).weight(.medium)`. It does
/// not work with these files, and the way it fails is silent, so this is worth
/// stating plainly:
///
///   - The bundled faces are Google Fonts' *optical size* cut of Inter. Their
///     family name is "Inter 18pt", not "Inter" — so `.custom("Inter", ...)`
///     matches nothing and falls back to San Francisco without an error.
///   - Worse, each weight registers as its own family: "Inter 18pt Light" and
///     "Inter 18pt Medium" are siblings of "Inter 18pt", not weights within it.
///     So even the correct family name plus `.weight(.medium)` cannot reach the
///     medium face — there is nothing for the weight to select.
///
/// Naming the PostScript face directly sidesteps both. `.weight()` is still
/// applied afterwards so the *fallback* renders at the intended weight when the
/// files are missing; when they are present it is a no-op on an already-correct
/// face.
///
/// If the fonts are ever swapped for a different cut of Inter, the PostScript
/// names below are what must change. `Typography.audit()` prints what actually
/// registered.
enum Typography {

    /// PostScript names of the bundled faces, by weight.
    ///
    /// Only the weights the app actually uses are bundled — see
    /// `Resources/Fonts/README.md`. A weight absent from this table falls
    /// through to the nearest bundled face rather than silently synthesising.
    private static let faces: [Font.Weight: String] = [
        .light: "Inter18pt-Light",
        .regular: "Inter18pt-Regular",
        .medium: "Inter18pt-Medium",
        .semibold: "Inter18pt-SemiBold",
        .bold: "Inter18pt-Bold"
    ]

    /// Inter at a given size and weight.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(faceName(for: weight), size: size).weight(weight)
    }

    /// Display type stays on the system serif.
    ///
    /// This is not an oversight. The large headings were set in a serif on
    /// purpose, and Inter is a grotesque — swapping them would flatten the
    /// editorial contrast between a heading and its body copy, which is most
    /// of what makes the onboarding read as considered rather than as a form.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The bundled face for a weight, falling back to the nearest one that
    /// exists rather than to a name that would resolve to San Francisco.
    private static func faceName(for weight: Font.Weight) -> String {
        if let exact = faces[weight] { return exact }
        // Heavier-than-bundled asks land on Bold, lighter ones on Light. Only
        // reachable if a call site uses a weight outside the bundled set.
        switch weight {
        case .thin, .ultraLight: return faces[.light]!
        case .heavy, .black: return faces[.bold]!
        default: return faces[.regular]!
        }
    }

    /// Whether the bundled faces actually registered.
    ///
    /// False means the .ttf files are missing from the target or absent from
    /// `UIAppFonts`, and every call above is silently rendering in San
    /// Francisco. Checked against a real face name rather than a family,
    /// because the family name is not "Inter" — see the type's note.
    static var isAvailable: Bool {
        UIFont(name: faces[.regular]!, size: 12) != nil
    }

    /// Prints which of the bundled faces resolved. For diagnosing a fallback
    /// on device, where the failure is otherwise invisible.
    static func audit() {
        for (weight, name) in faces.sorted(by: { $0.value < $1.value }) {
            let ok = UIFont(name: name, size: 12) != nil
            print("[Typography] \(ok ? "✓" : "✗") \(name) (\(weight))")
        }
    }
}
