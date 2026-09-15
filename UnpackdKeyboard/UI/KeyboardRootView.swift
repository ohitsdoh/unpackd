//
//  KeyboardRootView.swift
//  UnpackdKeyboard
//

import KeyboardKit
import SwiftUI

/// Composes the reflect panel above the keyboard and reports the total height
/// the extension needs so the controller can grow its frame.
struct KeyboardRootView<KeyboardView: View>: View {

    /// Owned by the controller, not by this view. `@State` would capture the
    /// first instance and silently ignore later ones; plain `let` is correct
    /// because @Observable tracks reads inside `body` regardless of ownership.
    let session: ReflectSession
    let onHeightChange: (CGFloat) -> Void
    let onApplyRewrite: (String) -> Void
    /// Handed down to the panel's text entry, which registers itself as
    /// KeyboardKit's `textInputProxy` while focused. Passed explicitly rather
    /// than through the environment — see `ReflectPanel.keyboardContext`.
    let keyboardContext: KeyboardContext
    /// Builds the keyboard, given a frame reporter and the current drift phase.
    /// The phase reaches the spacebar's own content, which draws the iridescent
    /// film — see `SpacebarWordmark`.
    @ViewBuilder let keyboardView: (@escaping (CGRect) -> Void, Double) -> KeyboardView

    /// Height of the keys plus the autocomplete toolbar above them. Measured
    /// rather than assumed, because it varies with device and orientation.
    /// The spacebar's gradient, its label and the wash all resolve differently
    /// per appearance — see `KeyboardTheme.irisGradient`.
    @Environment(\.colorScheme) private var colorScheme

    /// The spacebar's measured frame, reported by `SpacebarWordmark` from
    /// inside the real key. Every glow effect is positioned from this — see
    /// `RadialWash.coordinateSpace` for why none of it is estimated.
    @State private var keyFrame: CGRect = .zero

    /// Whether a real measurement has arrived yet.
    private var hasMeasuredKey: Bool {
        keyFrame.width > 0 && keyFrame.height > 0
    }

    @State private var keyboardHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    /// How far the keys have receded, 0...1.
    ///
    /// The recede begins during the hold rather than waiting for the panel, so
    /// stages 04 and 05 read as one continuous movement — the design shows the
    /// keys already softening in the frame the gesture is confirmed. It is
    /// damped to a third while the finger is still down, because an abandoned
    /// hold has to leave the keyboard exactly as it found it, and a keyboard
    /// that visibly dims every time someone types a slightly slow space would
    /// be intolerable.
    private var recede: Double {
        session.isOpen ? 1 : session.visibleHoldProgress * 0.34
    }

    /// Amplitude of the ambient drift, 0 = static. Zero also pauses the
    /// TimelineView entirely, so REST costs nothing.
    private var driftAmount: Double {
        session.isOpen ? 0 : session.spacebarDrift
    }

    /// Whether the contour cluster needs a running clock.
    ///
    /// Two independent reasons to tick, and missing the second one made the
    /// hold draw nothing at all: the timeline was paused unless presence had
    /// reached NUDGE, so holding the spacebar on a calm field — the ordinary
    /// case — never re-evaluated the cluster. The hold updated `holdProgress`
    /// and no frame was ever produced to show it.
    ///
    /// `TimelineView` pausing does not just stop the clock; it stops the body
    /// re-running, which means @Observable reads inside it stop reaching the
    /// screen. Anything animated from *outside* the timeline has to keep it
    /// unpaused too.
    private var rippleIsAnimating: Bool {
        // Nothing can be drawn correctly before the spacebar has reported its
        // frame; drawing at `.zero` would put the glow in the top-left corner.
        guard hasMeasuredKey else { return false }
        guard !session.isOpen else { return false }
        // A hold in progress, or the slow ambient breath at NUDGE.
        return session.holdProgress > 0 || session.presence >= .nudge
    }

