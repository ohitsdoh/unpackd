//
//  RadialWash.swift
//  UnpackdKeyboard
//
//  The wash that expands from the spacebar when a reflection opens.
//

import SwiftUI

/// A circle that grows from the spacebar across the entire keyboard.
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
    private let origin = UnitPoint(x: 0.5, y: 0.88)

    /// Measured once per layout rather than read inside a `GeometryReader`.
    /// `progress` animates continuously for 600ms, and a `GeometryReader` whose
    /// closure derives the anchor and radius would redo that work on every one
    /// of those frames — for values that only change when the keyboard resizes.
    /// Matches how `KeyboardRootView` measures its own heights.
    @State private var size: CGSize = .zero

    var body: some View {
        let anchor = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
        let diameter = Self.coveringRadius(for: size, from: anchor) * 2 * progress

        Circle()
            .fill(.tint.opacity(0.14))
            .frame(width: diameter, height: diameter)
            .position(anchor)
            // A soft edge keeps the growing circle from reading as a
            // hard-edged wipe. It relaxes as the wash fills so the settled
            // state is not permanently fuzzy.
            .blur(radius: 14 * (1 - progress) + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .allowsHitTesting(false)
    }

    /// Distance from `point` to the furthest corner of `size` — the radius at
    /// which the circle covers everything, corners included.
    static func coveringRadius(for size: CGSize, from point: CGPoint) -> CGFloat {
        let dx = max(point.x, size.width - point.x)
        let dy = max(point.y, size.height - point.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
