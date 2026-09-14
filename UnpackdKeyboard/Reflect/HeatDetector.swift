//
//  HeatDetector.swift
//  UnpackdKeyboard
//
//  Decides when the spacebar should quietly come to life.
//

import Foundation
import NaturalLanguage
import os

/// Reads a draft and answers one question: does this look like a moment where
/// space might help?
///
/// ML-FIRST, NOT A WORD LIST
/// This was 59 hardcoded phrases across four categories, and it failed the way
/// phrase lists always fail — it only caught wordings somebody had thought to
/// type. Every miss was fixed by adding more strings ("fuck you bro", then
/// "I am so angry", then "fuck u bro"), which is a treadmill, not a design.
///
/// The device ships two on-device classifiers that do the actual work:
///
///   - `NLTagger`'s **Emotion** scheme returns Anger / Disgust / Sadness /
///     Happiness / Surprise for a paragraph. It reads "fuck u bro" and
///     "youre being an idiot honestly" correctly with nothing hardcoded.
///   - The **Sentiment** scheme returns polarity, -1...1.
///
/// Neither is usable alone, and the measurements say why:
///
///   - EMOTION ALONE fires on "fuck yeah dude lets go" (Anger) and on pasted
///     source code (Anger). 5 wrong out of 15.
///   - SENTIMENT ALONE scores anger neutral — "You always do this. You never
///     once considered how it affects me." is exactly 0.00 — while rating
///     ordinary logistics negative ("dinner tomorrow?" is -0.60).
///
/// Together, plus three cheap structural checks that involve no vocabulary,
/// they score 16/17. The four phrases left in `positiveProfanity` exist for one
/// specific failure the models cannot resolve; see the note there.
///
/// WHY NOT THE LANGUAGE MODEL
/// Foundation Models would be more accurate again and is the wrong tool:
///   1. COST. This runs on every keystroke burst. A model call is ~1-2s, holds
///      a session, and would burn the extension's undocumented rate limit on a
///      decision about gradient saturation.
///   2. TIMING. The nudge has to appear *while* the user is typing. A verdict
///      that arrives 2s late is about a sentence they already finished.
///   3. SCOPE. The model's job is the rewrite — the part needing judgement.
///
/// Tuned to be *shy*: the design says "never disruptive", and a false nudge on
/// an ordinary message is far worse than missing a heated one. The user can
/// always hold space without being asked.
///
/// EVERYTHING HERE STAYS ON THE DEVICE
/// This reads what the user types at their worst moments. It keeps no history,
/// writes nothing to disk, and sends nothing anywhere — it maps a string to an
/// enum and forgets it. Do not add persistence or telemetry here.
final class HeatDetector {

    /// Apple's on-device classifiers. Held rather than constructed per call:
    /// the first tag pays ~50ms to load, every one after is ~0.2ms.
    ///
    /// The Emotion scheme has no `NLTagScheme` constant in the SDK, but it is
    /// reported by `availableTagSchemes(for: .paragraph, language: .english)`
    /// and works when constructed by raw value.
    private static let emotionScheme = NLTagScheme("Emotion")
    private let tagger = NLTagger(
        tagSchemes: [NLTagScheme("Emotion"), .sentimentScore]
    )

    /// The one thing the classifiers get reliably wrong.
    ///
    /// "fuck yeah" / "fuck yes" / "fuck right" are tagged Anger with negative
    /// sentiment, because the model keys on the profanity and misses that the
    /// following word inverts the speech act. It is the same word carrying
    /// opposite meaning, so no amount of threshold tuning separates them.
    ///
    /// This is a deliberate, minimal exception — four entries against a
    /// specific measured failure, not a vocabulary. Do not grow it into one:
    /// if something else is misread, fix the thresholds or accept the miss.
    private static let positiveProfanity = ["yeah", "yes", "yea", "right"]

    /// Shortest draft worth reading anything into. Below this there is not
    /// enough signal — nudging at "no." would be both wrong and creepy.
    private static let minimumLength = 8

    /// Load the emotion model now rather than on the user's first keystroke.
    ///
    /// The first `tag(...)` call pays ~58ms to load it; every one after is
    /// ~4ms. Without this that cost lands on whichever keystroke happens to be
    /// first, which is a visible stall in a keyboard.
    func prewarm() {
        _ = classify("ready", using: Self.emotionScheme)
    }

