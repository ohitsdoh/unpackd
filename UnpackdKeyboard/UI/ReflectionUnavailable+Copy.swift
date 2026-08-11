//
//  ReflectionUnavailable+Copy.swift
//  UnpackdKeyboard
//
//  What the user reads when a rewrite can't happen.
//
//  This lives in the UI layer, not next to the state machine: it is product
//  copy, it will be edited for tone far more often than the state machine
//  changes, and it is the first thing that needs localizing. `ReflectSession`
//  should not be the file someone opens to reword a sentence.
//

import Foundation

extension ReflectionUnavailable {

    /// Each case gets its own message. "Something went wrong" for all nine is
    /// how users conclude the feature is broken rather than unavailable.
    var title: String {
        switch self {
        case .deviceNotEligible: "Rewrite needs a newer iPhone"
        case .notEnabled: "Turn on Apple Intelligence"
        case .notReady: "Still getting ready"
        case .rateLimited, .guardrail: "Give it a moment"
        case .busy: "One at a time"
        case .refused: "This one's yours to write"
        case .tooLong: "That message is a bit long"
        case .emptyDraft: "Nothing to rewrite yet"
        case .failed: "Rewrite isn't available"
        }
    }

    var message: String {
        switch self {
        case .deviceNotEligible:
            "Unpackd's rewrite runs on your device and needs Apple Intelligence. Breathe and Reflect still work."
        case .notEnabled:
            "Enable Apple Intelligence in Settings to use rewrite. Nothing you type ever leaves your phone."
        case .notReady:
            "Your device is still downloading the language model. Try again shortly."
        case .rateLimited, .guardrail:
            "Your phone is pacing on-device requests. Try again in a moment."
        case .busy:
            "Still working on the last one."
        case .refused:
            // Deliberately not an apology or a scolding. The model declined;
            // that is not a verdict on the user, and the panel shouldn't imply
            // one to someone who is already upset.
            "Unpackd won't rewrite this one. Breathe and Reflect still work."
        case .tooLong:
            "Try holding space with a shorter draft."
        case .emptyDraft:
            "Write something first, then hold space."
        case .failed(let detail):
            detail
        }
    }
}
