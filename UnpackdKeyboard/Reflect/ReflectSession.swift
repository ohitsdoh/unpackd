//
//  ReflectSession.swift
//  UnpackdKeyboard
//
//  The state machine behind the reflect panel.
//

import Foundation
import Observation

/// Timings for the hold gesture.
///
/// Deliberately outside `ReflectSession`, which is `@MainActor`-isolated: the
/// display link computing progress reads `holdDuration` from a nonisolated
/// context, and static constants on an isolated type inherit that isolation.
/// These are plain numbers with no state to protect, so the isolation bought
/// nothing and only made them unreachable.
enum HoldTiming {

    /// Wall-clock duration of the hold, in seconds, that `holdProgress` spans.
    ///
    /// This is the ACTIVATE time from the design, not the threshold time: the
    /// ramp fills completely at the moment the gesture is confirmed. Threshold
    /// is a fraction along the way, below.
    /// Measured: with this at 0.70 the full gesture ran ~1.0s of transition
    /// before anything appeared, and the design budgets 700-1000ms for the
    /// *whole* interaction. 0.52 keeps a deliberate hold — comfortably longer
    /// than an accidental press — while leaving room for the open to play
    /// inside the budget rather than after it.
    static let holdDuration: TimeInterval = 0.52

    /// Where 03 THRESHOLD sits on that 0...1 ramp (~450ms of 700ms). This is
    /// the *haptic* boundary — the "keep holding" beat.
    static let thresholdFraction: Double = 0.34 / 0.52

    /// Where the visible response starts (~180ms of 700ms).
    ///
    /// SEPARATE FROM `thresholdFraction`, DELIBERATELY
    /// These were the same value, and that left the visuals ~250ms to play —
    /// so a hold looked like it did nothing. The two boundaries answer
    /// different questions:
    ///
    ///   - `thresholdFraction` is when Unpackd *commits* to the gesture, and
    ///     therefore when it is willing to spend a haptic on it. Firing that
    ///     early would tap the user for an ordinary space.
    ///   - `visibleFraction` is when it is safe to start *drawing*. A visual
    ///     can begin much sooner because it costs nothing if abandoned: the
    ///     contours simply fade back out, and the design's own stages 01/02
    ///     are visual-only changes with no haptics.
    ///
    /// 180ms still clears an ordinary tap (~80ms) with margin, so a normal
    /// space stays completely quiet.
    static let visibleFraction: Double = 0.14 / 0.52
}

@Observable
@MainActor
final class ReflectSession {

    enum Phase: Equatable {
        /// Panel closed, normal typing.
        case idle
        /// Panel open on the Breathe / Reflect / Rewrite / Save choice.
        case choosing
        /// Breathing animation running.
        case breathing
        /// Waiting on the model.
        case thinking
        /// Rewrites ready.
        case reviewing(Reflection)
        /// Could not produce a rewrite.
        case unavailable(ReflectionUnavailable)
    }

    private(set) var phase: Phase = .idle
    private(set) var draft: String = ""

    /// How far through the press-and-hold gesture we are, 0...1.
    ///
    /// WHY THIS EXISTS SEPARATELY FROM `phase`
    /// `phase` only changes at the moment the panel opens, but the mockup's
    /// stages 03 and 04 both happen *before* that — the ripple, the
    /// iridescence ramp and the first haptic all have to be driven by a value
    /// that moves continuously while the finger is still down and nothing has
    /// been committed to. Folding this into `Phase` would mean a case that
    /// changes 60 times a second, which would rebuild the panel's whole view
    /// tree on every tick.
    ///
    /// Resets to 0 the instant the finger lifts early, so an abandoned hold
    /// visibly rewinds rather than freezing part-lit.
    private(set) var holdProgress: Double = 0

    /// The last stage whose haptic has already fired, so a stage cannot fire
    /// twice as `holdProgress` jitters across its boundary.
    private var lastHapticStage: HoldStage = .none

    /// Named points on the way to opening, matching the mockup's numbering.
    enum HoldStage: Int, Comparable {
        case none = 0
        /// 03 THRESHOLD (~450ms): intent recognised, first ripple, light haptic.
        case threshold = 1
        /// 04 ACTIVATE (~700ms): full iridescence, second ring, firmer haptic.
        case activate = 2

        static func < (a: HoldStage, b: HoldStage) -> Bool { a.rawValue < b.rawValue }
    }

    /// Advance the hold. Returns the stage that was newly *entered* by this
    /// update, or nil if no boundary was crossed — the caller uses that to
    /// fire exactly one haptic per stage.
    @discardableResult
    func updateHold(progress: Double) -> HoldStage? {
        holdProgress = min(max(progress, 0), 1)

        let stage: HoldStage =
            if holdProgress >= 1 { .activate }
            else if holdProgress >= HoldTiming.thresholdFraction { .threshold }
            else { .none }

        // The display link runs at ~60fps, so each stage is crossed on many
        // consecutive frames; without this every frame past the threshold
        // would fire another haptic.
        guard stage > lastHapticStage else { return nil }
        lastHapticStage = stage
        return stage
    }

