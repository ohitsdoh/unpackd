//
//  HoldRipple.swift
//  UnpackdKeyboard
//
//  The ripple that answers a press-and-hold on the spacebar.
//

import SwiftUI

/// Concentric contours that gather around the spacebar as the user holds it.
///
/// WHAT THE DESIGN ACTUALLY SHOWS
/// This was built twice as "expanding rings" and was wrong both times, so it is
/// worth stating what the reference image shows instead: at NUDGE and ENGAGED
/// the key is wrapped in *many* soft contours, layered close together and
/// hugging the key's own rounded shape — like the surface of water disturbed
/// around an object, not a wavefront leaving it. They read as a standing state
/// of the key, present the whole time, rather than as one ring travelling out
/// and dissipating.
///
/// Three properties follow from that, and each was a defect in the earlier
/// versions:
///   - MANY, NOT TWO. A pair of rings reads as an animation; a cluster reads as
///     a texture. `contourCount` is deliberately high.
///   - TIGHT, NOT SWEEPING. The outermost contour sits just off the key. A ring
///     crossing the keyboard is a wipe passing over unrelated keys.
///   - UNEVEN. Their spacing is not uniform — evenly spaced concentric capsules
///     read as a target/bullseye. The offsets bunch toward the key.
///
/// WHY NOT A TRANSITION ON THE PANEL
/// A transition modifier can only mask the view it is attached to, so it could
/// never draw around the keys. This is a `ZStack` sibling instead; it owns no
/// layout and lets hit-testing through.
///
/// IT MUST DRAW BENEATH THE KEYS
/// `KeyboardView` paints an opaque background, so this only appears because
/// `KeyboardRootView` hides that background and paints its own at the bottom of
/// the stack. Without that the contours are computed, composited, and covered.
struct HoldRipple: View {

    /// 0...1 through the hold. 0 draws nothing at all.
    var progress: Double

    /// The spacebar's real frame, measured in `RadialWash.coordinateSpace`.
    /// The contours trace this rect exactly, so they sit on the key rather
    /// than near it.
    var keyFrame: CGRect

    /// White is a hard highlight on dark keys — see `tint`.
    @Environment(\.colorScheme) private var colorScheme

    /// How many contours surround the key at full expression.
    ///
    /// The count is what separates "a ring animating" from "the key sitting in
    /// disturbed water". Contours fade in progressively (see `body`), so early
    /// in the hold only the innermost few are drawn and the texture builds.
    private static let contourCount = 7

    var body: some View {
        let anchor = CGPoint(x: keyFrame.midX, y: keyFrame.midY)

        ZStack {
            ForEach(0..<Self.contourCount, id: \.self) { index in
                contour(index: index, key: keyFrame.size, anchor: anchor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// One contour of the cluster.
    ///
    /// Each is a capsule tracing the key's shape at a progressively larger
    /// offset, blurred enough to be a disturbance rather than a drawn outline.
    @ViewBuilder
    private func contour(index: Int, key: CGSize, anchor: CGPoint) -> some View {
        // Offsets bunch toward the key rather than spreading evenly: squaring
        // the normalised index keeps the inner contours tight together and lets
        // the outer ones drift, which is what stops the cluster reading as a
        // bullseye.
        let t = Double(index) / Double(Self.contourCount - 1)
        let offset = maxSpread * (t * t * 0.82 + t * 0.18)

        // Contours arrive in order, so the cluster thickens as the hold
        // deepens instead of appearing all at once. The innermost is visible
        // almost immediately; the outermost only near ACTIVATE.
        let arrival = t * 0.55
        let presence = min(max((progress - arrival) / 0.45, 0), 1)

        // Outer contours are fainter, and everything strengthens with the hold.
        // 0.5 was tuned when the cluster only ever appeared under a finger.
        // As a standing NUDGE state it has to read across a lit keyboard from
        // normal viewing distance, so the whole cluster is stronger.
        let alpha = (1 - t * 0.62) * presence * 0.85

        if alpha > 0.004 {
            // A rounded rect matching the key's own corner radius, grown
            // uniformly. A `Capsule` was wrong for a wide key: it rounds to
            // half the height, so its ends bulged well past the spacebar's
            // actual corners — part of why the outline looked misaligned.
            RoundedRectangle(cornerRadius: cornerRadius + offset, style: .continuous)
                .strokeBorder(tint.opacity(alpha), lineWidth: 1.4 + t * 1.8)
                .frame(width: key.width + offset * 2,
                       height: key.height + offset * 2)
                .position(anchor)
                // Blur scales with distance: the near contours stay crisp
                // enough to define the key's edge, the far ones dissolve into
                // the surrounding glow.
                .blur(radius: 1.2 + t * 5)
        }
    }

    /// How far the outermost contour sits from the key.
    ///
    /// Derived from the key's own measured height, so the cluster scales with
    /// the spacebar rather than with the keyboard. Tying it to keyboard width
    /// made it sweep across neighbouring keys on larger devices.
    private var maxSpread: CGFloat {
        keyFrame.height * 1.35
    }

    /// The key's corner radius.
    ///
    /// KeyboardKit does not expose the resolved value, but the standard key
    /// shape is a small fixed radius rather than a capsule — derived from the
    /// measured height so it tracks device metrics instead of being a literal.
    private var cornerRadius: CGFloat {
        min(keyFrame.height * 0.22, 12)
    }

    /// The contour colour.
    ///
    /// White reads as a hard highlight on dark keys, so dark mode traces in the
    /// iris lilac — the same colour the key itself is tinted with, so the
    /// disturbance looks like it belongs to the key rather than being drawn on
    /// top of it.
    private var tint: Color {
        colorScheme == .dark ? KeyboardTheme.iris[0] : .white
    }
}
