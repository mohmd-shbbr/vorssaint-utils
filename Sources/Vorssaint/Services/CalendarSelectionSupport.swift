// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Calendar identifiers only. Event titles and account names are never saved.
enum CalendarSelectionSupport {
    static let identifiersKey = "calendarSelectedIdentifiers"
    static let configuredKey = "calendarSelectionConfigured"
    static let changed = Notification.Name("VorssaintCalendarSelectionChanged")

    /// Nil retains the older exclusion-based selection until the user chooses
    /// calendars here. An explicitly empty selection means no calendars.
    static func selected(in defaults: UserDefaults = .standard) -> Set<String>? {
        guard defaults.bool(forKey: configuredKey) else { return nil }
        return Set(defaults.stringArray(forKey: identifiersKey) ?? [])
    }

    static func store(_ identifiers: Set<String>, in defaults: UserDefaults = .standard) {
        defaults.set(identifiers.sorted(), forKey: identifiersKey)
        defaults.set(true, forKey: configuredKey)
        if defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func filtering<C>(_ calendars: [C], selected: Set<String>?, excluded: Set<String>,
                              identifier: (C) -> String) -> [C] {
        calendars.filter { calendar in
            let id = identifier(calendar)
            return selected.map { $0.contains(id) } ?? !excluded.contains(id)
        }
    }
}
