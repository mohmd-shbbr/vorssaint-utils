// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

/// Shared by Menu Bar and Dynamic Island settings. The explicit allow-list
/// keeps calendars added later from silently appearing in the meeting list.
struct NotchCalendarSelection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var choices: [NotchCalendarChoice] = []
    @State private var selected = CalendarSelectionSupport.selected()
    @State private var loading = true

    var body: some View {
        let groups = NotchCalendarSupport.grouped(choices)
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(FeatureStrings.notchCalendar(l10n.language).calendars).font(.subheadline.weight(.medium))
            Text("Used by upcoming meetings in the menu bar and the Dynamic Island calendar. New calendars stay hidden after you make a selection.")
                .font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView().controlSize(.small) }
            else if groups.isEmpty {
                Text("No calendars are available. Add an account in macOS Calendar settings, then refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Select all") { save(Set(choices.map(\.id))) }
                    Button("Clear all") { save([]) }
                    if selected == nil {
                        Button("Use these calendars") { save(currentSelection) }
                    }
                }
                ForEach(groups, id: \.first?.sourceID) { group in
                    if let source = group.first?.source, !source.isEmpty {
                        Text(source).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    ForEach(group) { choice in
                        Toggle(isOn: shown(choice.id)) {
                            HStack(spacing: 6) {
                                Circle().fill(choice.color.color).frame(width: 8, height: 8)
                                Text(choice.title).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(choice.title)
                    }
                }
            }
            Button("Refresh calendars") { Task { await reload() } }
                .disabled(loading)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarSelectionSupport.changed)) { _ in
            selected = CalendarSelectionSupport.selected()
        }
    }

    private var currentSelection: Set<String> {
        selected ?? Set(choices.map(\.id)).subtracting(NotchCalendarSupport.excludedCalendars())
    }

    private func reload() async {
        loading = true
        choices = await NotchCalendarService.shared.calendarChoices()
        selected = CalendarSelectionSupport.selected()
        loading = false
    }

    private func save(_ identifiers: Set<String>) {
        CalendarSelectionSupport.store(identifiers)
        selected = identifiers
        NotchCalendarService.shared.syncWithPreferences()
        UpcomingMeetingMenuBarService.shared.syncWithPreferences()
    }

    private func shown(_ identifier: String) -> Binding<Bool> {
        Binding(get: { currentSelection.contains(identifier) }, set: { shown in
            var updated = currentSelection
            if shown { updated.insert(identifier) } else { updated.remove(identifier) }
            save(updated)
        })
    }
}
