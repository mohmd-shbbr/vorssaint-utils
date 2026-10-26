// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum WorldClockTests {
    static func run(_ suite: TestSuite) {
        let comparisonRange = -96...96
        suite.expect(NotchTimerRulerScale.minute(0, in: comparisonRange) == 0,
                     "the shared timer ruler supports a centered current-time position")
        suite.expect(NotchTimerRulerScale.moving(0, by: -14, in: comparisonRange) == 1
                     && NotchTimerRulerScale.moving(0, by: 14, in: comparisonRange) == -1,
                     "dragging the comparison ruler uses the timer's native tick spacing")
        suite.expect(NotchTimerRulerScale.minute(-1000, in: comparisonRange) == -96
                     && NotchTimerRulerScale.minute(1000, in: comparisonRange) == 96,
                     "comparison scrubbing stops at plus or minus twenty-four hours")
        suite.expect(NotchTimerRulerScale.minute(.nan, in: comparisonRange) == -96,
                     "invalid comparison input remains within its signed range")
        let parser = ISO8601DateFormatter()
        let winter = parser.date(from: "2026-01-15T12:00:00Z")!
        let summer = parser.date(from: "2026-07-15T12:00:00Z")!
        let local = TimeZone(identifier: "Asia/Kolkata")!
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        suite.expect(WorldClockSupport.differenceMinutes(at: winter, from: local, to: berlin) == -270,
                     "winter comparison includes the half-hour local offset")
        suite.expect(WorldClockSupport.differenceMinutes(at: summer, from: local, to: berlin) == -210,
                     "future comparisons use daylight saving at the selected date")
        suite.expect(WorldClockSupport.time(winter, in: local) == "17:30"
                     && WorldClockSupport.time(winter, in: berlin) == "13:00",
                     "one absolute instant is rendered in each chosen timezone")
        let later = WorldClockSupport.shifted(winter, minutes: 1440)
        suite.expect(later.timeIntervalSince(winter) == 86400,
                     "the slider advances an instant by its advertised duration")
        let transition = parser.date(from: "2026-03-29T00:30:00Z")!
        suite.expect(WorldClockSupport.time(transition, in: berlin) == "01:30"
                     && WorldClockSupport.time(WorldClockSupport.shifted(transition, minutes: 60), in: berlin) == "03:30",
                     "scrubbing across a spring DST transition skips the nonexistent local hour")
        let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
        suite.expect(WorldClockSupport.differenceMinutes(at: winter, from: .gmt, to: kathmandu) == 345
                     && WorldClockSupport.offsetLabel(minutes: 345) == "+5h 45m",
                     "quarter-hour offsets are not rounded away")
        let saved = [WorldClockZone(identifier: "UTC", label: "Home"),
                     WorldClockZone(identifier: "UTC", label: "Duplicate"),
                     WorldClockZone(identifier: "not-a-zone", label: "Invalid")]
        let decoded = WorldClockSupport.decode(try? JSONEncoder().encode(saved))
        suite.expect(decoded.count == 1 && decoded.first?.displayName == "Home",
                     "invalid and duplicate saved timezone identifiers are discarded")
        suite.expect(WorldClockSupport.decode(Data("broken".utf8)).isEmpty,
                     "damaged settings do not break the menu bar clock")
        suite.expect(WorldClockSupport.city("America/New_York") == "New York",
                     "timezone identifiers have readable default labels")
    }
}
