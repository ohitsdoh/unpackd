//
//  FoundationModelsRewriter.swift
//  UnpackdKeyboard
//
//  On-device rewrite via Apple's Foundation Models framework (iOS 26+).
//
//  WHY THIS AND NOT A BUNDLED MODEL
//  A keyboard extension is capped at ~60MB of phys_footprint, and crossing it
//  gets the process jetsam-killed with no crash log — iOS silently swaps the
//  user back to their previous keyboard. Bundling llama.cpp / MLX / Core ML
//  weights is not survivable at that budget once you count KV cache and
//  activation buffers. Foundation Models runs the ~1.2GB model in a *system*
//  process shared across Apple Intelligence, so our footprint barely moves.
//

import Foundation
import FoundationModels

// MARK: - Structured output

/// The shape we force the model to produce.
///
/// Constrained decoding (rather than "reply with JSON") is what keeps a small
/// model from returning prose we then have to parse, and pins the emotion to
/// a value the UI can actually render.
@Generable
struct ReflectionOutput {

    @Guide(description: "The dominant emotion expressed in the user's draft message.")
    var emotion: EmotionOutput

    // Constrained decoding generates the array against a single element guide,
    // so without the contrast instruction below the model returns three
    // near-identical sentences and the pager looks broken.
    @Guide(
        description: "Three distinctly different rewrites of the draft, best first. Each preserves the user's actual grievance and intent — never minimise or erase what they are upset about. They must differ in approach, not just wording: the first direct and plain, the second softer and more open to the other person's side, the third short and matter-of-fact. Do not repeat the same sentence structure or opening words across them.",
        .count(3)
    )
    var rewrites: [RewriteOutput]
}

@Generable
enum EmotionOutput: String {
    case angry, hurt, frustrated, overwhelmed, anxious
}

@Generable
struct RewriteOutput {

    // "No longer than the draft" rather than "two sentences at most": a length
    // ceiling reads as a target to fill, which is how a five-word draft comes
    // back as two sentences of padding. The concrete-nouns clause is the other
    // half of the same problem — see `instructions(forDraftLength:)`.
    @Guide(description: "The rewritten message, in this entry's own distinct approach. First person, owns the speaker's feeling, no blame or accusation, no therapy jargon. Reuse the concrete nouns and verbs from the draft — never replace a specific complaint with an abstract feeling word. No longer than the draft itself. Sound like the user on a calm day, not like a customer service bot.")
    var text: String

    @Guide(description: "One word describing the tone of this specific rewrite, e.g. Clear, Calm, Open, Direct, Warm. Must differ from the other rewrites' tone labels.")
    var toneLabel: String
}

// MARK: - Engine

@MainActor
final class FoundationModelsRewriter: ReflectionEngine {

    private let model = SystemLanguageModel.default

    /// Which set of instructions a draft needs.
    ///
    /// Instructions are fixed at `LanguageModelSession` init, so this cannot be
    /// decided per-prompt — it has to pick a session. Hence two armed sessions
    /// rather than one. A warmed session has an empty transcript and the model
    /// itself is shared in a system process, so the second one costs us
    /// essentially nothing in footprint.
    ///
    /// The threshold lives here rather than on the enclosing type: a static on
    /// a `@MainActor` class inherits that isolation, which this nonisolated
    /// initializer cannot then reference.
    private enum Variant: CaseIterable {
        case short, long

        /// How long a draft has to be before it stops counting as "short".
        /// Below this the model has so little to condition on that it drifts
        /// to generic output — see `instructions(for:)`.
        static let shortDraftWordCount = 12

        init(wordCount: Int) {
            self = wordCount <= Self.shortDraftWordCount ? .short : .long
        }
    }

    /// Armed, warmed, as-yet-unused sessions waiting for the next reflection.
    /// Never holds a session that has already generated a response.
    private var sessions: [Variant: LanguageModelSession] = [:]

    /// Kept deliberately short. The window is 4096 tokens covering instructions
    /// + transcript + prompt + output, so every token spent here is a token the
    /// user's draft can't use.
    private static let coreInstructions = """
        You help someone rewrite a message they drafted while upset, before they send it.

        Keep their real point intact. Do not soften the substance, apologise on their \
        behalf, or add warmth they did not express. Convert accusation into ownership: \
        "you never responded" becomes "I didn't hear back". Keep it short and plain.

        Never add new facts. Never invent context you were not given.
        """

    /// A short draft needs close to the opposite emphasis from a long one.
    ///
    /// For a long draft, "keep it short and plain" *is* the work. For a
    /// five-word draft that is already true, so the instruction becomes a
    /// licence to say nothing, and with almost no input to condition on the
    /// strongest signal left in context is the guide text itself — the model
    /// returns the generic centroid of "calm, owns the feeling, no blame"
    /// ("I feel unheard and I'd like to talk") no matter what was typed.
    ///
    /// The "could have been written without reading this draft" line is the
    /// operative one: it gives a concrete failure test instead of one more
    /// adjective to average over.
    private static func instructions(for variant: Variant) -> String {
        switch variant {
        case .long:
            return coreInstructions
        case .short:
            return coreInstructions + """


                This draft is very short. Stay close to its exact words — reuse the user's \
                own nouns and verbs. A rewrite that could have been written without reading \
                this draft is a failure. Do not generalise "you never text back" into \
                "I feel unheard"; keep the texting. Match its length: one sentence, not two.
                """
        }
    }

    // MARK: Availability

