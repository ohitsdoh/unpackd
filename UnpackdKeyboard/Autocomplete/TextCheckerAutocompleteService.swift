//
//  TextCheckerAutocompleteService.swift
//  UnpackdKeyboard
//
//  Autocomplete/autocorrect built on UITextChecker.
//

import Foundation
import KeyboardKit
import UIKit

/// Autocomplete and autocorrect backed by `UITextChecker`.
///
/// WHY THIS EXISTS
/// KeyboardKit ships `StandardAutocompleteService`, fully implemented, in the
/// MIT binary — but its initializer is `throws` precisely so it can reject an
/// unlicensed caller: `autocomplete` is a case in KeyboardKit's `ProFeature`
/// enum, and constructing the service without a Pro key throws
/// `licenseFeatureOrTierRequired(.autocomplete, _)`. What MIT falls back to is
/// `DisabledAutocompleteService`, whose `autocomplete(_:)` returns nothing.
/// That empty result — not a missing toolbar — is why this keyboard had no
/// autocorrect.
///
/// Only the *service* is gated. The rest of the pipeline in
/// `StandardKeyboardActionHandler` — `tryApplyAutocorrectSuggestion`,
/// the inserted/removed-space bookkeeping, `tryAutocompleteIgnoreCurrentWord`
/// — is unlicensed and already running. It just never had suggestions to act
/// on. So this type only has to answer "what are the suggestions for this
/// text"; auto-apply-on-space, undo, and the toolbar come for free.
///
/// `UITextChecker` is the same on-device spelling engine the stock keyboard
/// uses. It costs no memory budget worth worrying about against the ~60MB
/// extension cap (it is a system service, not a bundled dictionary) and needs
/// no network, so `RequestsOpenAccess` stays `false`.
///
/// CONCURRENCY — three constraints that only have one common solution
///
///   1. `UITextChecker` carries UIKit's blanket `NS_SWIFT_UI_ACTOR`, so every
///      member reads as `@MainActor`. Its lookups return a non-Sendable
///      `[String]?`, which cannot be returned into a nonisolated context.
///   2. `AutocompleteService` is a bare `AnyObject` protocol — neither
///      `@MainActor` nor `Sendable` — and `AutocompleteResult` is non-Sendable
///      too, so nothing can be handed back across an actor boundary.
///   3. `MainActor.assumeIsolated` looks like the escape hatch and is not: a
///      nonisolated `async` method runs on the cooperative pool regardless of
///      who awaits it, so the assertion is false and traps at runtime.
///
/// The resolution is to isolate the *methods* to the main actor and mark the
/// conformance `@preconcurrency`: the bodies run where `UITextChecker` wants,
/// nothing non-Sendable crosses a boundary, and the type still satisfies the
/// nonisolated protocol. KeyboardKit already drives autocomplete from the main
/// actor, so this costs no real hop.
final class TextCheckerAutocompleteService: @preconcurrency AutocompleteService {

    var locale: Locale

    /// How many suggestions to hand the toolbar. Three is what the stock
    /// keyboard shows and what fits before items start truncating.
    private let maxCount: Int

    /// `UITextChecker` is stateful and comparatively expensive to build, so it
    /// is created once and reused for the lifetime of the keyboard.
    ///
    /// Only touched from main-actor-isolated methods (see the note on the
    /// type), which is what UIKit's annotation on `UITextChecker` asks for.
    private let checker: UITextChecker

    /// Words the user has explicitly rejected, and words they have taught us.
    ///
    /// These are per-session only. Persisting them means a shared container,
    /// and `appGroupId` is nil while signing with a free Apple ID (see
    /// `KeyboardApp.unpackd`) — so writing them anywhere durable is a change
    /// to make alongside restoring the App Group, not before it.
    private(set) var ignoredWords: [String] = []
    private(set) var learnedWords: [String] = []

    /// `@MainActor` because `UITextChecker.init` is, like the rest of the
    /// class. The controller builds this in `viewDidLoad`, which is already
    /// main-actor, so it costs nothing.
    @MainActor
    init(locale: Locale = .current, maxCount: Int = 3) {
        self.locale = locale
        self.maxCount = maxCount
        self.checker = UITextChecker()
    }

    // MARK: - AutocompleteService

