//
//  KeyboardTheme.swift
//  UnpackdKeyboard
//

import Foundation
import KeyboardKit
import SwiftUI
import UIKit

/// Colours for the *reflect panel*.
///
/// SCOPE, AND WHY IT SHRANK
/// This used to also hold hand-rolled colours for the keys themselves —
/// `keyboardBackground`, `keyBackground`, `specialKeyBackground`, `keyBorder`,
/// `keyShadow`, `pressedOverlay` — which were applied over the top of
/// KeyboardKit's `standardStyle()`. They have been removed rather than left
/// unused, because an unused colour named `keyBackground` is an invitation to
/// put it back.
///
/// The keys now render entirely from `standardStyle()` and
/// `KeyboardViewStyle.standard`, which track the system across light/dark,
/// Liquid Glass, device metrics and the appearance bug that keyboard
/// extensions hit. Do not reintroduce literal RGB values for keys here; if a
/// key colour looks wrong, the fix is in KeyboardKit's tokens
/// (`Color.keyboardButtonBackground` and friends), not in a private copy.
///
/// What remains is genuinely ours: the panel is Unpackd's own surface, not a
/// reimplementation of an Apple one, so it is styled deliberately.
enum KeyboardTheme {
    static let ink = adaptive(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.945, blue: 0.925, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 0.48),
        dark: UIColor(red: 0.945, green: 0.945, blue: 0.925, alpha: 0.54)
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
    // The iris gradient on the *panel cards* is pastel in both schemes, so
    // text there is always dark — this is deliberately NOT adaptive.
    //
    // The SPACEBAR is a different surface and needs `onSpacebar(_:)` below:
    // its gradient now recedes toward the dark key colour in dark mode, so a
    // fixed black label would be black-on-dark-grey.
    static let onIris = Color.black.opacity(0.82)
    static let onIrisMuted = Color.black.opacity(0.52)

    /// The dark-appearance spectrum.
    ///
    /// Not `iris` dimmed — see `irisGradient`. These are chosen to sit at
    /// roughly a dark key's own luminance while keeping real, distinguishable
    /// hue: violet, blue, cyan, rose, amber. On a dark keyboard the eye reads
    /// hue far more readily than lightness, so the iridescence is carried by
    /// colour difference rather than by glow.
    static let irisDark = [
        Color(red: 0.290, green: 0.255, blue: 0.420),
        Color(red: 0.215, green: 0.310, blue: 0.440),
        Color(red: 0.200, green: 0.345, blue: 0.365),
        Color(red: 0.390, green: 0.250, blue: 0.345),
        Color(red: 0.400, green: 0.300, blue: 0.235)
    ]

    static let iris = [
        Color(red: 0.855, green: 0.824, blue: 1.000),
        Color(red: 0.765, green: 0.886, blue: 1.000),
        Color(red: 0.961, green: 0.878, blue: 1.000),
        Color(red: 1.000, green: 0.824, blue: 0.925),
        Color(red: 1.000, green: 0.894, blue: 0.792)
    ]