    /// How full the contour cluster is, 0...1.
    ///
    /// Follows the key's own intensity so the contours and the iridescence are
    /// one object at one level, with a slow breath added at rest so NUDGE is
    /// alive without a finger on it. The breath is suppressed during a hold —
    /// the ramp is the movement then, and a wander underneath it reads as
    /// instability.
    private func rippleIntensity(at date: Date) -> Double {
        guard hasMeasuredKey, !session.isOpen else { return 0 }

        let held = session.visibleHoldProgress
        guard held == 0 else { return held }
        guard session.presence >= .nudge else { return 0 }

        // A sine around a resting level: never fully absent, never as full as
        // a real hold.
        //
        // Was 0.34 +/- 0.10, which lit only ~3 of the 7 contours at low alpha —
        // technically present, but not something anyone notices mid-sentence.
        // NUDGE's entire job is to "invite a pause", and an invitation nobody
        // sees is not one. Raised so most of the cluster is lit, with a deeper
        // breath so the movement itself is what catches the eye.
        let breath = sin(Self.phase(at: date, period: 3.2) * 2 * .pi)
        return 0.66 + 0.18 * breath
    }

    /// One full rotation of the gradient every 9 seconds, scaled by how much
    /// drift the current presence level calls for.
    private func driftPhase(at date: Date) -> Double {
        Self.phase(at: date, period: 9) * driftAmount
    }

    /// A repeating 0...1 ramp derived from wall-clock time.
    ///
    /// Taken from the timeline's own date rather than accumulated into @State:
    /// a stored phase would jump whenever the keyboard is dismissed and
    /// restored, because the drift keeps notional time while the view is gone.
    private static func phase(at date: Date, period: Double) -> Double {
        date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
    }

