//
//  RememberedThought.swift
//  Unpackd / UnpackdKeyboard
//
//  Compiled into BOTH targets, like SavedMoment and Typography: the app
//  authors these, the keyboard reads them.
//

import Foundation
import os

/// One thing the user wants to be able to read back to themselves — an
/// affirmation, a mantra, a line they want close when it is hard to find.
///
/// The user's own words, always. Nothing here is generated: the whole point
/// of Remember is that it hands back something *you* decided mattered, at a
/// moment when deciding is hard. A model-written affirmation would be the
/// opposite of that, which is why `ReflectionEngine` is nowhere near this
/// file.
struct RememberedThought: Codable, Equatable, Identifiable {

    let id: UUID
    /// The thought itself, as the user typed it.
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    /// The longest a thought may be.
    ///
    /// This is rendered large and centred on a keyboard-sized panel and has to
    /// be readable at a glance — the deck's examples ("I can be honest and
    /// still be kind.") are one short sentence. A paragraph would neither fit
    /// nor work: the point is to be absorbed in a second, not read.
    static let characterLimit = 120
}

/// This file is compiled into both targets, so it cannot use `Unpackd.log`,
/// which lives in the extension only.
private let thoughtLog = Logger(
    subsystem: "com.hoamedigital.unpackd",
    category: "rememberedThoughts"
)

/// Stores the user's remembered thoughts in the shared App Group.
///
/// Written by the container app, read by the keyboard — the opposite direction
/// from `SavedMomentStore`, and the reason both exist rather than one generic
/// store: they have different owners, different lifetimes, and conflating them
/// would let a keyboard-side bug delete words the user deliberately authored.
enum RememberedThoughtStore {


    private static let key = "rememberedThoughts"

    /// A ceiling for the same reason `SavedMomentStore` has one: this is
    /// `UserDefaults`, read wholesale into memory, in a process that gets
    /// jetsam-killed at ~60MB.
    static let limit = 100

    /// A computed `var`, NOT a `static let`.
    ///
    /// `UserDefaults` is not `Sendable`, so a stored static is rejected under
    /// Swift 6 strict concurrency ("static property 'defaults' is not
    /// concurrency-safe"). Recomputing is the right shape anyway and costs
    /// nothing: `UserDefaults(suiteName:)` hands back a shared cached store
    /// rather than reparsing the plist.
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    /// Every thought, newest first.
    static func load() -> [RememberedThought] {
        guard let defaults, let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([RememberedThought].self, from: data)
        } catch {
            thoughtLog.error("rememberedThoughts: decode failed, treating as empty")
            return []
        }
    }

    /// Replace the whole list. The app owns this; the keyboard only reads.
    static func save(_ thoughts: [RememberedThought]) {
        guard let defaults else {
            thoughtLog.error("rememberedThoughts: app group unavailable, not saving")
            return
        }
        do {
            let data = try JSONEncoder().encode(Array(thoughts.prefix(limit)))
            defaults.set(data, forKey: key)
        } catch {
            thoughtLog.error("rememberedThoughts: encode failed")
        }
    }
}
