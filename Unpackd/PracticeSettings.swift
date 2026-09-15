//
//  PracticeSettings.swift
//  Unpackd
//

import Foundation

enum PracticeKey: String, CaseIterable, Identifiable {
    case breathe = "B"
    /// R WAS REWRITE, AND IS NOW REMEMBER.
    /// Rewrite kept its route through the hold-space panel — where the design
    /// puts it anyway — and gave up only its redundant shortcut, which freed
    /// R for Remember. Remember has no other entry point.
    case remember = "R"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathe: "Breathe"
        case .remember: "Remember"
        }
    }

    var description: String {
        switch self {
        case .breathe: "Open one guided breath before responding."
        case .remember: "Bring back the words you want close."
        }
    }

    var detail: String {
        switch self {
        case .breathe: "Hold B on the Unpackd keyboard."
        case .remember: "Hold R on the Unpackd keyboard."
        }
    }
}

enum PracticeSettings {
    static let enabledPracticeKeysKey = "enabledPracticeKeys"
    static let defaultEnabledKeys: Set<String> = ["B", "R"]

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func enabledKeys() -> Set<String> {
        guard let values = defaults.array(forKey: enabledPracticeKeysKey) as? [String] else {
            return defaultEnabledKeys
        }
        return Set(values.map { $0.uppercased() })
    }

    static func setEnabled(_ isEnabled: Bool, for key: PracticeKey) {
        var keys = enabledKeys()
        if isEnabled {
            keys.insert(key.rawValue)
        } else {
            keys.remove(key.rawValue)
        }
        defaults.set(Array(keys).sorted(), forKey: enabledPracticeKeysKey)
    }

    static func isEnabled(_ key: PracticeKey) -> Bool {
        enabledKeys().contains(key.rawValue)
    }
}
