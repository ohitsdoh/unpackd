//
//  RadialWash.swift
//  UnpackdKeyboard
//
//  The wash that expands from the spacebar when a reflection opens.
//

import SwiftUI

/// A soft halo that grows out of the spacebar and bleeds across the keyboard.
///
/// WHY NOT A TRANSITION ON THE PANEL
/// The obvious implementation is `.transition(...)` on `ReflectPanel`, and it
/// does not work: a transition modifier can only mask the view it is attached
/// to, so the circle stops at the panel's own bounds and the keys below are
/// never touched. Worse, the panel's height is animating from zero at the same
/// time, so the mask is clipped to a box that is itself still growing — which
/// is why that version read as an ordinary slide-up no matter how the timing
/// was tuned.
///
/// So this is a `ZStack` overlay spanning panel *and* keyboard instead. It owns
/// no layout: it draws over everything and lets hit-testing through.
///
/// ORIGIN IS FIXED, NOT FOLLOWED
/// The circle always grows from the centre of the spacebar. It deliberately
/// does not follow the thumb — KeyboardKit does not expose a touch location at
/// the moment we need one (`pressAction` and `longPressAction` carry no
/// coordinates, and `handleDrag(on:from:to:)` is not called until the finger
/// actually *moves*, which a stationary press-and-hold never does). Chasing the
/// real point would mean a custom space button and gesture plumbing for an
/// effect nobody watching can distinguish, since the wash covers its own origin
/// within the first few frames.
struct RadialWash: View {

    /// 0 = nothing drawn, 1 = the whole keyboard is covered.
    var progress: CGFloat

    /// Where the circle grows from, as a unit point in the wash's own bounds.
    /// The spacebar: horizontally centred, near the bottom of the keys.
    /// The coordinate space the glow effects resolve the spacebar's frame in.
    ///
    /// `KeyboardRootView` names its ZStack with this, and `SpacebarWordmark` —
    /// which SwiftUI places *inside* the real key — reports its own frame in
    /// it. That measured rect is what the contours and the wash draw around.
    ///
    /// WHY MEASURED AND NOT ESTIMATED
    /// These effects used hardcoded fractions: 42% of keyboard width, 16% of
    /// height, centred 88% down. That could never be right. The spacebar's
    /// share of the bottom row changes with device, orientation, locale layout
    /// and the number of system keys in the row, and its vertical position
    /// changes whenever the panel grows the stack. The outline therefore sat
    /// slightly small and slightly off against the real key — and an outline
    /// that *nearly* matches reads as a misprint, which is worse than no
    /// outline at all.
    ///
    /// Nothing here should be a magic fraction of the keyboard. If a future
    /// effect needs the key's geometry, take it from this measurement.
    static let coordinateSpace = "unpackd.keyboard"

    /// Measured once per layout rather than read inside a `GeometryReader`.
    /// `progress` animates continuously for 600ms, and a `GeometryReader` whose
    /// closure derives the anchor and radius would redo that work on every one
    /// of those frames — for values that only change when the keyboard resizes.
    /// Matches how `KeyboardRootView` measures its own heights.
    @State private var size: CGSize = .zero

    /// Dark mode needs a different glow, not the same one at lower opacity.
    ///
    /// The light-mode wash is white-cored: on pale keys that reads as light
    /// spilling out. On dark keys the same white core is a hard bright disc —
    /// a spotlight rather than a glow — so dark mode drops the white entirely
    /// and leads with the iris colours, which sit far closer to the surface
    /// they are blooming over.
    @Environment(\.colorScheme) private var colorScheme

    /// The spacebar's real frame, measured in `RadialWash.coordinateSpace`.
    var keyFrame: CGRect

    var body: some View {
        // Anchored to the measured key, not to a unit point.
        let anchor = CGPoint(x: keyFrame.midX, y: keyFrame.midY)

        // Starts at the spacebar's own footprint and blooms outward, so the
        // glow looks like it is coming *off the key* rather than arriving from
        // somewhere else.
        let width = keyFrame.width + size.width * 1.30 * progress
        let height = keyFrame.height + size.height * 1.05 * progress

        Capsule()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width / 2, 2)
                )
            )
            .frame(width: max(width, 0), height: max(height, 0))
            .position(anchor)
            // Heavy and constant, rather than relaxing as it fills. This is the
            // difference between a glow and a shape: a wash that sharpens as it
            // settles ends up looking like a translucent object sitting on the
            // keyboard, which is exactly the hard-edged reading to avoid.
            .blur(radius: 28)
            // Fades in faster than it grows. Tying alpha to `progress` linearly
            // made the bloom arrive dimmest exactly when it was largest.
            .opacity(min(progress * 2.2, 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .allowsHitTesting(false)
    }

    /// Stops for the halo, from its centre outward.
    ///
    /// Indexed into the canonical palette rather than re-typed: these are the
    /// same colours the spacebar uses, and the wash blooming in a subtly
    /// different lilac is exactly what a second copy causes.
    private var colors: [Color] {
        if colorScheme == .dark {
            [
                KeyboardTheme.iris[0].opacity(0.34),
                KeyboardTheme.iris[1].opacity(0.24),
                KeyboardTheme.iris[3].opacity(0.12),
                .clear
            ]
        } else {
            [
                .white.opacity(0.38),
                KeyboardTheme.iris[0].opacity(0.24),
                KeyboardTheme.iris[1].opacity(0.16),
                KeyboardTheme.iris[3].opacity(0.10),
                .clear
            ]
        }
    }
}
