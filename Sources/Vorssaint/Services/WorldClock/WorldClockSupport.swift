// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WorldClockZone: Codable, Equatable, Identifiable {
    var identifier: String
    var label: String
    var id: String { identifier }
    var timeZone: TimeZone { TimeZone(identifier: identifier) ?? .gmt }
    var displayName: String { label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WorldClockSupport.city(identifier) : label }
}

enum WorldClockSupport {
    static let enabledKey = "worldClockMenuBarEnabled"
    static let zonesKey = "worldClockZones"
    static let primaryKey = "worldClockPrimaryIdentifier"
    static let twentyFourHourKey = "worldClock24Hour"

    static func city(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    static func decode(_ data: Data?) -> [WorldClockZone] {
        guard let data, let zones = try? JSONDecoder().decode([WorldClockZone].self, from: data) else { return [] }
        var seen = Set<String>()
        return zones.filter { TimeZone(identifier: $0.identifier) != nil && seen.insert($0.identifier).inserted }
    }

    static func savedZones(in defaults: UserDefaults = .standard) -> [WorldClockZone] {
        let saved = decode(defaults.data(forKey: zonesKey))
        return saved.isEmpty ? [WorldClockZone(identifier: "UTC", label: "UTC")] : saved
    }

    static func time(_ date: Date, in zone: TimeZone, twentyFourHour: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = twentyFourHour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    static func day(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date)
    }

    /// Offsets are calculated for the selected instant, never cached from now:
    /// meeting planning across a daylight-saving transition stays correct.
    static func differenceMinutes(at date: Date, from local: TimeZone, to remote: TimeZone) -> Int {
        (remote.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)) / 60
    }

    static func offsetLabel(minutes: Int) -> String {
        if minutes == 0 { return "Same time" }
        let sign = minutes > 0 ? "+" : "−"
        let absolute = abs(minutes)
        return "\(sign)\(absolute / 60)h" + (absolute % 60 == 0 ? "" : " \(absolute % 60)m")
    }

    static func shifted(_ date: Date, minutes: Double) -> Date {
        date.addingTimeInterval(minutes * 60)
    }
}
