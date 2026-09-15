//
//  ReflectSession.swift
//  UnpackdKeyboard
//
//  The state machine behind the reflect panel.
//

import Foundation
import os
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
        /// Panel open, deliberately empty. "Create space." — see `settling`.
        case settling
        /// Panel open on the Unpack this / Rewrite / Unpack later choice.
        case choosing
        /// Breathing animation running.
        case breathing
        /// Waiting on the model.
        case thinking
        /// A generated question, waiting for the user to tap an answer.
        case asking(UnpackQuestion)
        /// The user chose "Something else..." and is typing their own answer.
        case composing(UnpackQuestion)
        /// The "It sounds like you want to..." card.
        case reflecting(UnpackInsight)
        /// Choosing how the next expression should differ ("Try another").
        case adjusting
        /// A generated message, with Use this / Try another / Edit.
        case expressing(Reflection)
        /// Editing a generated message in place before using it.
        ///
        /// Carries NO payload: the live text is `editedMessage`, which the
        /// editor is bound to. A `case editing(String)` would be a second
        /// apparent home for one string, frozen at the moment the editor
        /// opened — so the next person to bind it would silently read the
        /// pre-edit text.
        case editing
        /// Rewrites ready.
        case reviewing(Reflection)
        /// The moment was saved and the panel is about to close.
        case saved
        /// One of the user's own saved thoughts, from "Remember".
        ///
        /// Carries the thought rather than an index so the view never has to
        /// reach back into the session to resolve what it is showing — and so
        /// an empty list is representable as a distinct case below rather than
        /// as an out-of-range index.
        case remembering(RememberedThought)
        /// "Remember" was opened with nothing saved yet.
        case nothingRemembered
        /// Could not produce a rewrite.
        case unavailable(ReflectionUnavailable)
    }

    /// How long the panel stays deliberately empty before offering anything.
    ///
    /// The design brief's rule is "don't fill the space the instant we create
    /// it": holding the spacebar is a request for a pause, and a panel that
    /// arrives already asking a question has given the user a new decision
    /// instead of a moment. The deck budgets 600-800ms for this.
    ///
    /// It is a real cost, so it is spent once — only on the way *in* from a
    /// hold. Every later screen in the flow appears immediately.
    static let settleDuration: Duration = .milliseconds(700)

    private(set) var phase: Phase = .idle
    /// The draft this moment is about.
    ///
    /// DERIVED, NOT STORED.
    /// This was a stored property set alongside `context.draft` from the same
    /// argument, and the two then drifted: `beginBreathe` cleared one,
    /// `dismiss` cleared the other. Two names for one string, with nothing in
    /// the type system requiring them to agree, is how a rewrite ends up
    /// running against a draft the panel is no longer showing. `context` owns
    /// it; everything else reads through here.
    var draft: String { context.draft }

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

    /// Everything the user has told us during this unpack, accumulated.
    /// Rebuilt on every `begin` so one moment never leaks into the next.
    private(set) var context = UnpackContext(draft: "")

    /// The insight currently on screen, kept so "Keep unpacking" and
    /// "Try another" can both refer back to it without re-deriving it.
    private var currentInsight: UnpackInsight?

    /// What the user typed under "Something else...".
    /// Bound directly by the composer's text field.
    var composedAnswer: String = ""

    /// The message being edited in place, bound by the editor's text field.
    var editedMessage: String = ""

    /// How many questions the flow asks before offering a reflection.
    ///
    /// Two by default, per the deck ("Two questions by default. Tap, don't
    /// type."). Each question is a model call the user waits on, and a third
    /// turns a pause into an interview — "Keep unpacking" exists for anyone
    /// who actually wants to go deeper, and is their choice rather than ours.
    static let defaultQuestionCount = 2

    /// How many answers the flow is currently waiting for before it reflects.
    ///
    /// A MOVING TARGET, NOT A CONSTANT COMPARISON.
    /// This started as `depth >= defaultQuestionCount`, which quietly broke
    /// "Keep unpacking": by the time that button exists the user has already
    /// answered two questions, so the extra question it asked came back, hit
    /// the same already-true condition, and bounced straight to a new insight
    /// — the deeper answer was collected but the flow could never go deeper
    /// than one extra step, and a second "Keep unpacking" behaved identically
    /// to the first.
    ///
    /// Raising the target as each extra question is asked keeps the rule
    /// ("reflect once you have answered everything asked of you") true at any
    /// depth, so the flow can go as deep as the user wants to take it.
    private var questionsWanted = ReflectSession.defaultQuestionCount

    private let engine: ReflectionEngine
    private var task: Task<Void, Never>?

    init(engine: ReflectionEngine) {
        self.engine = engine
    }

    var isOpen: Bool { phase != .idle }

    /// Open the panel on `phase`, clearing the previous moment first.
    ///
    /// The practice keys (Breathe, Remember) each used to do this by hand and
    /// each did a different subset — one cleared `selectedRewrite`, the other
    /// cleared nothing, and both repeated `presence = .rest`. Routing them
    /// through one opener means a new practice cannot forget a step, and the
    /// reason presence drops is written once: the user has stopped to deal
    /// with the moment, so the key must not still be nudging about it
    /// underneath an open panel, nor resume the instant it closes.
    private func openPanel(at phase: Phase, draft: String) {
        resetFlowState(for: draft)
        cancelHold()
        presence = .rest
        self.phase = phase
    }

    /// Return every piece of per-moment state to its starting value.
    ///
    /// ONE LIST, NOT FOUR.
    /// `begin`, `beginBreathe`, `remember` and `dismiss` each used to clear a
    /// different subset, and they had already drifted: `begin` cleared
    /// `lastStep` and `selectedRewrite` but left `composedAnswer`,
    /// `editedMessage` and the loaded thoughts behind, while `dismiss` cleared
    /// those and left the other two. Either omission leaks one moment's state
    /// into the next — a half-typed "Something else…" answer reappearing
    /// under a different draft, say.
    ///
    /// Add new per-moment state HERE, never at a call site: every entry point
    /// reaches this through `openPanel`, so this list is the only thing that
    /// has to be complete.
    private func resetFlowState(for draft: String) {
        context = UnpackContext(draft: draft)
        questionsWanted = Self.defaultQuestionCount
        currentInsight = nil
        lastStep = .rewrite
        selectedRewrite = 0
        composedAnswer = ""
        editedMessage = ""
        thoughts = []
        thoughtIndex = 0
    }

    // MARK: - Entry

    /// Open the panel for the current draft.
    ///
    /// Enters `.settling` — deliberately empty — and only offers the actions
    /// once `settleDuration` has passed. See that constant for why the pause
    /// is the feature rather than latency to be optimised away.
    func begin(draft: String) {
        // Availability is checked up front rather than after the user picks
        // "Rewrite" — offering an action that is going to fail is worse than
        // not offering it.
        if case .failure(let reason) = engine.availability {
            openPanel(at: .unavailable(reason), draft: draft)
        } else {
            openPanel(at: .settling, draft: draft)
            task?.cancel()
            task = Task { [weak self] in
                try? await Task.sleep(for: Self.settleDuration)
                guard let self, !Task.isCancelled else { return }
                // Only advance if nothing else moved us on. A user who tapped
                // through or dismissed during the pause must not be yanked
                // back to the chooser.
                guard case .settling = phase else { return }
                phase = .choosing
            }
        }
        #if DEBUG
        Unpackd.log.debug("""
            begin -> phase=\(String(describing: self.phase), privacy: .public) \
            draftLen=\(draft.count, privacy: .public)
            """)
        #endif
    }

    func beginBreathe() {
        // Opened with an EMPTY draft, deliberately: Breathe is about the
        // moment, not the message, so it carries none of it into the panel.
        openPanel(at: .breathing, draft: "")
    }

    func dismiss() {
        task?.cancel()
        task = nil
        phase = .idle
        resetFlowState(for: "")
        cancelHold()
    }

    // MARK: - Actions

    // MARK: Unpack flow

    /// "Unpack this" — start the guided flow with the first question.
    func unpack() {
        guard !draft.isBlank else {
            phase = .unavailable(.emptyDraft)
            return
        }
        askNextQuestion()
    }

    /// Ask the model for the next question, given everything answered so far.
    private func askNextQuestion() {
        lastStep = .question
        run { [context] engine in
            .asking(try await engine.question(for: context))
        }
    }

    /// The user tapped one of the generated options.
    func answer(_ response: String, to question: UnpackQuestion, isUserWritten: Bool = false) {
        context.answers.append(
            .init(question: question.prompt, response: response, isUserWritten: isUserWritten)
        )
        composedAnswer = ""

        // Reflect once everything asked has been answered; otherwise keep
        // asking. The target moves when the user chooses to go deeper — see
        // `questionsWanted`.
        if context.depth >= questionsWanted {
            reflectBack()
        } else {
            askNextQuestion()
        }
    }

    /// The user chose "Something else..." and wants to type their own answer.
    func composeAnswer(to question: UnpackQuestion) {
        composedAnswer = ""
        phase = .composing(question)
    }

    /// Submit what they typed under "Something else...".
    ///
    /// Marked as the user's own words, which the model is told to treat as
    /// ground truth rather than as one more guess — see `UnpackContext.Answer`.
    func submitComposedAnswer(to question: UnpackQuestion) {
        guard let trimmed = composedAnswer.trimmedOrNil else { return }
        answer(trimmed, to: question, isUserWritten: true)
    }

    /// Produce the "It sounds like you want to..." card.
    private func reflectBack() {
        lastStep = .insight
        // The insight is stashed by `run` when the phase lands, not here —
        // see the note by its cancellation guard.
        run { [context] engine in
            .reflecting(try await engine.insight(for: context))
        }
    }

    /// "Keep unpacking" — one more question before generating any language.
    ///
    /// Raises the target so the answer to this question is not immediately
    /// treated as "everything asked" and bounced back to a reflection. See
    /// `questionsWanted`.
    func keepUnpacking() {
        questionsWanted = context.depth + 1
        askNextQuestion()
    }

    /// "Help me say it" — turn the accumulated context into a message.
    func express(style: ExpressionStyle? = nil) {
        guard let insight = currentInsight else {
            // Without an insight there is nothing to express from. Reflecting
            // first is the correct recovery, not an error: the flow is simply
            // one step behind where the caller thought it was.
            reflectBack()
            return
        }
        lastStep = .expression(style)
        run { [context] engine in
            .expressing(try await engine.express(for: context, insight: insight, style: style))
        }
    }

    /// "Try another" — offer the softer / more direct / shorter choice.
    func adjust() {
        phase = .adjusting
    }

    /// "Edit" — make the generated message editable in place.
    func edit(_ text: String) {
        editedMessage = text
        phase = .editing
    }

    // MARK: Remember

    /// The user's saved thoughts, loaded when Remember opens.
    ///
    /// Read once per open rather than per swipe: these are authored in the
    /// container app, so they cannot change while the keyboard is on screen,
    /// and re-reading `UserDefaults` on every swipe would be pure cost.
    private var thoughts: [RememberedThought] = []

    /// Which thought is showing. Only meaningful while `phase` is
    /// `.remembering`.
    private var thoughtIndex = 0

    /// "Remember" — hold R. Show one of the user's own saved thoughts.
    ///
    /// Deliberately touches neither the draft nor the model. The design's
    /// promise is "nothing is typed or sent, just a moment for you", so this
    /// is the one entry point that reads no draft at all.
    func remember() {
        // Remember reads no draft at all, but the key can still be lit from
        // whatever the user was typing before they reached for it.
        openPanel(at: .nothingRemembered, draft: "")
        // Shuffled, not ordered: Remember is meant to be opened repeatedly,
        // and always leading with the same thought would make the rest of the
        // list invisible in practice.
        thoughts = RememberedThoughtStore.load().shuffled()
        if let first = thoughts.first { phase = .remembering(first) }
    }

    /// "Another" — the next saved thought.
    ///
    /// Wraps rather than stopping at the end: there is no progress to be made
    /// through this list and no reason to strand the user on a last card with
    /// a dead button.
    func anotherThought() {
        guard !thoughts.isEmpty else { return }
        thoughtIndex = (thoughtIndex + 1) % thoughts.count
        phase = .remembering(thoughts[thoughtIndex])
    }

    /// "Unpack later" — save the moment and close, leaving the draft alone.
    ///
    /// The draft is deliberately NOT touched: the promise is that stepping
    /// away costs nothing, so the message stays exactly as it was typed.
    func unpackLater() {
        // `save` drops a moment with nothing in it — see
        // `SavedMoment.isWorthKeeping`. The confirmation below is shown either
        // way: the promise "Unpack later" makes is that stepping away costs
        // nothing, and it has already kept that promise by leaving the draft
        // untouched.
        SavedMomentStore.save(SavedMoment(context: context))
        task?.cancel()
        task = nil
        phase = .saved
    }

    /// What the flow was doing when it failed, so a retry resumes it.
    ///
    /// Without this, the panel's only retry was `rewrite()` — the draft-only
    /// path — so a question that failed on a transient throttle dumped the
    /// user into a plain rewrite of their original text, silently discarding
    /// the answers they had already given. A failure should cost the retry,
    /// not the progress.
    private enum Step: Equatable {
        case question
        case insight
        case expression(ExpressionStyle?)
        /// The draft-only rewrite, reached from "Rewrite" rather than "Unpack".
        case rewrite
    }

    private var lastStep: Step = .rewrite

    /// Re-run whatever failed.
    func retry() {
        switch lastStep {
        case .question: askNextQuestion()
        case .insight: reflectBack()
        case .expression(let style): express(style: style)
        case .rewrite: rewrite()
        }
    }


    /// Run one engine call, showing `.thinking` while it is in flight and
    /// mapping any failure onto `.unavailable`.
    ///
    /// Every step of the flow has exactly this shape, and writing it out four
    /// times is how one of them ends up missing the cancellation check or
    /// swallowing a typed error. `[weak self]` for the same reason `rewrite`
    /// uses it: cancelling does not abort an in-flight `respond`, so a strong
    /// capture would pin the session and its engine for the whole of an
    /// abandoned inference.
    ///
    /// `[weak self]`: cancelling does not abort an in-flight `respond` — the
    /// model call runs to completion regardless. A strong capture would pin
    /// this session, and through it the engine, for the whole of an abandoned
    /// inference, which is exactly the moment footprint is highest and the
    /// user has already dismissed the panel.
    ///
    /// `work` is `@MainActor`-isolated, and has to be: `ReflectionEngine` is
    /// itself main-actor isolated and non-Sendable, so a non-isolated closure
    /// taking one cannot be handed the engine without Swift 6 calling it a
    /// data race ("sending 'engine' risks causing data races"). Isolating the
    /// closure costs nothing — every implementation is an `await` on an
    /// already-isolated method, which suspends rather than blocking.
    private func run(
        _ work: @escaping @MainActor (ReflectionEngine) async throws -> Phase
    ) {
        phase = .thinking
        task?.cancel()
        task = Task { [weak self, engine] in
            let outcome: Phase
            do {
                outcome = try await work(engine)
            } catch let reason as ReflectionUnavailable {
                outcome = .unavailable(reason)
            } catch {
                outcome = .unavailable(.failed(error.localizedDescription))
            }
            guard let self, !Task.isCancelled else { return }
            // Anything a step needs to remember is read back OFF the landed
            // phase here, inside the cancellation guard — never assigned from
            // the work closure, which runs before it and would outlive a
            // dismissal the user has already made.
            if case .reflecting(let insight) = outcome { currentInsight = insight }
            phase = outcome
        }
    }

    func rewrite() {
        lastStep = .rewrite
        guard !draft.isBlank else {
            phase = .unavailable(.emptyDraft)
            return
        }
        run { [draft] engine in
            .reviewing(try await engine.reflect(on: draft))
        }
    }

}

// User-facing copy for these failures lives in UI/ReflectionUnavailable+Copy.swift;
// retry semantics live with the type in Reflect/ReflectionEngine.swift.
