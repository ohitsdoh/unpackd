//
//  UnpackFlow.swift
//  UnpackdKeyboard
//
//  The domain types for "Unpack this" — the guided flow that helps someone
//  find what they actually want to say before rewriting anything.
//

import Foundation

/// One question put to the user, with the options they can tap.
///
/// The deck's rule is "static structure, dynamic content": the *shape* of this
/// screen never changes — a prompt and a short list of taps — while every
/// string in it is generated from the conversation. That is what lets the
/// panel's layout be fixed code while the content is model output.
struct UnpackQuestion: Equatable {

    /// The question itself, e.g. "What do you want them to understand?".
    let prompt: String

    /// Tappable answers. Four is the design's count; `options` is not forced to
    /// exactly four because a model that returns three should degrade into a
    /// slightly shorter list rather than into an error.
    let options: [String]

    /// The upper bound on how many options will be rendered.
    ///
    /// There is deliberately no matching `optionCount` constant for the number
    /// *requested*: `@Guide(.count(4))` is a macro argument and must be a
    /// literal, so a constant could not govern it and would only look as
    /// though it did. The requested count lives in the guide in
    /// `UnpackQuestionOutput`; this is the ceiling the UI enforces, because a
    /// `.count` guide constrains generation rather than guaranteeing it, and a
    /// model that over-produces must not push the panel past the keyboard's
    /// height.
    static let maxOptions = 5
}

/// What the user has told us so far, accumulated across the flow.
///
/// WHY THIS IS A VALUE AND NOT A TRANSCRIPT
/// The obvious implementation is to keep one `LanguageModelSession` and let
/// its transcript carry the context between questions. That is exactly what
/// the 4096-token window cannot afford: each turn's instructions, prompt and
/// structured output stay in the transcript, so by the third call the draft is
/// competing with two rounds of JSON for space. Carrying the answers as a
/// small struct and building a fresh prompt per call keeps every request's
/// context to the draft plus a few short lines.
///
/// It also keeps `FoundationModelsRewriter`'s existing "one fresh session per
/// reflection" rule intact — see `takeWarmedSession`.
struct UnpackContext: Equatable {

    /// The draft the user was typing when they held space.
    var draft: String

    /// Each question that was asked, paired with the answer they gave.
    ///
    /// Ordered, and the order is meaningful: it is the path the user took, and
    /// the model is shown it as such so a later question can build on an
    /// earlier answer rather than restating it.
    var answers: [Answer] = []

    struct Answer: Equatable {
        let question: String
        /// The option they tapped, or what they typed under "Something else...".
        let response: String
        /// Whether `response` is the user's own words rather than one of ours.
        ///
        /// The model is told which is which. An option we generated is a guess
        /// it should treat as approximate; a sentence the user typed is the
        /// one piece of ground truth in the whole flow, and the deck is
        /// explicit that it wins ("Your words win").
        let isUserWritten: Bool
    }

    init(draft: String) {
        self.draft = draft
    }

    /// The accumulated answers rendered for a prompt.
    ///
    /// Empty when nothing has been answered yet, so the caller can omit the
    /// whole section rather than sending a header with nothing under it.
    var promptSummary: String {
        guard !answers.isEmpty else { return "" }
        return answers.map { answer in
            let marker = answer.isUserWritten ? " (their own words)" : ""
            return "Q: \(answer.question)\nA\(marker): \(answer.response)"
        }
        .joined(separator: "\n")
    }

    /// How many questions have been answered.
    var depth: Int { answers.count }
}

/// The model's read of what the user is trying to say, shown before any
/// language is generated.
///
/// This is the "It sounds like you want to..." card — deliberately a reflection
/// the user can agree or disagree with, never a diagnosis of them. The deck's
/// wording is "context, not diagnosis": it describes the *message*, not the
/// person writing it.
struct UnpackInsight: Equatable {
    /// One or two sentences, second person, e.g. "It sounds like you want to
    /// be heard without making this bigger."
    let text: String
}
