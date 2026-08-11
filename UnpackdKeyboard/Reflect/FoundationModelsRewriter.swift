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

    @Guide(
        description: "Rewritten versions of the draft, best first. Each preserves the user's actual grievance and intent — never minimise or erase what they are upset about.",
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

    @Guide(description: "The rewritten message. First person, owns the speaker's feeling, no blame or accusation, no therapy jargon. Two sentences at most. Sound like the user on a calm day, not like a customer service bot.")
    var text: String

    @Guide(description: "One word describing the tone of this rewrite, e.g. Clear, Calm, Open, Direct, Warm.")
    var toneLabel: String
}

// MARK: - Engine

@MainActor
final class FoundationModelsRewriter: ReflectionEngine {

    private let model = SystemLanguageModel.default
    /// An armed, warmed, as-yet-unused session waiting for the next reflection.
    /// Never holds a session that has already generated a response.
    private var session: LanguageModelSession?

    /// Kept deliberately short. The window is 4096 tokens covering instructions
    /// + transcript + prompt + output, so every token spent here is a token the
    /// user's draft can't use.
    private static let instructions = """
        You help someone rewrite a message they drafted while upset, before they send it.

        Keep their real point intact. Do not soften the substance, apologise on their \
        behalf, or add warmth they did not express. Convert accusation into ownership: \
        "you never responded" becomes "I didn't hear back". Keep it short and plain.

        Never add new facts. Never invent context you were not given.
        """

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
    /// The warmed session is *consumed* by the next `reflect`, which then arms
    /// a replacement — see `takeWarmedSession()`. Warming an instance that
    /// `reflect` then throws away would make this method pure cost.
    func prewarm() {
        guard case .success = availability else { return }
        guard session == nil else { return }
        arm()
    }

    /// Build a session and hint the system to load the model behind it.
    private func arm() {
        let session = LanguageModelSession(instructions: Self.instructions)
        self.session = session
        session.prewarm()
    }

    /// Hand over the warmed session and immediately arm a replacement.
    ///
    /// Handing it over rather than reusing it in place is what keeps each
    /// reflection independent: a warmed session has an empty transcript, so
    /// consuming one costs nothing in context window, while reusing the *same*
    /// session across reflections would carry one message's tone into the next.
    private func takeWarmedSession() -> LanguageModelSession {
        defer { arm() }
        return session ?? LanguageModelSession(instructions: Self.instructions)
    }

    // MARK: Inference

    func reflect(on draft: String, selfReported: Emotion?) async throws -> Reflection {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReflectionUnavailable.emptyDraft }

        if case .failure(let reason) = availability { throw reason }

        // A fresh session per reflection, taken warm where possible.
        let session = takeWarmedSession()

        do {
            // NOTE: `respond`, deliberately not `streamResponse`.
            // Apple's guidance on the extension rate limit is explicit that
            // streaming burns more power and trips the limit sooner. The
            // rewrite is ~30 tokens; streaming buys us nothing here.
            // The self-report, when given, is context — not an override. The
            // model still returns its own read of the draft, because the two
            // disagreeing is often the useful part ("you said frustrated, this
            // reads as hurt").
            var prompt = "Rewrite this draft message:\n\n\(trimmed)"
            if let selfReported {
                prompt += "\n\nThe writer says they are feeling \(selfReported.label.lowercased())."
            }

            let response = try await session.respond(
                to: prompt,
                generating: ReflectionOutput.self,
                options: GenerationOptions(temperature: 0.6)
            )
            return Self.map(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw ReflectionUnavailable.failed(error.localizedDescription)
        }
    }

    // MARK: Mapping

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
