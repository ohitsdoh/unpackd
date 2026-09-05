//
//  PracticeSettings.swift
//  Unpackd
//

import Foundation

enum PracticeKey: String, CaseIterable, Identifiable {
    case breathe = "B"
    case rewrite = "R"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathe: "Breathe"
        case .rewrite: "Rewrite"
        }
    }

    var description: String {
        switch self {
        case .breathe: "Open one guided breath before responding."
        case .rewrite: "Rewrite the current draft with more clarity."
        }
    }

    var detail: String {
        switch self {
        case .breathe: "Hold B on the Unpackd keyboard."
        case .rewrite: "Hold R on the Unpackd keyboard."
        }
    }
}

enum PracticeSettings {
    static let appGroupId = "group.com.hoamedigital.unpackd"
    static let enabledPracticeKeysKey = "enabledPracticeKeys"
    static let defaultEnabledKeys: Set<String> = ["B", "R"]

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
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
