//
//  ReflectionEngine.swift
//  UnpackdKeyboard
//
//  The abstraction between the keyboard UI and whatever produces a rewrite.
//  Everything above this line is UI; everything below is inference.
//

import Foundation

/// A tone the model can detect in the drafted message.
///
/// A closed set on purpose: constrained decoding (`@Guide`) against a closed
/// enum is what stops a 3B model from inventing a sixth emotion the badge on
/// the review screen can't render.
enum Emotion: String, Codable {
    case angry
    case hurt
    case frustrated
    case overwhelmed
    case anxious

    var label: String {
        switch self {
        case .angry: "Angry"
        case .hurt: "Hurt"
        case .frustrated: "Frustrated"
        case .overwhelmed: "Overwhelmed"
        case .anxious: "Anxious"
        }
    }
}

/// The result of a reflection pass over the user's draft.
struct Reflection: Equatable {
    /// The tone detected in the original draft.
    let detectedEmotion: Emotion
    /// Rewritten alternatives, best first. The panel pages through these.
    let rewrites: [Rewrite]
}

struct Rewrite: Equatable, Identifiable {
    let id: Int
    /// The rewritten message, ready to insert.
    let text: String
    /// A one-word badge shown under the rewrite ("Clear", "Calm", ...).
    let toneLabel: String
}

/// Why a reflection could not be produced. Each case maps to a *different*
/// user-facing message — collapsing these into one "something went wrong"
/// is the single most common way this feature feels broken.
enum ReflectionUnavailable: Error, Equatable {
    /// Device has no Apple Intelligence (pre-A17 Pro).
    case deviceNotEligible
    /// User has Apple Intelligence switched off in Settings.
    case notEnabled
    /// Model is still downloading.
    case notReady
    /// The system throttled us. Recoverable — worth a retry later.
    case rateLimited
    /// The draft tripped a safety guardrail.
    case guardrail
    /// The model declined to answer. Distinct from `guardrail`: the content
    /// passed the filter, the model chose not to engage with it.
    case refused
    /// A request was already in flight. Transient — the user double-triggered.
    case busy
    /// Draft (plus instructions) exceeded the context window.
    case tooLong
    /// Nothing to work with.
    case emptyDraft
    /// Anything else.
    case failed(String)
}

extension ReflectionUnavailable {

    /// Whether trying the same draft again could plausibly succeed.
    ///
    /// This is a property of the failure, not of the UI, so it lives with the
    /// type: throttling and transient decode failures clear on their own, while
    /// an ineligible device never will. Retrying the permanent ones just burns
    /// battery on a request that cannot succeed.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .guardrail, .notReady, .busy, .failed: true
        // .refused won't change on retry with the same draft.
        case .deviceNotEligible, .notEnabled, .tooLong, .emptyDraft, .refused: false
        }
    }
}

/// Anything that can turn a raw draft into a reflection.
///
/// Kept as a protocol so the panel can be developed and previewed against
/// `StubReflectionEngine` without an Apple Intelligence device in hand —
/// the simulator cannot run Foundation Models.
///
/// `@MainActor` because implementations hold mutable, non-Sendable state (a
/// `LanguageModelSession`) and are driven from `ReflectSession`, which is also
/// main-actor isolated. Under Swift 6 an unisolated protocol here means the
/// engine crosses an isolation boundary every call. `reflect` is `async`, so
/// isolating it costs nothing — the await suspends rather than blocking.
@MainActor
protocol ReflectionEngine: AnyObject {
    /// Whether a rewrite can be attempted at all right now.
    var availability: Result<Void, ReflectionUnavailable> { get }

    /// Warm the model so the first hold-space doesn't eat the 1-2s cold start.
    func prewarm()

    /// Produce a reflection for a draft.
    ///
    /// The emotion comes back from the model's own reading of the draft. There
    /// is deliberately no self-report input: asking the user to label their
    /// feeling before they've been helped is friction, and feeding that label
    /// into the same call that reports the emotion would only make the model
    /// echo it back.
    func reflect(on draft: String) async throws -> Reflection

    /// Generate the next question in the unpack flow.
    ///
    /// The question and its options are both generated from `context` — the
    /// draft plus every answer so far — which is what makes the second
    /// question follow from the first rather than being a fixed list. See
    /// `UnpackQuestion` for why the *shape* stays static while the content
    /// does not.
    func question(for context: UnpackContext) async throws -> UnpackQuestion

