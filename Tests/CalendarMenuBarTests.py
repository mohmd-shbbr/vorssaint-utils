#!/usr/bin/env python3
"""Exercise production calendar filtering and meeting presentation without EventKit data."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
calendar = (ROOT / 'Sources/Vorssaint/Services/Notch/NotchCalendarSupport.swift').read_text()
models = calendar[calendar.index('struct NotchCalendarColor:'):calendar.index('/// What the closed island')]
service = (ROOT / 'Sources/Vorssaint/Services/UpcomingMeetingMenuBarService.swift').read_text()
support = service[service.index('enum UpcomingMeetingSupport {'):service.index('/// Uses its own reader')]
with tempfile.TemporaryDirectory(prefix='vorssaint-calendar-tests-') as directory:
    work = Path(directory)
    (work / 'Models.swift').write_text('import Foundation\n' + models)
    (work / 'Support.swift').write_text('import Foundation\n' + support)
    (work / 'main.swift').write_text(r'''
import Foundation
let defaults = UserDefaults(suiteName: "com.vorssaint.tests.calendar-menu")!
defaults.removePersistentDomain(forName: "com.vorssaint.tests.calendar-menu")
defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.calendar-menu") }
var checks = 0
func expect(_ condition: Bool, _ label: String) {
    checks += 1
    precondition(condition, label)
}
expect(CalendarSelectionSupport.selected(in: defaults) == nil, "unconfigured selection preserves legacy behavior")
CalendarSelectionSupport.store([], in: defaults)
expect(CalendarSelectionSupport.selected(in: defaults) == [], "explicitly empty means no calendars")
CalendarSelectionSupport.store(["work"], in: defaults)
expect(CalendarSelectionSupport.selected(in: defaults) == ["work"], "chosen identifiers round-trip")
let choices = ["work", "holidays", "new-calendar"]
expect(CalendarSelectionSupport.filtering(choices, selected: ["work"], excluded: [], identifier: { $0 }) == ["work"], "new and holiday calendars remain hidden after selection")
expect(CalendarSelectionSupport.filtering(choices, selected: [], excluded: [], identifier: { $0 }).isEmpty, "empty selection never falls back to all calendars")
expect(CalendarSelectionSupport.filtering(choices, selected: nil, excluded: ["holidays"], identifier: { $0 }) == ["work", "new-calendar"], "legacy exclusions remain effective before first selection")
let now = Date(timeIntervalSinceReferenceDate: 100_000)
func event(_ id: String, _ start: TimeInterval, _ end: TimeInterval, allDay: Bool = false) -> NotchCalendarEvent {
    NotchCalendarEvent(id: id, title: id, calendar: "Work", start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), allDay: allDay, location: "")
}
let ongoing = event("ongoing", -600, 600)
let future = event("future", 1800, 3600)
let fixtures = [future, event("all-day", -3600, 3600, allDay: true), event("ended", -600, 0), event("outside", 7200, 8000), ongoing]
expect(UpcomingMeetingSupport.upcoming(fixtures, now: now, horizon: 3600).map(\.id) == ["ongoing", "future"], "ongoing first, ended/all-day/outside events excluded")
expect(UpcomingMeetingSupport.countdown(ongoing, now: now) == "Now", "ongoing event labels now")
expect(UpcomingMeetingSupport.countdown(future, now: now) == "in 30m", "future minutes use the requested countdown")
expect(UpcomingMeetingSupport.countdown(event("long", 3900, 4000), now: now) == "in 1h 5m", "long countdown stays compact")
expect(UpcomingMeetingSupport.title(future, now: now, includeTitle: false) == "in 30m", "title can be hidden for privacy")
print("Calendar menu bar: \(checks) checks passed")
'''.replace('\\.', '\.').replace('\\(', '\('))
    command = ['swiftc', str(ROOT / 'Sources/Vorssaint/Services/CalendarSelectionSupport.swift'),
               str(work / 'Models.swift'), str(work / 'Support.swift'), str(work / 'main.swift'), '-o', str(work / 'test')]
    subprocess.run(command, check=True)
    subprocess.run([str(work / 'test')], check=True)