    /// The single entry point KeyboardKit calls as the user types.
    ///
    /// `text` is the document context *before the cursor*, not just the current
    /// word, so the current word has to be sliced off the end first.
    ///
    /// `@MainActor` on the method rather than the type — see the CONCURRENCY
    /// note above for why that is the only arrangement that compiles.
    @MainActor
    func autocomplete(_ text: String) async throws -> AutocompleteResult {
        let word = Self.currentWord(in: text)

        // Just after a space there is no partial word to complete, so this is
        // where predictive typing goes: suggest the *next* word from the one
        // before it, which is what the stock keyboard shows at this moment.
        guard !word.isEmpty else {
            return .init(
                inputText: text,
                suggestions: nextWordSuggestions(after: text)
            )
        }

        return .init(
            inputText: text,
            suggestions: suggestions(for: word)
        )
    }

    func hasIgnoredWord(_ word: String) -> Bool {
        ignoredWords.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    func hasLearnedWord(_ word: String) -> Bool {
        learnedWords.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    var canIgnoreWords: Bool { true }
    var canLearnWords: Bool { true }

    func ignoreWord(_ word: String) {
        guard !hasIgnoredWord(word) else { return }
        ignoredWords.append(word)
    }

    func learnWord(_ word: String) {
        guard !hasLearnedWord(word) else { return }
        learnedWords.append(word)
        // Also teach the system checker, so the word stops being flagged as a
        // misspelling everywhere this process asks.
        UITextChecker.learnWord(word)
    }

    func removeIgnoredWord(_ word: String) {
        ignoredWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    func unlearnWord(_ word: String) {
        learnedWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        UITextChecker.unlearnWord(word)
    }
}

// MARK: - Suggestion building

private extension TextCheckerAutocompleteService {

    /// Build the toolbar's three slots for a single in-progress word.
    ///
    /// The shape mirrors the stock keyboard: the middle slot is the one that
    /// gets applied on space, and it is quoted-literal when we are *not*
    /// correcting, so the user can always keep exactly what they typed.
    @MainActor
    func suggestions(for word: String) -> [AutocompleteSuggestion] {
        // Smart punctuation: the substitutions iOS applies inside a normal text
        // field but not to text a keyboard extension pushes through the proxy.
        // Offered as an `.autocorrect` suggestion so the existing
        // space-to-apply path in StandardKeyboardActionHandler performs the
        // swap — the same mechanism a spelling fix uses.
        // Looked up against `.english` rather than `self.locale`: the table is
        // keyed by language, and `Locale.Dictionary` matches keys exactly, so a
        // regional locale like en_GB would silently miss an "en" entry and drop
        // smart punctuation entirely. `KeyboardApp.unpackd` declares
        // `locales: [.english]`, so this is the only table there is; when a
        // second language is added, resolve the language from `locale` here
        // rather than passing the region-qualified locale straight through.
        if let replacement = Self.textReplacements.textReplacement(for: word, locale: .english) {
            return [
                .init(text: word, type: .unknown, title: "\"\(word)\""),
                .init(text: replacement, type: .autocorrect)
            ]
        }

        // Not a word we should ever correct — a number, @handle, URL or
        // acronym. Bail before touching UITextChecker: `guesses` and
        // `completions` cost ~700-900µs each, and this runs on every
        // keystroke, so paying that to complete a token we have already
        // classified as not-a-word is the one real waste in this path.
        guard isCorrectable(word) else {
            return [.init(text: word, type: .regular)]
        }

        let language = languageCode

        // A word the user has told us to leave alone is never corrected, but
        // completions are still useful, so this is not an early return.
        let isProtected = hasIgnoredWord(word) || hasLearnedWord(word)

        let misspelled = !isProtected && isMisspelled(word, language: language)

        // `guesses` is the correction list ("teh" -> "the"); `completions` is
        // the prefix list ("th" -> "the", "that"). A misspelled word wants
        // guesses, a correctly-spelled prefix wants completions.
        let candidates: [String] = misspelled
            ? guesses(for: word, language: language)
            : completions(for: word, language: language)

        let ranked: [String] = Array(
            candidates
                .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
                .prefix(maxCount)
        )

        // What the user typed always comes first. When a correction is pending
        // it is quoted and `.unknown`, so tapping it means "no, I meant this"
        // and suppresses the autocorrect; otherwise it is a plain suggestion.
        // With no candidates at all this is the whole toolbar, which keeps the
        // layout from jumping.
        let literal: AutocompleteSuggestion = misspelled
            ? .init(text: word, type: .unknown, title: "\"\(word)\"")
            : .init(text: word, type: .regular)

        // `.autocorrect` on the top guess is the flag that
        // `StandardKeyboardActionHandler` keys on in
        // `tryApplyAutocorrectSuggestion` — it is what makes space-to-correct
        // fire. Nothing carries it when the word is spelled correctly, so
        // space inserts the word untouched.
        let rest = ranked.enumerated().map { index, candidate in
            AutocompleteSuggestion(
                text: candidate,
                type: misspelled && index == 0 ? .autocorrect : .regular
            )
        }

        return Array(([literal] + rest).prefix(maxCount))
    }

    /// Predictive typing: what word probably comes next.
    ///
    /// SCOPE — READ BEFORE EXTENDING
    /// This is a fixed bigram table, not a language model. It knows "I" is
    /// often followed by "am/have/think" and nothing more; it does not learn,
    /// does not adapt to the user, and returns nothing for the long tail. That
    /// is a deliberate ceiling, not an unfinished implementation:
    ///
    ///   - `UITextChecker` has no next-word API. It completes and corrects a
    ///     word in hand; it cannot predict an absent one.
    ///   - KeyboardKit's own next-word prediction is `RemoteAutocompleteRequest`
    ///     — a `URLRequest` to Claude/OpenAI. That needs Full Access and ships
    ///     the user's text off-device, which this product cannot do.
    ///   - A real on-device model means shipping an n-gram corpus, and the
    ///     extension lives under a ~60MB jetsam cap it must not spend here.
    ///
    /// The honest framing is "sentence starters and common continuations".
    /// If this needs to be genuinely smart, the on-device path is Foundation
    /// Models — which this app already loads for `ReflectionEngine` — not a
    /// bigger table. That would be a real feature with its own latency budget,
    /// not an extension of this function.
    func nextWordSuggestions(after text: String) -> [AutocompleteSuggestion] {
        let previous = Self.lastCompletedWord(in: text)

        // Start of a message: offer openers rather than an empty toolbar.
        guard !previous.isEmpty else {
            return Self.sentenceStarters.prefix(maxCount).map {
                AutocompleteSuggestion(text: $0, type: .regular)
            }
        }

        let key = previous.lowercased()
        guard let followers = Self.bigrams[key] else { return [] }

        let capitalize = previous.first?.isUppercase == true
            && Self.sentenceEnders.contains(key)

        return followers.prefix(maxCount).map { follower in
            let text = capitalize
                ? follower.prefix(1).uppercased() + follower.dropFirst()
                : follower
            return AutocompleteSuggestion(text: text, type: .regular)
        }
    }

    @MainActor
    func isMisspelled(_ word: String, language: String) -> Bool {
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelling = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        return misspelling.location != NSNotFound
    }

    /// Run one of `UITextChecker`'s word lookups and case-match the result.
    ///
    /// DO NOT REINTRODUCE `MainActor.assumeIsolated` HERE — it crashes.
    /// `guesses` and `completions` are annotated main-actor-isolated because
    /// `UITextChecker` is a UIKit type, not because they have a real threading
    /// requirement. That made `assumeIsolated` look like the obvious escape
    /// hatch, and it is the wrong one: it *asserts* main-actor context rather
    /// than switching to it, so it traps with `EXC_BREAKPOINT` when the
    /// assertion is false — which it always is here.
    ///
    /// It is always false because `AutocompleteService.autocomplete` is `async`
    /// on a protocol that is a bare `AnyObject` (verified in KeyboardKit's
    /// `.swiftinterface`), and this type deliberately is not `@MainActor`. A
    /// nonisolated `async` method runs on the generic executor no matter who
    /// awaits it, so the body is off the main actor even though KeyboardKit
    /// calls it from the main actor. Reasoning about the *call site's*
    /// isolation is the trap; what matters is where the body runs.
    ///
    /// `UITextChecker` is genuinely thread-safe, so calling it from the
    /// cooperative pool is correct. The service still cannot be `@MainActor`
    /// (see the note on the type: `AutocompleteResult` is non-Sendable and
    /// could not be returned across the boundary), so this is the only
    /// direction that works.
    ///
    /// These are two plain methods rather than one taking a lookup closure. The
    /// closure version does not compile: returning the result out through a
    /// closure makes a non-Sendable `[String]?` cross an isolation boundary,
    /// which is a hard error that no `@preconcurrency` downgrades. Called
    /// directly, as here, the same lookup is only a warning — the value never
    /// crosses, because the method is already nonisolated. Keep them separate.
    @MainActor
    func guesses(for word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: word.utf16.count)
        let raw = checker.guesses(
            forWordRange: range, in: word, language: language
        ) as NSArray? as? [String] ?? []
        return matchingCase(of: word, in: raw)
    }

    @MainActor
    func completions(for word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: word.utf16.count)
        let raw = checker.completions(
            forPartialWordRange: range, in: word, language: language
        ) as NSArray? as? [String] ?? []
        return matchingCase(of: word, in: raw)
    }

    /// `UITextChecker` returns lowercase completions regardless of input, so
    /// "Th" would suggest "that" and quietly destroy the user's capital.
    func matchingCase(of word: String, in candidates: [String]) -> [String] {
        guard let first = word.first, first.isUppercase else { return candidates }
        return candidates.map { candidate in
            guard let head = candidate.first else { return candidate }
            return head.uppercased() + candidate.dropFirst()
        }
    }

    /// Skip anything that is not really a word: numbers, punctuation runs,
    /// URLs, @handles. Correcting these is the behaviour people describe as a
    /// keyboard "fighting" them.
    func isCorrectable(_ word: String) -> Bool {
        guard word.count > 1 else { return false }
        guard word.contains(where: \.isLetter) else { return false }
        guard !word.contains(where: \.isNumber) else { return false }
        // A capital anywhere but the first character reads as a name, acronym
        // or identifier (iPhone, NASA, McCarthy).
        guard !word.dropFirst().contains(where: \.isUppercase) else { return false }
        let disqualifying: Set<Character> = ["@", "#", "/", ":", "_", "."]
        return !word.contains(where: disqualifying.contains)
    }

    /// `UITextChecker` wants a language, not a locale identifier. It expects
    /// forms like "en_US"; falling back to plain "en" keeps a bare `Locale`
    /// working, and an unavailable language degrades to no suggestions rather
    /// than to a crash.
    var languageCode: String {
        let identifier = locale.identifier.replacingOccurrences(of: "-", with: "_")
        let available = UITextChecker.availableLanguages
        if available.contains(identifier) { return identifier }
        if let language = locale.language.languageCode?.identifier {
            if let match = available.first(where: { $0.hasPrefix(language) }) {
                return match
            }
            return language
        }
        return "en_US"
    }

    /// The last finished word before the cursor, stripped of trailing
    /// punctuation so "angry." still keys the table as "angry".
    static func lastCompletedWord(in text: String) -> String {
        // Bounded for the same reason as `currentWord`, and additionally
        // because `split` over the whole draft allocates a substring for every
        // word only to use the last one. Both run on every keystroke.
        let trimmed = text.suffix(scanWindow)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .last
        else { return "" }

        // Keep the terminator itself as the key when the sentence just ended:
        // "." predicts a capitalised opener for the next sentence.
        let word = String(last)
        if let terminator = word.last, sentenceEnders.contains(String(terminator)) {
            return String(terminator)
        }
        return word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// Smart-punctuation substitutions, keyed by exactly what the user typed.
    ///
    /// iOS applies these inside a normal text field, but not to text a keyboard
    /// extension inserts through the proxy, so a custom keyboard loses them
    /// unless it reimplements them.
    ///
    /// The *storage* is KeyboardKit's `AutocompleteReplacementDictionary`, but
    /// the *lookup* is ours. Only the Pro-gated `StandardAutocompleteService`
    /// reads `AutocompleteContext.autocorrectDictionary`, so entries written
    /// there would be stored and never consulted — but the dictionary type
    /// itself is plain MIT (its `init` does not throw, unlike the Pro-gated
    /// `additionalAutocorrections`). Using it keeps the substitutions keyed by
    /// locale rather than in a flat English-only table, and means a later move
    /// onto the Pro service composes instead of needing a rewrite.
    static let textReplacements: AutocompleteReplacementDictionary = {
        var dictionary = AutocompleteReplacementDictionary()
        dictionary.setTextReplacements(["--": "—", "...": "…"], for: .english)
        return dictionary
    }()

    /// Keys that mean "a new sentence starts here".
    static let sentenceEnders: Set<String> = [".", "!", "?"]

    /// Openers offered on an empty field. Weighted toward how this keyboard is
    /// actually used — drafting a difficult message to someone.
    static let sentenceStarters = ["I", "I'm", "Thanks"]

    /// Common continuations, most-frequent first.
    ///
    /// Hand-written rather than derived from a corpus, and intentionally
    /// small: every entry is a fixed memory cost inside the extension's
    /// footprint, and a wrong-but-confident prediction is worse than none.
    /// Skewed toward first-person and feeling words because that is the
    /// vocabulary of the drafts this keyboard exists to catch.
    static let bigrams: [String: [String]] = [
        // Sentence starts
        ".": ["I", "It", "But"],
        "!": ["I", "It", "But"],
        "?": ["I", "It", "Do"],

        // First person — the spine of an I-statement
        "i": ["am", "have", "think", "feel", "just", "don't"],
        "i'm": ["not", "just", "sorry", "feeling", "really"],
        "im": ["not", "just", "sorry", "feeling"],
        "we": ["can", "should", "need", "have"],
        "you": ["are", "can", "should", "said", "were", "did"],
        "it": ["is", "was", "feels", "seems"],
        "that": ["is", "was", "makes", "would"],
        "this": ["is", "was", "feels"],
        "there": ["is", "are", "was"],

        // Verbs into objects
        "am": ["not", "going", "sorry", "feeling"],
        "is": ["not", "the", "a", "really"],
        "are": ["not", "you", "the"],
        "was": ["not", "a", "the", "just"],
        "have": ["to", "been", "a", "no"],
        "has": ["been", "to", "a"],
        "had": ["to", "been", "a"],
        "will": ["be", "not", "have"],
        "would": ["be", "have", "like"],
        "can": ["you", "we", "be", "not"],
        "could": ["be", "you", "we", "have"],
        "should": ["be", "not", "have", "we"],
        "need": ["to", "you", "a", "some"],
        "want": ["to", "you", "a"],
        "feel": ["like", "that", "so"],
        "feels": ["like", "so"],
        "think": ["that", "we", "you", "it"],
        "know": ["that", "you", "how", "what"],
        "don't": ["know", "think", "want", "have"],
        "didn't": ["know", "think", "mean", "want"],
        "just": ["want", "need", "feel", "a"],
        "really": ["need", "want", "think", "appreciate"],

        // Connectors
        "to": ["be", "the", "you", "get", "do"],
        "the": ["same", "way", "time", "other"],
        "a": ["lot", "little", "bit", "few"],
        "and": ["I", "the", "it", "then"],
        "but": ["I", "it", "the", "that"],
        "so": ["I", "that", "much", "we"],
        "because": ["I", "it", "you", "of"],
        "when": ["I", "you", "we", "it"],
        "if": ["you", "I", "we", "that"],
        "for": ["the", "me", "you", "a"],
        "of": ["the", "my", "it"],
        "with": ["the", "you", "me", "a"],
        "about": ["the", "it", "this", "you"],
        "at": ["the", "me", "you"],
        "my": ["own", "time", "head"],
        "your": ["own", "time", "side"],
        "not": ["sure", "going", "the", "a"],
        "very": ["much", "hard", "important"]
    ]

    /// The in-progress word: everything after the last whitespace or newline.
    ///
    /// Deliberately not split on punctuation — an apostrophe is part of the
    /// word ("don't"), and splitting on it turns every contraction into a
    /// misspelling.
    static func currentWord(in text: String) -> String {
        // Scan a bounded suffix, not the whole draft. `text` is
        // `documentContextBeforeInput` — potentially the entire message up to
        // the cursor — and this runs on every keystroke, so searching all of it
        // makes each keypress cost O(draft length). No word worth completing is
        // anywhere near `scanWindow` characters, so the cap changes no result.
        let tail = text.suffix(scanWindow)
        let terminators = CharacterSet.whitespacesAndNewlines
        guard let range = tail.rangeOfCharacter(
            from: terminators,
            options: .backwards
        ) else {
            // No boundary in the window: only a genuinely short draft is one
            // unbroken word, so anything longer is mid-word past the cap and
            // not worth completing.
            return text.count <= scanWindow ? text : ""
        }
        return String(tail[range.upperBound...])
    }

    /// How far back the two scanners look. Comfortably longer than any word a
    /// completion would apply to, short enough that the cost per keystroke does
    /// not grow with the draft.
    static let scanWindow = 64
}
