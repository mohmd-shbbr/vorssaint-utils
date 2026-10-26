// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WorldClockSettings: View {
    @AppStorage(WorldClockSupport.enabledKey) private var enabled = false
    @AppStorage(WorldClockSupport.twentyFourHourKey) private var twentyFourHour = true
    @AppStorage(WorldClockSupport.primaryKey) private var primary = "UTC"
    @State private var zones = WorldClockSupport.savedZones()
    @State private var search = ""
    @State private var selection = "UTC"
    private var matches: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter {
            search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        SettingsCard(title: "World clock") {
            Toggle("Show world time in the menu bar", isOn: $enabled)
            Text("Click the clock to open the time-comparison slider in Dynamic Island. Time differences follow daylight saving for your selected date.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Use a 24-hour clock", isOn: $twentyFourHour)
            Picker("Menu bar timezone", selection: $primary) {
                ForEach(zones) { zone in Text(zone.displayName).tag(zone.identifier) }
            }
            Divider()
            ForEach(zones) { zone in
                HStack {
                    TextField("Label", text: Binding(get: { zones.first(where: { $0.id == zone.id })?.label ?? "" }, set: { value in
                        if let index = zones.firstIndex(where: { $0.id == zone.id }) { zones[index].label = value; save() }
                    }))
                    Text(zone.identifier).font(.caption).foregroundStyle(.secondary)
                    Button {
                        zones.removeAll { $0.id == zone.id }
                        if primary == zone.id { primary = zones.first?.id ?? "UTC" }
                        save()
                    } label: { Image(systemName: "minus.circle") }
                    .disabled(zones.count == 1)
                    .accessibilityLabel("Remove \(zone.displayName)")
                }
            }
            TextField("Search city or timezone", text: $search)
            HStack {
                Picker("Add timezone", selection: $selection) {
                    if !matches.contains(selection) { Text(selection).tag(selection) }
                    ForEach(matches, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                Button("Add") {
                    guard TimeZone(identifier: selection) != nil, !zones.contains(where: { $0.id == selection }) else { return }
                    zones.append(WorldClockZone(identifier: selection, label: WorldClockSupport.city(selection)))
                    save()
                }.disabled(zones.contains(where: { $0.id == selection }))
            }
            .onChange(of: search) { _, _ in if let match = matches.first { selection = match } }
            Button("Preview time comparison") { _ = NotchService.shared.openWorldClock() }
        }
        .onChange(of: enabled) { _, _ in WorldClockMenuBarService.shared.syncWithPreferences() }
        .onChange(of: twentyFourHour) { _, _ in WorldClockMenuBarService.shared.syncWithPreferences() }
        .onChange(of: primary) { _, _ in WorldClockMenuBarService.shared.syncWithPreferences() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(zones) { UserDefaults.standard.set(data, forKey: WorldClockSupport.zonesKey) }
        WorldClockMenuBarService.shared.syncWithPreferences()
    }
}