    var availability: Result<Void, ReflectionUnavailable> {
        switch model.availability {
        case .available:
            return .success(())
        case .unavailable(let reason):
            // These three are genuinely different situations for the user:
            // one is "buy a newer phone", one is "flip a switch", one is "wait".
            switch reason {
            case .deviceNotEligible:
                return .failure(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .failure(.notEnabled)
            case .modelNotReady:
                return .failure(.notReady)
            @unknown default:
                return .failure(.failed("Unavailable"))
            }
        @unknown default:
            return .failure(.failed("Unavailable"))
        }
    }

    // MARK: Prewarm

    /// Call this from `viewDidLoad`, not from the space-hold handler.
    ///
    /// Building a session lazily costs 1-2s of cold start, and it lands exactly
    /// when the user is holding the spacebar waiting for the panel. Paying it at
    /// keyboard launch makes the first hold feel instant.
    ///
    /// Arms one session per `Variant`. The matching one is *consumed* by the
    /// next `reflect`, which then arms a replacement — see
    /// `takeWarmedSession(_:)`. Warming an instance that `reflect` then throws
    /// away would make this method pure cost.
    func prewarm() {
        guard case .success = availability else { return }
        for variant in Variant.allCases where sessions[variant] == nil {
            arm(variant)
        }
    }

    /// Build a session and hint the system to load the model behind it.
    private func arm(_ variant: Variant) {
        let session = LanguageModelSession(instructions: Self.instructions(for: variant))
        sessions[variant] = session
        session.prewarm()
    }

    /// Hand over the warmed session for this variant and immediately arm a
    /// replacement.
    ///
    /// Handing it over rather than reusing it in place is what keeps each
    /// reflection independent: a warmed session has an empty transcript, so
    /// consuming one costs nothing in context window, while reusing the *same*
    /// session across reflections would carry one message's tone into the next.
    private func takeWarmedSession(_ variant: Variant) -> LanguageModelSession {
        defer { arm(variant) }
        return sessions[variant]
            ?? LanguageModelSession(instructions: Self.instructions(for: variant))
    }

    // MARK: Inference

    func reflect(on draft: String) async throws -> Reflection {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReflectionUnavailable.emptyDraft }

        if case .failure(let reason) = availability { throw reason }

        let variant = Variant(wordCount: Self.wordCount(of: trimmed))
        // A fresh session per reflection, taken warm where possible.
        let session = takeWarmedSession(variant)

        // Short drafts run hotter. Little input plus a moderate temperature is
        // exactly the regime where the model falls back to high-probability
        // generic phrasing — there isn't enough conditioning to pull it off the
        // prior. With five words on the table there is also very little to be
        // incoherent about, so the usual risk of raising this is muted.
        let temperature: Double = switch variant {
        case .short: 0.9
        case .long: 0.6
        }

        do {
            // NOTE: `respond`, deliberately not `streamResponse`.
            // Apple's guidance on the extension rate limit is explicit that
            // streaming burns more power and trips the limit sooner. The
            // rewrite is ~30 tokens; streaming buys us nothing here.
            let response = try await session.respond(
                to: "Rewrite this draft message:\n\n\(trimmed)",
                generating: ReflectionOutput.self,
                options: GenerationOptions(temperature: temperature)
            )
            return Self.map(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw ReflectionUnavailable.failed(error.localizedDescription)
        }
    }

    // MARK: Mapping

    /// Whitespace-separated words. Deliberately crude: this only has to pick a
    /// side of a threshold, and `enumerateSubstrings(options: .byWords)` would
    /// be slower for no benefit at this granularity.
    private static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func map(_ output: ReflectionOutput) -> Reflection {
        Reflection(
            detectedEmotion: Emotion(rawValue: output.emotion.rawValue) ?? .frustrated,
            rewrites: output.rewrites.enumerated().map { index, rewrite in
                Rewrite(
                    id: index,
                    text: rewrite.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    toneLabel: rewrite.toneLabel
                )
            }
        )
    }

    /// Classify the failure so the UI can decide between "try again",
    /// "try again later", and "this will never work".
    ///
    /// Exhaustive over all nine cases of `LanguageModelSession.GenerationError`
    /// as documented for iOS 26. `@unknown default` covers future additions
    /// without silently swallowing the ones that exist today — the previous
    /// `default` arm was collapsing four real cases into one generic failure.
    private static func map(_ error: LanguageModelSession.GenerationError) -> ReflectionUnavailable {
        switch error {
        case .exceededContextWindowSize:
            return .tooLong

        case .guardrailViolation:
            // Worth knowing: in app extensions Apple has confirmed the rate
            // limiter surfaces as a *guardrail* error message
            // ("Safety guardrail was triggered after consecutive failures"),
            // so this arm is not purely about unsafe content. If you see this
            // fire on innocuous drafts, you are being throttled, not filtered.
            return .guardrail

        case .rateLimited:
            return .rateLimited

        case .refusal:
            // The model chose not to engage. Not retryable with the same text.
            return .refused

        case .concurrentRequests:
            // Two reflections in flight at once — the user held space again
            // before the first finished. Retrying immediately is correct.
            return .busy

        case .decodingFailure:
            // Structured output didn't conform to ReflectionOutput. Usually
            // transient at temperature 0.6; a retry generally succeeds.
            return .failed("Couldn't read the rewrite. Try again.")

        case .assetsUnavailable:
            return .notReady

        case .unsupportedLanguageOrLocale:
            return .failed("Rewrite doesn't support this language yet.")

        case .unsupportedGuide:
            // A @Guide in ReflectionOutput is invalid. This is our bug, not
            // the user's — it will fail identically every time.
            return .failed("Rewrite is misconfigured.")

        @unknown default:
            return .failed(String(describing: error))
        }
    }
}