    var body: some View {
        // ZStack, not a plain VStack: the wash has to draw over the panel *and*
        // the keys to reach the keyboard's edges. As a transition on the panel
        // it could only ever mask the panel's own bounds. See RadialWash.
        ZStack {
            // The keyboard's own background, painted here rather than by
            // KeyboardView.
            //
            // WHY IT MOVED
            // `KeyboardViewStyle.standard` paints an OPAQUE background behind
            // the keys, and `KeyboardView` sits above the glow layers in this
            // stack — so that background covered every ripple and the wash
            // completely. The symptom is not "the glow looks wrong", it is
            // "the keyboard never glows", because nothing was ever visible.
            //
            // So the background is drawn first, at the bottom of the stack, and
            // `keyboardViewBackground(.hidden)` below stops KeyboardView from
            // drawing its own on top. The glow then sits between the background
            // and the keys, which is where light spilling from a key belongs.
            Color.keyboardBackground(for: colorScheme)
                .ignoresSafeArea()

            // Beneath the keys, above the background: light spilling from the
            // spacebar should pass *behind* its neighbours, not over them.
            RadialWash(
                progress: (session.isOpen && hasMeasuredKey) ? 1 : 0,
                keyFrame: keyFrame
            )

            VStack(spacing: 0) {
                // Absorbs any gap between the height we ask for and the frame
                // iOS actually gives us, and pins panel+keys to the bottom.
                //
                // WHY IT IS HERE
                // A ZStack CENTRES its children. `setKeyboardHeight` installs a
                // `.defaultHigh` constraint — deliberately losable — so the real
                // frame can be taller than `keyboardHeight + panelHeight`. With
                // the VStack centred, that surplus split above and below the
                // keys, and the band above showed the system keyboard backdrop's
                // rounded top edge through it: the "ledge" over the suggestion
                // bar. Bottom-aligning puts the whole surplus at the top, where
                // `Color.keyboardBackground` at the base of this stack already
                // paints it, so a mismatch degrades to a slightly taller
                // keyboard instead of a visible seam.
                //
                // `minLength: 0` so this costs nothing when the frame matches.
                Spacer(minLength: 0)

                if session.isOpen {
                    ReflectPanel(
                        session: session,
                        onApplyRewrite: onApplyRewrite,
                        keyboardContext: keyboardContext
                    )
                        .onGeometryChange(for: CGFloat.self) { $0.size.height }
                            action: { panelHeight = $0 }
                        // Just a fade. The panel arriving is the *result* of the
                        // wash passing over it, not a second animation competing
                        // with it, so it gets no movement of its own.
                        .transition(.opacity)
                }

                // TimelineView drives the ambient drift's phase.
                //
                // WHY IT WRAPS ONLY THE KEYS
                // Everything inside re-evaluates on every frame the schedule
                // fires, so the panel is deliberately outside it — there is no
                // reason to re-run the reflect panel's body at 20fps while the
                // model is thinking.
                //
                // WHY .animation RATHER THAN .periodic
                // `.animation` ticks with the display, so the drift is smooth;
                // it also pauses when the view is not visible, which matters
                // for a keyboard that is offscreen most of the time. A paused
                // schedule is the difference between a decorative gradient and
                // a background timer burning cycles in a 60MB extension.
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: driftAmount == 0)) { timeline in
                    // No `.keyboardViewStyle(...)`: KeyboardViewStyle.standard
                    // is applied by default and matches the system keyboard's
                    // background, corner radii and edge insets per device and
                    // appearance. The previous override hardcoded a background
                    // colour, zeroed both corner radii and set its own insets —
                    // all of which the system already gets right, and gets
                    // right on devices this was never checked on.
                    keyboardView({ keyFrame = $0 }, driftPhase(at: timeline.date))
                        // Make KeyboardKit's long-press fire at exactly the
                        // moment our ramp completes.
                        //
                        // These were two independent numbers that had to agree
                        // and did not: the ramp spanned 700ms while the default
                        // long-press fired at ~500ms, so the panel opened while
                        // the ramp was still at ~70% and the visible part of
                        // the hold — which only starts at the 450ms threshold —
                        // got about 50ms of screen time. The hold looked like
                        // it did nothing because there was no time for it to do
                        // anything.
                        //
                        // Setting it here makes `holdDuration` the single
                        // source: the gesture confirms when the ramp says it
                        // does, not on a timer that happens to be nearby.
                        .keyboardGestureConfiguration(
                            .init(longPressDelay: HoldTiming.holdDuration)
                        )
                        // See the background note at the top of the ZStack:
                        // without this the standard opaque background draws
                        // over every glow layer beneath it.
                        .keyboardViewBackground(.hidden)
                        .keyboardButtonStyle(
                            builder: KeyboardTheme.styleBuilder(
                                intensity: session.spacebarIntensity,
                                phase: driftPhase(at: timeline.date),
                                colorScheme: colorScheme
                            )
                        )
                        // 05 OPEN — "surrounding keys soften and recede".
                        //
                        // WHAT THIS CAN AND CANNOT DO
                        // These modifiers apply to the whole KeyboardView
                        // subtree, spacebar included, because KeyboardKit owns
                        // that view and there is no per-key hook for opacity or
                        // scale. So the design's "keys recede while the
                        // spacebar floats forward" is approximated: everything
                        // recedes together, and the spacebar is kept visually
                        // forward by its own deepening shadow and full
                        // saturation (see KeyboardTheme) rather than by moving
                        // independently.
                        //
                        // Drawing a separate floating copy of the spacebar over
                        // the top was the alternative. It was not worth it: the
                        // ghost has to be positioned by hand against a layout
                        // that varies by device and orientation, and the wash
                        // covers the whole area within ~200ms anyway.
                        // "Soften and recede" — measured to be gentle. An
                        // earlier version dropped opacity 35% and saturation
                        // 55%, which turned the whole keyboard into flat grey
                        // haze rather than letting it sit back.
                        .saturation(1 - 0.20 * recede)
                        .opacity(1 - 0.12 * recede)
                        .scaleEffect(1 - 0.012 * recede, anchor: .bottom)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height }
                            action: { keyboardHeight = $0 }
                }
            }

            // The hold ripple, under the wash so that when the panel commits,
            // the wash passes over the rings rather than the rings sitting on
            // top of a settled panel.
            //
            // The contour cluster around the spacebar.
            //
            // ONE VIEW FOR BOTH STATES, NOT TWO
            // There used to be a separate hold ripple and ambient ripple. That
            // was wrong about what the design shows: the cluster is a *standing
            // state* of the key that thickens with intensity — visible at NUDGE
            // with no finger on it, fuller at ENGAGED — not two effects that
            // happen to overlap. Two instances also drew two overlapping sets
            // of contours whenever a hold began from NUDGE.
            //
            // So it is driven by the same `spacebarIntensity` as the key's own
            // gradient, and breathes slowly so the resting state is alive
            // rather than a static decal.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !rippleIsAnimating)) { timeline in
                HoldRipple(
                    progress: rippleIntensity(at: timeline.date),
                    keyFrame: keyFrame
                )
            }

            // Spans the whole stack, so the circle sweeps across the keys on
            // its way to the corners.
            // NOTE: the wash is intentionally NOT here any more.
            //
            // As a sibling above `keyboardView` it drew a large pale capsule
            // across every key — measured: a neighbouring key went from 0.30 to
            // 0.72 luminance during a hold, i.e. the keys got *brighter* and
            // hazier, the exact opposite of "surrounding keys soften and
            // recede". It is now composited beneath the keys, further up this
            // stack.
        }
        // Names the space the spacebar reports its frame in.
        .coordinateSpace(name: RadialWash.coordinateSpace)
        // Slow and linear-ish rather than eased. `easeOut` front-loads the
        // motion, which is exactly what made the old version read as a snap;
        // this is meant to be watched expanding. Not a spring either — an
        // expanding circle that overshoots reads as a wobble.
        // 0.32s, and eased OUT rather than in-and-out.
        //
        // MEASURED, NOT GUESSED
        // Frame analysis of a hold put the transition at ~1.0s: the 700ms ramp
        // and then a 600ms `easeInOut` wash playing *after* it, serially. The
        // design budgets 700-1000ms for the whole gesture, so the tail alone
        // was eating most of it — and `easeInOut` is slow at both ends, which
        // is what made an already-long transition feel sluggish rather than
        // merely slow.
        //
        // `easeOut` starts immediately and decelerates, so the panel is
        // visibly moving in the first frame after the finger has committed.
        // The user has already waited 700ms holding the key; the reward should
        // not make them wait again.
        //
        // Only `isOpen` is animated. `holdProgress` deliberately is not: the
        // display link already updates it every frame, so a SwiftUI animation
        // on top would add a second interpolation lagging behind the first and
        // the ripple would trail the finger. It also lets an abandoned hold
        // snap back to 0 rather than coasting.
        .animation(.easeOut(duration: 0.32), value: session.isOpen)
        // The ambient level changes on its own, with no gesture behind it, so
        // it must not snap — an unprompted step change on a key nobody touched
        // reads as a glitch.
        //
        // But 0.55s here was itself most of the "it fires slowly" complaint:
        // detection had already happened and the key was still crossfading.
        // `easeOut` starts at full speed and settles, so the change registers
        // immediately and still arrives softly.
        .animation(.easeOut(duration: 0.28), value: session.presence)
        // Height keeps its own faster spring: this drives the keyboard frame
        // growing, and a little softness there is what stops the host app's
        // content from snapping upward. Deliberately quicker than the wash, so
        // the panel has settled into place by the time the circle reaches it.
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: panelHeight)
        .onChange(of: keyboardHeight + (session.isOpen ? panelHeight : 0)) { _, total in
            guard total > 0 else { return }
            onHeightChange(total)
        }
    }
}

// Height is measured with `onGeometryChange` rather than a PreferenceKey.
// Under Swift 6, `onPreferenceChange` takes a `@Sendable` closure, so the old
// helper could not capture a non-Sendable `(CGFloat) -> Void` callback without
// a concurrency error. `onGeometryChange` is also a single pass rather than a
// preference walk, which matters inside a 60MB extension.
