//
//  SavedMoment.swift
//  Unpackd / UnpackdKeyboard
//
//  Compiled into BOTH targets, like Typography.swift: the keyboard writes
//  these and the container app reads them, and a shared framework for two
//  small types would cost more than compiling one file twice.
//

import Foundation

/// The App Group both targets share.
///
/// ONE LITERAL, BECAUSE A MISMATCH IS SILENT.
/// This id has to agree with the `com.apple.security.application-groups`
/// entitlement in BOTH targets and with `KeyboardApp.unpackd`. When it does
/// not, `UserDefaults(suiteName:)` simply returns nil — no crash, no warning,
/// just a store that reads empty and writes nowhere. It was written out at
/// five sites before this existed, which is five chances to typo something
/// nothing would tell you about.
///
/// Lives here because this file is compiled into both targets; the
/// entitlements themselves are still the source of truth, and changing the
/// group means changing them, this, and `KeyboardApp.unpackd` together.
enum AppGroup {
    static let identifier = "group.com.hoamedigital.unpackd"
}

/// A moment the user chose to step away from, saved for later.
///
/// Persisted to the shared App Group so the container app can surface it. This
/// is the one thing in the keyboard that writes to disk, and it only ever does
/// so on an explicit tap of "Unpack later" — `HeatDetector` and the reflect
/// path remain storage-free by design.
struct SavedMoment: Codable, Equatable, Identifiable {

    let id: UUID
    /// The draft as it stood when they stepped away.
    let draft: String
    /// Anything they had already unpacked, so returning does not start over.
    let answers: [SavedAnswer]
    let savedAt: Date

    struct SavedAnswer: Codable, Equatable {
        let question: String
        let response: String
    }

    /// Takes plain values rather than an `UnpackContext`.
    ///
    /// This file is compiled into the container app too, and the app has no
    /// business knowing about the keyboard's flow types — the convenience
    /// initialiser that takes a context lives beside them in the extension
    /// instead. See `SavedMoment+Unpack.swift`.
    init(draft: String, answers: [SavedAnswer], savedAt: Date = .now) {
        self.id = UUID()
        self.draft = draft
        self.answers = answers
        self.savedAt = savedAt
    }

    /// Whether this moment is worth keeping.
    ///
    /// A moment with no draft and nothing unpacked cannot be resumed and shows
    /// as a blank row in the app — it is storage without content. This lives
    /// on the type rather than at the "Unpack later" button because it is a
    /// property of the moment, not of one caller: `save` enforces it, so a
    /// second entry point cannot reintroduce the empty rows.
    ///
    /// Not hypothetical — empty moments were written for real, when
    /// `currentDraft()` read the panel's proxy instead of the host's. The
    /// save reported success and stored nothing recoverable.
    var isWorthKeeping: Bool {
        !draft.isBlank || !answers.isEmpty
    }

    /// What "Copy" should put on the clipboard.
    ///
    /// Beside `isWorthKeeping` on purpose: that rule guarantees a stored
    /// moment has a draft OR answers, so this is the other half of the same
    /// decision and the view never has to re-derive it. When the view checked
    /// `draft.isBlank` itself, an answers-only moment rendered a disabled
    /// button — a row the store had agreed to keep, offering nothing back,
    /// while the section header promised otherwise.
    var copyText: String {
        draft.isBlank ? answers.map(\.response).joined(separator: "\n") : draft
    }
}

/// Whether a string is empty once surrounding whitespace is discounted.
///
/// Every place that asks "is there anything to work with here" — a draft, a
/// typed answer, an edited message — was asking it by hand, in both targets.
/// One name for it means the trimming rule cannot drift between the check and
/// the value that gets used.
extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The trimmed value, or nil when there is nothing left.
    ///
    /// Pairs with `isBlank` for the common "check, then use the trimmed form"
    /// sequence, so the trim is written once rather than once per branch.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
