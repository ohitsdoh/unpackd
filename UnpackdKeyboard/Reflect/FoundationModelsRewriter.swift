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

// MARK: - Unpack flow

/// Structured output for one generated question.
///
/// The options are generated in the same call as the prompt, not in a second
/// one. Two calls would double the rate-limit exposure for a screen the user
/// is waiting on, and the options only make sense relative to the question —
/// generating them apart invites a set that does not answer it.
@Generable
struct UnpackQuestionOutput {

    @Guide(description: "A short, open question — at most eight words — that helps the user notice what they actually want from this conversation. Second person. Never diagnose the user, never label their mental state, never ask why they feel something. Ask about what they want to happen or what matters to them, e.g. 'What do you want them to understand?'.")
    var prompt: String

    @Guide(
        description: "Four distinct answers the user might give, each written in FIRST PERSON as the user's own voice, e.g. 'I want to feel heard'. At most eight words each. They must be genuinely different intentions, not rewordings of one another, and must fit this specific conversation — reuse the concrete subject matter of the draft rather than generic feelings. Never include an option that blames the other person.",
        .count(4)
    )
    var options: [String]
}

/// Structured output for the reflection card.
@Generable
struct UnpackInsightOutput {

    @Guide(description: "One sentence, at most twenty words, starting with 'It sounds like you want' or similar, that reflects back what the user is trying to achieve in this conversation. Describe the MESSAGE and their intent, never the person — no diagnosis, no personality claims, no advice, no therapy jargon. Use what they selected, in their own terms.")
    var text: String
}

/// Structured output for a generated message.
///
/// One rewrite, not three: by this point the user has told us what they mean,
/// so a pager of alternatives is the wrong affordance — the deck replaces it
/// with an explicit "Try another" that says *how* the next one should differ.
@Generable
struct ExpressionOutput {

    @Guide(description: "The message the user could send, in first person, in their own natural voice. It must say what they told you they want to say. Own the speaker's feeling, no blame or accusation, no therapy jargon, no new facts. Keep the concrete subject matter of the original draft. At most three sentences.")
    var text: String

    @Guide(description: "One word describing this message's tone, e.g. Clear, Calm, Open, Direct, Warm.")
    var toneLabel: String
}

extension FoundationModelsRewriter {

    /// Instructions for the question and insight steps.
    ///
    /// A different job from `coreInstructions`, which is about rewriting. This
    /// half of the flow does not produce any message at all — it helps the
    /// user notice their own intent — and giving it the rewrite instructions
    /// made it answer questions with rewritten drafts.
    ///
    /// The "never diagnose" line is load-bearing, not decoration: the deck's
    /// rule is "context, not diagnosis", and a 3B model asked to be insightful
    /// about an upset person will reach for amateur psychology unless told
    /// plainly not to.
    static var unpackInstructions: String {
        """
        You help someone notice what they actually want to say, before they send \
        an angry message. You do not rewrite anything here.

        Never diagnose, label, or psychoanalyse the user. Never give advice. \
        Never take the other person's side or defend them. Describe what the \
        user wants from the conversation, in their own plain words.

        Stay concrete. Use the actual subject of their draft, not abstract \
        feeling words. Never invent context you were not given.
        """
    }

    /// One prompt body shared by the question and insight calls.
    ///
    /// Both need the same picture — the draft plus the path so far — and
    /// building it in one place keeps the two calls consistent as the flow
    /// grows. Kept terse: the 4096-token window covers instructions, prompt
    /// and output together.
    static func contextPrompt(_ context: UnpackContext) -> String {
        var parts = ["Their draft message:\n\(context.draft)"]
        if !context.promptSummary.isEmpty {
            parts.append("What they have told you so far:\n\(context.promptSummary)")
        }
        return parts.joined(separator: "\n\n")
    }

    func question(for context: UnpackContext) async throws -> UnpackQuestion {
        if case .failure(let reason) = availability { throw reason }

        // A fresh, unwarmed session: the unpack steps use different
        // instructions from the rewrite, so they cannot draw on the sessions
        // `prewarm` armed. Building one costs the cold start only on the
        // first question of a flow — the model itself is already resident
        // because `prewarm` loaded it at viewDidLoad.
        let session = LanguageModelSession(instructions: Self.unpackInstructions)

        let ask = context.depth == 0
            ? "Ask what they want the other person to understand."
            : "Ask a FOLLOW-UP question that builds on what they already told you. Do not repeat a question they have answered."

        do {
            let response = try await session.respond(
                to: "\(Self.contextPrompt(context))\n\n\(ask)",
                generating: UnpackQuestionOutput.self,
                // Higher than the rewrite path: these options should feel
                // varied rather than converge on the safest phrasing, and a
                // tapped option is lower-stakes than a message that gets sent.
                options: GenerationOptions(temperature: 0.8)
            )
            return Self.map(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw ReflectionUnavailable.failed(error.localizedDescription)
        }
    }

    func insight(for context: UnpackContext) async throws -> UnpackInsight {
        if case .failure(let reason) = availability { throw reason }

        let session = LanguageModelSession(instructions: Self.unpackInstructions)

        do {
            let response = try await session.respond(
                to: """
                    \(Self.contextPrompt(context))

                    Reflect back, in one sentence, what they want to say.
                    """,
                generating: UnpackInsightOutput.self,
                // Low: this sentence is handed to the user as "here is what I
                // heard", so it needs to be faithful rather than interesting.
                options: GenerationOptions(temperature: 0.4)
            )
            return UnpackInsight(
                text: response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw ReflectionUnavailable.failed(error.localizedDescription)
        }
    }

    func express(
        for context: UnpackContext,
        insight: UnpackInsight,
        style: ExpressionStyle?
    ) async throws -> Reflection {
        if case .failure(let reason) = availability { throw reason }

        // The rewrite instructions, not the unpack ones: this step *is*
        // writing a message, so it wants the "convert accusation into
        // ownership, add no new facts" rules. Taken warm — a `.long` session
        // is armed and this prompt always carries the accumulated context, so
        // it is never the short-draft regime.
        let session = takeWarmedSession(.long)

        var prompt = """
            \(Self.contextPrompt(context))

            What they want to say:
            \(insight.text)

            Write the message they could send.
            """
        if let style {
            // Appended rather than folded into the instructions: instructions
            // are fixed at session init, and "Try another" has to change the
            // ask without rebuilding the session it was warmed on.
            prompt += "\n\n\(style.instruction)"
        }

        do {
            let response = try await session.respond(
                to: prompt,
                generating: ExpressionOutput.self,
                options: GenerationOptions(temperature: 0.7)
            )
            let output = response.content
            return Reflection(
                detectedEmotion: .frustrated,
                rewrites: [
                    Rewrite(
                        id: 0,
                        text: output.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        toneLabel: output.toneLabel
                    )
                ]
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw ReflectionUnavailable.failed(error.localizedDescription)
        }
    }

    private static func map(_ output: UnpackQuestionOutput) -> UnpackQuestion {
        // Trimmed and de-duplicated before the clamp: constrained decoding
        // hits the `.count` guide reliably but says nothing about the entries
        // being distinct, and two identical options read as a bug.
        var seen = Set<String>()
        let options = output.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(UnpackQuestion.maxOptions)

        return UnpackQuestion(
            prompt: output.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            options: Array(options)
        )
    }
}
