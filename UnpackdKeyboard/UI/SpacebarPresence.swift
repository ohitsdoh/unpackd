//
//  SpacebarPresence.swift
//  UnpackdKeyboard
//
//  How present the spacebar is between gestures.
//

import Foundation

/// The spacebar's ambient intensity — "one object, a spectrum of awareness".
///
/// HOW THIS RELATES TO `ReflectSession.holdProgress`
/// They are different axes and both feed the same visuals:
///
///   - `Presence` is where the key *rests* when nobody is touching it. It
///     changes slowly, on the order of seconds, in response to what the user
///     is writing. Levels 02 AWARE and 03 NUDGE explicitly do not interrupt —
///     the design notes "typing continues" for both.
///   - `holdProgress` is the 0...1 ramp of one press-and-hold gesture.
///
/// Rendering reads `intensity + holdProgress`, so a hold started from NUDGE
/// begins visibly further along than one started from REST. Collapsing them
/// into a single number would lose that: the same 0.5 would mean "the user is
/// halfway through holding" and "the draft looks heated", which want different
/// haptics and different decay behaviour.
enum SpacebarPresence: Int, Comparable {

    /// 01 — "I'm here." Subtle iridescence, static, no haptics.
    case rest = 0
    /// 02 — "Something may be happening." Slightly increased iridescence and a
    /// gentle drift. Still no haptics; typing continues uninterrupted.
    case aware = 1
    /// 03 — "Space might help." More presence and a soft ripple, plus a single
    /// subtle haptic pulse on *arrival* only. Invites a pause; does not demand
    /// one.
    case nudge = 2
    /// 04 — "You chose to create space." Full iridescence. Reached by holding,
    /// not by the draft, which is why `HeatDetector.presence(for:)` never
    /// returns it.
    case engaged = 3

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Baseline saturation of the iris gradient, 0...1.
    ///
    /// THE RANGE IS WIDE, AND THAT IS THE POINT
    /// A previous pass compressed this to 0.78...1.0 while fixing an unrelated
    /// brightness bug. Measured, that made REST -> NUDGE a 3.3% luminance
    /// change — completely imperceptible. The detector was firing correctly on
    /// genuinely angry drafts and *nothing visible happened*, which reads as
    /// the feature being broken.
    ///
    /// The spectrum only means something if the stages are distinguishable, so
    /// the range is wide. What keeps the key from being a pale slab in dark
    /// mode is `KeyboardTheme.irisDark` — a palette that is already the right
    /// brightness — not a compressed intensity range. Those are separate
    /// concerns and squeezing this one to fix that one broke both.
    var intensity: Double {
        switch self {
        case .rest: 0.24
        case .aware: 0.46
        case .nudge: 0.86
        case .engaged: 1.0
        }
    }

    /// Amplitude of the slow ambient drift, 0 = perfectly static.
    ///
    /// REST IS NOT ZERO, DESPITE THE DESIGN SAYING "STATIC"
    /// It was zero, and the result was a spacebar whose colours never moved at
    /// all — the single most common complaint about the key, because on a calm
    /// draft (the overwhelmingly common case) REST is the *only* state anyone
    /// sees. A dead gradient reads as a static image pasted onto the key.
    ///
    /// "Static" in the reference distinguishes REST from AWARE's "gentle, slow
    /// movement", so REST keeps a very slow shimmer — enough that the key is
    /// alive if you look at it, not enough to be movement you notice while
    /// typing. The perceptible step up to AWARE is preserved.
    var drift: Double {
        switch self {
        case .rest: 0.22
        case .aware: 0.55
        case .nudge: 0.85
        case .engaged: 1.0
        }
    }

    /// Whether arriving at this level fires one haptic pulse.
    ///
    /// Only NUDGE. AWARE is explicitly silent — a keyboard that taps the user
    /// because their sentence looked tense would be insufferable, and it would
    /// also announce that the draft is being read, which is the opposite of
    /// what an on-device feature should feel like.
    var announcesArrival: Bool { self == .nudge }

    /// How far a combined intensity sits above the *resting* floor, 0...1.
    ///
    /// REST is the zero point of the visible spectrum, not 0.0 — the key is
    /// always "recognizably Unpackd", so anything measured from 0 would treat
    /// the resting sheen as if it were part of the response. Renderers use
    /// this for effects that must be invisible at rest and full at ENGAGED:
    /// the spacebar's shadow lift and the wordmark's tracking.
    ///
    /// Lives here rather than in either renderer because both need it, and a
    /// second copy is how `rest.intensity` gets changed in one place and
    /// silently disagreed with in another.
    static func lift(above intensity: Double) -> Double {
        let floor = rest.intensity
        guard intensity > floor else { return 0 }
        return (intensity - floor) / (1 - floor)
    }
}
