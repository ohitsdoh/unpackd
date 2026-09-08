//
//  SpacebarWordmark.swift
//  UnpackdKeyboard
//

import SwiftUI

/// The "unpackd" label that replaces the space key's normal caption.
///
/// WHY THE SPACE KEY IS BRANDED AT ALL
/// The hold gesture is invisible — nothing about a spacebar suggests holding it
/// does something. The wordmark is the only standing affordance the feature
/// has, so it stays legible at rest rather than appearing only once the user
/// has already discovered the gesture.
///
/// The label tracks the hold: letterspacing opens up and the weight settles as
/// the gesture is confirmed, so the word itself participates in the 03 → 04
/// transition instead of sitting inert on top of it.
struct SpacebarWordmark: View {

    /// Combined ambient presence + hold, 0...1 — `spacebarIntensity`. The label
    /// tracks the same spectrum as the key it sits on, so the wordmark firms up
    /// as the key comes to life rather than staying flat until a hold begins.
    var intensity: Double

    /// Rotates the spectrum along the key. Comes from the same drift clock as
    /// everything else, so the key's shimmer and the glow stay in step.
    var phase: Double = 0

    /// The wordmark sits on a key whose own resting colour is scheme-dependent
    /// (see `KeyboardTheme.irisGradient`), so the label has to follow it.
    @Environment(\.colorScheme) private var colorScheme

    /// Reports the spacebar's real frame to the glow effects.
    ///
    /// This view is the only thing in the project that SwiftUI places *inside*
    /// the real key — KeyboardKit builds the button and hands us its content —
    /// so it is the only place the key's true frame can be observed. The glow
    /// used hardcoded fractions of the keyboard before this, which could not
    /// track device, orientation or layout and left the outline visibly off.
    ///
    /// The label is inset within the button, so the reported rect is padded
    /// back out to the button's own bounds — see `keyInset`.
    var onFrameChange: ((CGRect) -> Void)?

    var body: some View {
        // The iridescence is drawn HERE, behind the label, rather than through
        // `Keyboard.Background`'s `backgroundGradient`.
        //
        // WHY
        // That API takes a flat colour array and renders it as a fixed
        // LinearGradient whose direction we cannot set. The reference shows the
        // spectrum sweeping *along* the key — pink at one end through lilac and
        // mint to blue at the other — with a soft sheen over the top. A
        // vertical two-stop ramp cannot produce that, which is most of why the
        // key read as a flat tinted slab rather than as iridescent.
        //
        // Drawing it in the button's own content gives control of angle,
        // layering and blend mode, and it composites *above* the key's base
        // fill so the system's pressed-state and shadow still work normally.
        ZStack {
            iridescence
            label
        }
    }

    /// The iridescent film across the key.
    private var iridescence: some View {
        ZStack {
            // The spectrum itself, swept along the key's long axis.
            LinearGradient(
                colors: KeyboardTheme.irisGradient(
                    intensity: intensity,
                    phase: phase,
                    colorScheme: colorScheme
                ),
                startPoint: .leading,
                endPoint: .trailing
            )

            // NO SLIDING SHEEN.
            //
            // There was a second gradient here — white/clear/white/clear on a
            // diagonal, offset horizontally by a sine so it slid back and forth
            // across the key. It was meant to read as light catching a film.
            // It did not: with four abrupt stops and no blur it rendered as a
            // hard-edged bar physically travelling across the spacebar, which
            // is the "gradient line thing that keeps moving".
            //
            // Real iridescence shifts HUE as the viewing angle changes; it does
            // not slide a white streak over a surface. The hue rotation in
            // `KeyboardTheme.irisGradient` is the effect — a highlight sliding
            // on top of it is a different, worse effect competing with it.
            //
            // A fixed, very soft top highlight instead: keys are lit from above,
            // so this is just the key's own shading, and it does not move.
            LinearGradient(
                colors: [
                    .white.opacity(0.10 * sheenStrength),
                    .white.opacity(0.02 * sheenStrength),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Clipped to the key's own shape by the button, but rounded here too so
        // the film does not square off the corners at high intensity.
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .allowsHitTesting(false)
    }

    private var label: some View {
        Text("unpackd")
            .font(.unpackdWordmark(size: 15, weight: weight))
            // The design's wordmark is widely tracked. It widens further as the
            // key intensifies — a small movement, but it is what makes the key
            // feel like it is *opening* rather than just lighting up.
            .tracking(1.6 + 1.4 * lift)
            // Interpolated alpha over the scheme's own base colour, NOT
            // `.opacity()` stacked on an already-transparent constant.
            //
            // `onIris` is `black.opacity(0.82)`, so the previous
            // `.opacity(0.72)` multiplied the two to 0.59 and the wordmark
            // rendered washed-out grey instead of the near-black the design
            // shows. Naming the alpha directly means the number here is the
            // alpha you get.
            .foregroundStyle(
                KeyboardTheme.onSpacebar(colorScheme).opacity(0.75 + 0.25 * lift)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsHitTesting(false)
            // Fill the button so the measured frame is the key's, not the
            // text's. Without this the rect is only as wide as "unpackd".
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(RadialWash.coordinateSpace))
            } action: { frame in
                onFrameChange?(frame)
            }
    }

    /// The highlight strengthens slightly with intensity. Static — see the
    /// note in `iridescence` about why nothing slides.
    private var sheenStrength: Double {
        let base = 0.55 + 0.45 * lift
        return colorScheme == .dark ? base * 0.4 : base
    }

    /// How far above resting intensity the key is, 0...1, so the label's
    /// movement is measured from REST rather than from nothing.
    private var lift: Double {
        SpacebarPresence.lift(above: intensity)
    }

    /// 300 at rest, stepping to 400 once the key is well lit. Inter's variable
    /// axis is not available through `Font.custom`, so this is a two-stop step
    /// rather than a continuous interpolation — at 15pt the difference between
    /// adjacent weights is not perceptible enough to be worth carrying a
    /// variable font in a 60MB extension.
    private var weight: Font.Weight {
        intensity >= SpacebarPresence.nudge.intensity ? .regular : .light
    }
}

extension Font {

    /// Inter, for the spacebar wordmark only.
    ///
    /// SCOPE IS DELIBERATE
    /// Inside the *extension* this is brand typography for one label, not a UI
    /// font. The panel and the keys stay on the system font: they render text
    /// the user is reading at a bad moment, and San Francisco is what every
    /// other keyboard and message bubble on the device uses. Setting the panel
    /// in Inter would make it read as a web page pasted over the keyboard, and
    /// would cost Dynamic Type and the system's optical sizing.
    ///
    /// That scope is a policy about call sites, not a reason to restate the
    /// face table — `Typography` is compiled into this target too (see
    /// `project.yml`), so the PostScript names live in exactly one place and
    /// `Typography.audit()` is reachable from the extension, which is where
    /// the only Inter consumer actually ships.
    static func unpackdWordmark(size: CGFloat, weight: Font.Weight) -> Font {
        Typography.inter(size, weight)
    }
}