    /// Read back what the user seems to be trying to say.
    ///
    /// Produces the "It sounds like you want to..." card. Deliberately
    /// separate from `reflect`: this happens *before* any language is
    /// generated, and the user can choose to go deeper instead of accepting
    /// it, in which case no rewrite is ever requested.
    func insight(for context: UnpackContext) async throws -> UnpackInsight

    /// Turn everything unpacked so far into a message they could send.
    ///
    /// Distinct from `reflect(on:)`, which only sees the raw draft. This is
    /// the "Help me say it" path and is conditioned on the user's stated
    /// intent, so it can say what they meant rather than a politer version of
    /// what they typed.
    func express(for context: UnpackContext, insight: UnpackInsight, style: ExpressionStyle?) async throws -> Reflection
}

/// How the user asked for the next attempt to differ ("Try another").
///
/// The deck is firm that this changes *expression, not intention*: the user
/// has already told us what they mean, and a re-roll that quietly reinterprets
/// that would undo the whole flow. So this is a closed set of adjustments to
/// delivery, never to substance.
enum ExpressionStyle: String, CaseIterable, Identifiable {
    case softer
    case moreDirect
    case shorter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .softer: "Softer"
        case .moreDirect: "More direct"
        case .shorter: "Shorter"
        }
    }

    /// The instruction handed to the model.
    var instruction: String {
        switch self {
        case .softer:
            "Say the same thing more gently. Same meaning, warmer delivery."
        case .moreDirect:
            "Say the same thing more plainly and directly. Do not soften it."
        case .shorter:
            "Say the same thing in fewer words. Cut, do not rephrase."
        }
    }
}

// MARK: - Preview / simulator stub

/// Returns canned data so the UI can be built without an eligible device.
@MainActor
final class StubReflectionEngine: ReflectionEngine {
    var availability: Result<Void, ReflectionUnavailable> { .success(()) }
    func prewarm() {}

    func question(for context: UnpackContext) async throws -> UnpackQuestion {
        try? await Task.sleep(for: .milliseconds(500))
        // Two different canned questions so the stub exercises the flow's
        // second step rather than repeating the first.
        if context.depth == 0 {
            return UnpackQuestion(
                prompt: "What do you want them to understand?",
                options: [
                    "I need some space",
                    "I want to feel heard",
                    "I don't want this to escalate",
                    "I'm trying to explain my perspective"
                ]
            )
        }
        return UnpackQuestion(
            prompt: "What feels most important?",
            options: [
                "They understand why I'm upset",
                "We talk when we're both calmer",
                "I say this without making it worse",
                "That I still care about this"
            ]
        )
    }

    func insight(for context: UnpackContext) async throws -> UnpackInsight {
        try? await Task.sleep(for: .milliseconds(500))
        return UnpackInsight(
            text: "It sounds like you want to be heard without making this bigger."
        )
    }

    func express(for context: UnpackContext, insight: UnpackInsight, style: ExpressionStyle?) async throws -> Reflection {
        try? await Task.sleep(for: .milliseconds(600))
        let text = switch style {
        case .softer:
            "I'd really like to talk about this, but not right now. I need a little space so we can come back to it when we're both in a better headspace."
        case .moreDirect:
            "I want to talk about this, just not right now. I need some space first."
        case .shorter:
            "Can we come back to this later? I need a little space."
        case nil:
            "Can we come back to this a little later? I do want to talk about it — I just need a little space so we can have the conversation when we're both calmer."
        }
        return Reflection(
            detectedEmotion: .frustrated,
            rewrites: [.init(id: 0, text: text, toneLabel: "Clear")]
        )
    }

    func reflect(on draft: String) async throws -> Reflection {
        try? await Task.sleep(for: .milliseconds(600))
        return Reflection(
            detectedEmotion: .angry,
            rewrites: [
                .init(id: 0, text: "I felt hurt when I didn't hear back. Can we talk?", toneLabel: "Clear"),
                .init(id: 1, text: "I've been waiting to hear from you and it's been weighing on me.", toneLabel: "Calm"),
                .init(id: 2, text: "Not hearing back left me unsure where we stand. Can we find a time?", toneLabel: "Open")
            ]
        )
    }
}