    /// The spacebar's gradient at a given point in the hold.
    ///
    /// At rest the iris colours are washed most of the way out toward the key
    /// surface, so the spacebar reads as a normal key with a faint sheen. As
    /// the hold progresses they saturate toward their full values — this is
    /// the "iridescence reaches full expression" beat of stage 04.
    ///
    /// WHAT A LOW INTENSITY MIXES *TOWARD*, AND WHY IT IS NOT WHITE
    /// This mixed toward `.white` in both appearances. In light mode that is
    /// right — a barely-lit spacebar should look like the white keys around
    /// it. In dark mode it was badly wrong: at REST the key is mixed ~66%
    /// toward white, so the spacebar sat as a pale slab among dark grey keys,
    /// permanently shouting, and every intensity step made it *less* distinct
    /// rather than more.
    ///
    /// The fix is that the desaturated end is the *neighbouring key surface*,
    /// not white. The iris colours then read as a tint blooming on a key that
    /// otherwise matches its neighbours — which is what "subtle iridescence,
    /// recognizably Unpackd" means in a dark keyboard.
    ///
    /// Still a mix rather than an opacity ramp: lowering alpha would let the
    /// keyboard *background* show through, which is a darker colour than the
    /// key and makes the spacebar read as a hole.
    ///
    /// - Parameters:
    ///   - intensity: combined ambient presence + hold, 0...1. Comes from
    ///     `ReflectSession.spacebarIntensity`; the floor for REST lives in
    ///     `SpacebarPresence.intensity`, not here, so the spectrum is defined
    ///     in exactly one place.
    ///   - phase: rotates the colour stops for the ambient drift. Full circle
    ///     at 1, so callers can hand it a repeating 0...1 ramp.
    ///   - colorScheme: which surface the key is resting against.
    static func irisGradient(
        intensity: Double,
        phase: Double = 0,
        colorScheme: ColorScheme = .light
    ) -> [Color] {
        let t = min(max(intensity, 0), 1)
        let rotated = rotate(iris, by: phase)
        // Dark mode never mixes all the way to the key surface — even at REST
        // the key keeps a little tint, or it stops being recognizably Unpackd.
        if colorScheme == .dark {
            // DARK MODE USES ITS OWN PALETTE, NOT THE LIGHT ONE DIMMED.
            //
            // Mixing the near-white pastels toward the key surface was tried
            // and measured: at the brightness that stops the key looking like a
            // pale slab, saturation fell to ~0.04 — a flat grey key with no
            // hue left at all. The two goals are in direct conflict for a
            // near-white palette on a dark ground, because the thing making it
            // too bright IS the thing carrying the colour.
            //
            // `irisDark` solves that: colours picked to be *already* dark
            // enough to sit beside a neighbouring key, with the saturation
            // carried in hue rather than in lightness.
            let rotatedDark = rotate(irisDark, by: phase)
            // REST sits toward the key surface; ENGAGED lifts toward white.
            // The span has to be big enough to *see* — a previous version
            // moved only 3.3% in luminance between REST and NUDGE, so a
            // correctly-detected angry draft produced no visible change at all.
            //
            // Below `t = 0` the key would go fully grey and stop being
            // recognizably Unpackd, so REST still keeps most of its hue; the
            // travel is in brightness, which is what the eye picks up on a dark
            // keyboard at a glance.
            let toSurface = 0.55 * (1 - t)       // dimmed toward the key at REST
            let toWhite = 0.22 * t               // lifted toward white at ENGAGED
            return rotatedDark.map {
                $0.mix(with: darkKeySurface, by: toSurface).mix(with: .white, by: toWhite)
            }
        }
        return rotated.map { $0.mix(with: .white, by: 1 - t) }
    }

