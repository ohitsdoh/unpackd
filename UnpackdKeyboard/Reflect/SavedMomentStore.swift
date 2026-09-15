//
//  SavedMomentStore.swift
//  Unpackd / UnpackdKeyboard
//
//  Persistence for "Unpack later". Compiled into both targets: the keyboard
//  writes, the container app reads.
//

import Foundation
import os

/// This file is compiled into BOTH targets, so it cannot use `Unpackd.log` —
/// that logger lives in the extension only. A private logger here keeps the
/// store self-contained.
private let storeLog = Logger(
    subsystem: "com.hoamedigital.unpackd",
    category: "savedMoments"
)

/// Stores moments the user stepped away from, in the shared App Group so the
/// container app can read them.
///
/// SCOPE OF WHAT IS WRITTEN, AND WHY IT IS NARROW
/// This is the only thing in the keyboard that puts the user's text on disk.
/// A keyboard reads what you type at your worst moments, so the bar for
/// writing any of it down is an explicit, deliberate tap — which is exactly
/// what "Unpack later" is. Nothing here is written on a nudge, a hold, or a
/// rewrite. `HeatDetector` in particular stays storage-free; do not route it
/// through this type.
///
/// WHY UserDefaults AND NOT A FILE
/// The payload is a handful of short strings and the App Group suite is
/// already configured for both targets (see `KeyboardApp.unpackd`). A file in
/// the shared container would need its own coordination for the app and the
/// extension writing concurrently; `UserDefaults` handles that itself. If the
/// saved list ever grows to hold long transcripts this should be revisited,
/// because `UserDefaults` is loaded wholesale into memory — and this process
/// has a ~60MB ceiling.
enum SavedMomentStore {


    private static let key = "savedMoments"

    /// How many moments are kept.
    ///
    /// A cap rather than unbounded growth: this lives in `UserDefaults`, which
    /// is read entirely into memory in a process that gets jetsam-killed at
    /// ~60MB. Oldest are dropped first.
    private static let limit = 50

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

    /// Append a moment. Newest first.
    ///
    /// Silently does nothing if the App Group is unavailable — a failed save
    /// must not break the dismissal that follows it. The user's draft is
    /// untouched either way, which is the promise "Unpack later" actually
    /// makes; the saved copy is a convenience on top of it.
    static func save(_ moment: SavedMoment) {
        guard moment.isWorthKeeping else {
            storeLog.error("savedMoments: refusing to save an empty moment")
            return
        }
        guard let defaults else {
            storeLog.error("savedMoments: app group unavailable, not saving")
            return
        }
        var moments = load()
        moments.insert(moment, at: 0)
        if moments.count > limit {
            moments = Array(moments.prefix(limit))
        }
        do {
            let data = try JSONEncoder().encode(moments)
            defaults.set(data, forKey: key)
        } catch {
            storeLog.error("savedMoments: encode failed")
        }
    }

    /// Every saved moment, newest first.
    static func load() -> [SavedMoment] {
        guard let defaults, let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([SavedMoment].self, from: data)
        } catch {
            // A decode failure means the stored shape no longer matches
            // `SavedMoment` — most likely the type changed between builds.
            // Returning empty rather than throwing keeps the keyboard usable;
            // the next save overwrites the unreadable blob.
            storeLog.error("savedMoments: decode failed, treating as empty")
            return []
        }
    }
}