    /// Finger lifted, or the gesture was otherwise abandoned.
    func cancelHold() {
        holdProgress = 0
        lastHapticStage = .none
    }

    // MARK: - Ambient presence

    /// Where the spacebar rests when nobody is holding it. See SpacebarPresence.
    private(set) var presence: SpacebarPresence = .rest

    /// Combined intensity for rendering, 0...1.
    ///
    /// The hold lifts the key from wherever it was resting up to full, rather
    /// than restarting from REST — so a hold begun at NUDGE has less distance
    /// to travel and reads as the key meeting the user halfway, which is the
    /// point of having a spectrum at all.
    var spacebarIntensity: Double {
        let base = presence.intensity
        return base + (1 - base) * visibleHoldProgress
    }

    /// `holdProgress`, but zero until the hold crosses THRESHOLD.
    ///
    /// Every *visible* response to the hold is driven off this rather than off
    /// the raw progress. An ordinary space tap is ~80ms — well short of the
    /// 450ms threshold, but long enough that a value ramping from touch-down
    /// makes the key visibly flare and drop back on every single space. The
    /// design reserves all feedback for after the threshold ("Unpackd
    /// recognizes intentional hold"); before that, typing just continues.
    ///
    /// The raw `holdProgress` is still what the haptic stages compare against,
    /// so the timing of the two beats is unaffected.
    var visibleHoldProgress: Double {
        let start = HoldTiming.visibleFraction
        guard holdProgress > start else { return 0 }
        return (holdProgress - start) / (1 - start)
    }

    /// How much ambient drift to apply. Suppressed while a hold is in progress:
    /// the ripple and the saturation ramp are already carrying that moment, and
    /// a slow ambient wander underneath them just reads as instability.
    var spacebarDrift: Double {
        presence.drift * (1 - visibleHoldProgress)
    }

    /// Move the spacebar to a new ambient level.
    ///
    /// Returns true if arriving here should fire the single subtle pulse that
    /// 03 NUDGE calls for. Only ever fires on the way *up*: sliding back down
    /// to REST as a draft cools off is meant to go unnoticed.
    @discardableResult
    func setPresence(_ next: SpacebarPresence) -> Bool {
        guard next != presence else { return false }
        let rising = next > presence
        presence = next
        return rising && next.announcesArrival
    }

    /// Which rewrite the user is currently looking at.
    var selectedRewrite: Int = 0

    private let engine: ReflectionEngine
    private var task: Task<Void, Never>?

    init(engine: ReflectionEngine) {
        self.engine = engine
    }

    var isOpen: Bool { phase != .idle }

    // MARK: - Entry

    /// Open the panel for the current draft.
    func begin(draft: String) {
        self.draft = draft
        self.selectedRewrite = 0
        // The hold has done its job; the panel's own animation takes over from
        // here. Leaving this lit would keep the spacebar at full iridescence
        // underneath an open panel.
        cancelHold()
        // The draft that raised the presence is about to be dealt with, so the
        // key returns to rest rather than still nudging about a message the
        // user has now stopped to look at.
        presence = .rest
        // Availability is checked up front rather than after the user picks
        // "Rewrite" — offering an action that is going to fail is worse than
        // not offering it.
        if case .failure(let reason) = engine.availability {
            phase = .unavailable(reason)
        } else {
            phase = .choosing
        }
        #if DEBUG
        print("[Unpackd] begin -> phase=\(phase) draftLen=\(draft.count)")
        #endif
    }

    func beginBreathe() {
        draft = ""
        selectedRewrite = 0
        phase = .breathing
    }

    func beginRewrite(draft: String) {
        begin(draft: draft)
        guard case .choosing = phase else { return }
        rewrite()
    }

    func dismiss() {
        task?.cancel()
        task = nil
        phase = .idle
        cancelHold()
    }

    // MARK: - Actions

    func breathe() {
        phase = .breathing
    }

    func rewrite() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .unavailable(.emptyDraft)
            return
        }
        phase = .thinking
        task?.cancel()
        // `[weak self]`: cancelling does not abort an in-flight `respond` — the
        // model call runs to completion regardless. A strong capture would pin
        // this session, and through it the engine, for the whole of an
        // abandoned inference, which is exactly the moment footprint is
        // highest and the user has already dismissed the panel.
        task = Task { [weak self, engine, draft] in
            let outcome: Phase
            do {
                let reflection = try await engine.reflect(on: draft)
                outcome = .reviewing(reflection)
            } catch let reason as ReflectionUnavailable {
                outcome = .unavailable(reason)
            } catch {
                outcome = .unavailable(.failed(error.localizedDescription))
            }
            guard let self, !Task.isCancelled else { return }
            phase = outcome
        }
    }

    var currentRewriteText: String? {
        guard case .reviewing(let reflection) = phase else { return nil }
        guard reflection.rewrites.indices.contains(selectedRewrite) else { return nil }
        return reflection.rewrites[selectedRewrite].text
    }
}

// User-facing copy for these failures lives in UI/ReflectionUnavailable+Copy.swift;
// retry semantics live with the type in Reflect/ReflectionEngine.swift.