    /// The flat fill beneath the iridescent film.
    ///
    /// The film is not fully opaque, so this decides what shows through in the
    /// gaps: a pale ground in light mode, the dark key surface in dark mode.
    /// Without it the keyboard background showed through and the spacebar read
    /// as a hole.
    static func baseSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? darkKeySurface : Color.white
    }

    /// The dark-appearance key surface the spacebar recedes toward. Matches
    /// KeyboardKit's own dark button background closely enough that a fully
    /// desaturated spacebar would be indistinguishable from its neighbours.
    private static let darkKeySurface = Color(
        red: 0.255, green: 0.267, blue: 0.298
    )

    /// Continuously rolls the gradient's stops around the key.
    ///
    /// Interpolating between neighbouring stops rather than swapping them at
    /// integer boundaries: a discrete rotation would step visibly once per
    /// cycle, which is the one thing "gentle, slow movement" cannot do.
    private static func rotate(_ colors: [Color], by phase: Double) -> [Color] {
        guard phase != 0, colors.count > 1 else { return colors }
        let count = colors.count
        let shift = phase.truncatingRemainder(dividingBy: 1) * Double(count)
        let whole = Int(shift.rounded(.down))
        let frac = shift - Double(whole)
        return (0..<count).map { i in
            let a = colors[(i + whole) % count]
            let b = colors[(i + whole + 1) % count]
            return a.mix(with: b, by: frac)
        }
    }

    /// `style(for:)` needs to know how far through the hold we are, but
    /// `ButtonStyleBuilderParams` carries only action/context/isPressed — there
    /// is no room in KeyboardKit's type to thread our own state through it. So
    /// the builder is *created with* the progress instead, and the call site
    /// rebuilds it whenever `holdProgress` changes. That is cheap: it is a
    /// closure, and SwiftUI is already re-running `body` for the ripple on the
    /// same frames.
    @MainActor
    static func styleBuilder(
        intensity: Double,
        phase: Double = 0,
        colorScheme: ColorScheme = .light
    ) -> Keyboard.ButtonStyleBuilder {
        { params in
            style(
                for: params,
                intensity: intensity,
                phase: phase,
                colorScheme: colorScheme
            )
        }
    }

    /// The style for one key.
    ///
    /// EVERY KEY BUT SPACE IS RETURNED UNTOUCHED.
    ///
    /// This used to call `standardStyle()` and then override colours, font,
    /// corner radius, border and shadow with hardcoded RGB values — which is
    /// to say it reimplemented the system keyboard by hand and got it slightly
    /// wrong. That is worth not doing again, for reasons beyond taste:
    ///
    ///   - `standardStyle()` already tracks the system: light/dark, the
    ///     `keyboardButtonBackgroundForColorSchemeBug` workaround for the
    ///     appearance bug extensions hit, Liquid Glass, iPad vs iPhone metrics,
    ///     and whatever Apple changes next. Hardcoded values track none of it
    ///     and go stale silently.
    ///   - Keys are muscle memory. A 5pt corner radius where the system uses a
    ///     different one, or a 16pt font where the system sizes by device, is
    ///     not a design choice the user notices and admires — it is a keyboard
    ///     that feels subtly wrong to type on.
    ///
    /// The design brief is explicit about this: "Preserve the conventions
    /// people already know. Change only what creates value." The spacebar is
    /// the one thing that creates value here, so it is the one thing changed.
    @MainActor
    static func style(
        for params: Keyboard.ButtonStyleBuilderParams,
        intensity: Double = SpacebarPresence.rest.intensity,
        phase: Double = 0,
        colorScheme: ColorScheme = .light
    ) -> Keyboard.ButtonStyle {
        let base = params.standardStyle()
        guard params.action == .space else { return base }

        return base.extended(
            with: Keyboard.ButtonStyle(
                // A flat base only. The iridescent film is drawn by
                // `SpacebarWordmark` in the button's own content, because
                // `Keyboard.Background` renders a gradient whose direction we
                // cannot set and the spectrum has to sweep along the key. Two
                // gradients would otherwise fight: this one underneath, the
                // real one on top.
                backgroundColor: baseSurface(colorScheme),
                // The label must be pinned dark, and this is NOT adaptive.
                //
                // The iris gradient mixes toward *white* in both appearances —
                // that is deliberate (see `irisGradient`), so the spacebar is a
                // pale, luminous key even in dark mode. But `standardStyle()`'s
                // foreground is near-white in dark mode, because it assumes the
                // dark key surface it also supplied. Inheriting it put white
                // text on a near-white spacebar: the wordmark vanished.
                //
                // This is the same trap `onAccent`/`accent` documents further
                // up the file. Any key whose background is overridden to a
                // fixed lightness has to override its foreground with it —
                // the two are one decision, not two.
                foregroundColor: onSpacebar(colorScheme),
                //
                // Corner radius, font, border and pressed overlay are all
                // deliberately absent: `extended(with:)` only overrides
                // non-nil fields, so the spacebar keeps the system's own
                // geometry and only its fill differs. It should read as the
                // native spacebar wearing a gradient, not as a custom control.
                //
                // The shadow is the one exception — it deepens as the key
                // intensifies so it appears to rise off the keyboard ("more
                // presence"). Measured from REST, so the resting key sits at
                // exactly the same height as its neighbours.
                shadow: shadow(for: base, intensity: intensity, isPressed: params.isPressed)
            )
        )
    }

    /// The spacebar's lift, expressed as the system's own shadow with a larger
    /// radius. Reuses `standardStyle()`'s shadow colour rather than a hardcoded
    /// black, so it stays correct in both appearances.
    /// The wordmark colour for the spacebar's current appearance.
    ///
    /// Follows the gradient's own resting target: in light mode the key stays
    /// pale, so the label is near-black; in dark mode the key recedes toward
    /// the dark key surface, so the label has to be light or it disappears
    /// into it. Getting this wrong is invisible in whichever scheme you happen
    /// to be testing in, which is how it shipped backwards once already.
    static func onSpacebar(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.92)
            : Color.black.opacity(0.82)
    }

    @MainActor
    private static func shadow(
        for base: Keyboard.ButtonStyle,
        intensity: Double,
        isPressed: Bool
    ) -> Keyboard.ButtonStyle.ShadowStyle? {
        guard let standard = base.shadow else { return nil }
        guard !isPressed else { return standard }
        let lift = SpacebarPresence.lift(above: intensity)
        guard lift > 0 else { return standard }
        return .init(color: standard.color, size: (standard.size ?? 1) + 3 * lift)
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
