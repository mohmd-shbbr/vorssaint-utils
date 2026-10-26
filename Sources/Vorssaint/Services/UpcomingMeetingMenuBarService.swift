// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import EventKit

/// Pure presentation policy shared by the status item and its tests.
enum UpcomingMeetingSupport {
    static let enabledKey = "upcomingMeetingMenuBarEnabled"
    static let leadMinutesKey = "upcomingMeetingLeadMinutes"
    static let showTitleKey = "upcomingMeetingShowTitle"

    static func upcoming(_ events: [NotchCalendarEvent], now: Date, horizon: TimeInterval) -> [NotchCalendarEvent] {
        events.filter { !$0.allDay && $0.end > now && $0.start < now.addingTimeInterval(horizon) }
            .sorted {
                // An ongoing meeting takes precedence over later invitations.
                if ($0.start <= now) != ($1.start <= now) { return $0.start <= now }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.id < $1.id
            }
    }

    static func countdown(_ event: NotchCalendarEvent, now: Date) -> String {
        if event.start <= now { return "Now" }
        let minutes = max(1, Int(ceil(event.start.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "in \(hours)h" : "in \(hours)h \(remainder)m"
    }

    static func title(_ event: NotchCalendarEvent, now: Date, includeTitle: Bool) -> String {
        let countdown = countdown(event, now: now)
        guard includeTitle else { return countdown }
        let clean = event.title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let title = clean.isEmpty ? "Meeting" : clean
        let shortened = title.count > 26 ? String(title.prefix(25)) + "…" : title
        return shortened + " · " + countdown
    }
}

/// Uses its own reader so menu-bar meetings work with Dynamic Island disabled.
/// Calendar identifiers are preferences; fetched event content exists in memory only.
final class UpcomingMeetingMenuBarService: NSObject, NSMenuDelegate {
    static let shared = UpcomingMeetingMenuBarService()
    var onOpenSettings: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var reader: NotchCalendarReader?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscription: AnyCancellable?
    private var events: [NotchCalendarEvent] = []
    private var generation = UUID()
    private var loading = false
    private var lastSelection: Set<String>?

    private override init() {
        super.init()
        menu.delegate = self
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        guard UserDefaults.standard.bool(forKey: UpcomingMeetingSupport.enabledKey),
              SessionActivity.shared.isActive else { stop(); return }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "VorssaintUpcomingMeetings"
            item.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Upcoming meetings")
            item.button?.imagePosition = .imageLeading
            item.button?.font = .menuBarFont(ofSize: 0)
            item.menu = menu
            statusItem = item
            reader = NotchCalendarReader()
            for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                         .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged,
                         CalendarSelectionSupport.changed] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in self?.refresh()
                })
            }
            permissionSubscription = Permissions.shared.$calendarAccess.removeDuplicates().dropFirst()
                .sink { [weak self] _ in self?.refresh() }
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refresh()
    }

    func refresh() {
        task?.cancel()
        generation = UUID()
        guard let reader, statusItem != nil else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let selected = CalendarSelectionSupport.selected(), !selected.isEmpty else {
            events = []; loading = false; render()
            return
        }
        // Drop the old selection immediately, before the asynchronous read, so
        // an unchecked calendar cannot remain in the status title or open menu.
        if lastSelection != selected { events = [] }
        lastSelection = selected
        loading = events.isEmpty
        render()
        let requested = generation
        let now = Date()
        let minutes = UserDefaults.standard.integer(forKey: UpcomingMeetingSupport.leadMinutesKey)
        let horizon = TimeInterval(min(10080, max(15, minutes > 0 ? minutes : 1440))) * 60
        let interval = DateInterval(start: Calendar.current.startOfDay(for: now), end: now.addingTimeInterval(horizon))
        task = Task { @MainActor [weak self] in
            let result = await reader.read(interval: interval, excluded: [], selected: selected)
            guard !Task.isCancelled, let self, self.generation == requested,
                  self.statusItem != nil, SessionActivity.shared.isActive else { return }
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                  CalendarSelectionSupport.selected() == selected else {
                self.events = []
                self.loading = false
                self.task = nil
                self.render()
                return
            }
            self.events = UpcomingMeetingSupport.upcoming(result, now: Date(), horizon: horizon)
            self.loading = false
            self.task = nil
            self.render()
        }
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let includeTitle = UserDefaults.standard.object(forKey: UpcomingMeetingSupport.showTitleKey) == nil
            || UserDefaults.standard.bool(forKey: UpcomingMeetingSupport.showTitleKey)
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            button.title = " Calendar access"
            button.toolTip = "Allow calendar access in Vorssaint Settings → Menu bar."
        } else if CalendarSelectionSupport.selected() == nil {
            button.title = " Choose calendars"
            button.toolTip = "Select which calendars should appear in upcoming meetings."
        } else if let event = events.first {
            button.title = " " + UpcomingMeetingSupport.title(event, now: now, includeTitle: includeTitle)
            button.toolTip = event.title + "\n" + Self.dateLabel(event.start) + " – " + Self.timeLabel(event.end) + "\n" + event.calendar
        } else {
            button.title = loading ? " Meetings…" : " No meetings"
            button.toolTip = "Upcoming meetings from your selected calendars."
        }
        rebuildMenu(now: now)
    }

    private func rebuildMenu(now: Date) {
        menu.removeAllItems()
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            disabled("Calendar access is required")
        } else if CalendarSelectionSupport.selected() == nil {
            disabled("Choose calendars to show upcoming meetings")
        } else if CalendarSelectionSupport.selected()?.isEmpty == true {
            disabled("No calendars selected")
        } else if events.isEmpty {
            disabled(loading ? "Loading meetings…" : "No upcoming meetings in this time range")
        } else {
            for event in events.prefix(20) {
                let label = Self.dateLabel(event.start) + " · " + (event.title.isEmpty ? "Meeting" : event.title)
                let item = NSMenuItem(title: label, action: #selector(openEvent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = event.start
                item.toolTip = event.calendar + "\n" + Self.timeLabel(event.start) + " – " + Self.timeLabel(event.end)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let choose = NSMenuItem(title: "Choose calendars…", action: #selector(openSettings), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        let refresh = NSMenuItem(title: "Refresh meetings", action: #selector(manualRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
    }

    private func disabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) { render() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func manualRefresh() { refresh() }
    @objc private func openEvent(_ sender: NSMenuItem) {
        guard let date = sender.representedObject as? Date,
              let url = URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        permissionSubscription = nil
        reader = nil
        events = []
        loading = false
        lastSelection = nil
        menu.cancelTracking()
        menu.removeAllItems()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }
}