    /// How heated the draft looks, as the presence level it justifies.
    ///
    /// Never returns `.engaged`: that means "you chose to create space" and is
    /// reached by holding the key. The detector's ceiling is an invitation.
    func presence(for draft: String) -> SpacebarPresence {
        guard draft.prefix(Self.minimumLength).count == Self.minimumLength else {
            return .rest
        }
        // Code, logs and URLs are not feelings. A structural ratio rather than
        // a keyword list, so it generalises to anything symbol-dense.
        guard looksLikeProse(draft) else { return .rest }

        let text = draft.lowercased()
        if isCelebratory(text) { return .rest }

        let emotion = classify(draft, using: Self.emotionScheme)
        let polarity = Double(classify(draft, using: .sentimentScore) ?? "") ?? 0

        Unpackd.log.debug("""
            emotion=\(emotion ?? "nil", privacy: .public) \
            polarity=\(polarity, privacy: .public)
            """)

        let isHot = emotion == "Anger" || emotion == "Disgust"
        let isNegative = isHot || emotion == "Sadness"

        // Clearly positive text is never a moment where space helps — EXCEPT
        // when the emotion model says anger and the message is aimed at
        // somebody. Measured: "i hate you so much right now" scores +0.4
        // polarity, because the sentiment model reads "so much" as
        // enthusiasm, and a flat positive veto discarded it. Two classifiers
        // disagreeing is not a reason to trust the weaker one.
        if polarity >= 0.4, !(isHot && addressesSomeone(text)) { return .rest }

        // Anger aimed at a person is the case this feature exists for, so it
        // reaches NUDGE on weaker evidence than undirected frustration.
        //
        // `polarity <= 0` rather than `< 0` is deliberate and measured: Apple's
        // sentiment model scores several of the most pointed messages at
        // exactly 0.00 — "You always do this. You never once considered how it
        // affects me." and "i hate you so much right now" both do. Requiring
        // strictly negative polarity discarded precisely the drafts this
        // feature exists for. Direction plus a negative emotion is enough; the
        // positive-sentiment veto above already removed anything cheerful.
        let directed = addressesSomeone(text)
        if isHot, directed { return .nudge }
        if isNegative, polarity <= 0, directed { return .nudge }
        if isHot, polarity <= -0.5 { return .nudge }
        if isNegative || polarity <= -0.5 { return .aware }
        return .rest
    }

    // MARK: - Signals

    private func classify(_ draft: String, using scheme: NLTagScheme) -> String? {
        tagger.string = draft
        let (tag, _) = tagger.tag(
            at: draft.startIndex,
            unit: .paragraph,
            scheme: scheme
        )
        return tag?.rawValue
    }

    /// Whether the draft is addressed *at* somebody.
    ///
    /// Second-person pronouns only — a closed grammatical class, not a
    /// vocabulary of angry words. "This is ridiculous" and "You are ridiculous"
    /// are different messages, and only the second is what this feature is for.
    private func addressesSomeone(_ lowercased: String) -> Bool {
        let padded = " \(lowercased) "
        return [" you ", " you'", " your ", " youre ", " u ", " ur "]
            .contains { padded.contains($0) }
    }

    /// Profanity used as celebration rather than attack. See `positiveProfanity`.
    private func isCelebratory(_ lowercased: String) -> Bool {
        Self.positiveProfanity.contains { lowercased.contains("fuck \($0)") }
    }

    /// Whether this reads as prose rather than code, logs or a URL.
    ///
    /// Measures punctuation density, so it needs no vocabulary and catches
    /// anything symbol-heavy. Pasting a stack trace or a line of Swift into a
    /// message field should never light the keyboard up.
    private func looksLikeProse(_ draft: String) -> Bool {
        var symbols = 0
        var letters = 0
        for character in draft {
            if character.isLetter { letters += 1 }
            else if "{}[]()<>=/\\|_;`*#@~^".contains(character) { symbols += 1 }
        }
        guard letters > 0 else { return false }
        return Double(symbols) / Double(letters) < 0.06
    }
}
