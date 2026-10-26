// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

struct CalendarMenuBarSettings: View {
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(UpcomingMeetingSupport.enabledKey) private var enabled = false
    @AppStorage(UpcomingMeetingSupport.showTitleKey) private var showTitle = true
    @AppStorage(UpcomingMeetingSupport.leadMinutesKey) private var leadMinutes = 1440

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming meetings").font(.headline)
            Toggle("Show upcoming meetings in the menu bar", isOn: $enabled)
            Text("Show the next timed event and its countdown. All-day, canceled and declined events stay out of the meeting list.")
                .font(.caption).foregroundStyle(.secondary)
            if enabled {
                Toggle("Show the meeting title", isOn: $showTitle)
                Picker("Look ahead", selection: $leadMinutes) {
                    Text("1 hour").tag(60)
                    Text("6 hours").tag(360)
                    Text("24 hours").tag(1440)
                    Text("7 days").tag(10080)
                }
                .fixedSize()
            }
            if permissions.calendarAccess == .fullAccess {
                NotchCalendarSelection()
            } else {
                Text("Allow calendar access to choose individual calendars. Selection is shared with the Dynamic Island calendar.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Allow calendar access", action: permissions.requestCalendar)
                        .disabled(permissions.requestingCalendar)
                    Button("Open calendar privacy settings", action: permissions.openCalendarSettings)
                }
            }
        }
        .onChange(of: enabled) { _, _ in UpcomingMeetingMenuBarService.shared.syncWithPreferences() }
        .onChange(of: showTitle) { _, _ in UpcomingMeetingMenuBarService.shared.syncWithPreferences() }
        .onChange(of: leadMinutes) { _, _ in UpcomingMeetingMenuBarService.shared.syncWithPreferences() }
    }
}
