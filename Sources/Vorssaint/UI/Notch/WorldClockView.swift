// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct WorldClockView: View {
    let size: CGSize
    var usesIslandHeader = true
    @ObservedObject private var clock = WorldClockMenuBarService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WorldClockSupport.primaryKey) private var primary = "UTC"
    @State private var anchor = Date()
    @State private var quarters = 0
    @State private var live = true
    @State private var editingZone: String?
    private var instant: Date { WorldClockSupport.shifted(anchor, minutes: Double(quarters * 15)) }
    private var localLabel: String {
        clock.zones.first { $0.timeZone.identifier == TimeZone.current.identifier }?.displayName
            ?? WorldClockSupport.city(TimeZone.current.identifier)
    }
    private var remoteZones: [WorldClockZone] {
        let remote = clock.zones.filter { $0.timeZone.identifier != TimeZone.current.identifier }
        guard let chosen = remote.first(where: { $0.identifier == primary }) else { return remote }
        return [chosen] + remote.filter { $0.identifier != primary }
    }

    var body: some View {
        VStack(spacing: 14) {
            if !usesIslandHeader {
                HStack { Text("World clock").font(.headline); Spacer(); nowButton }
            }
            GeometryReader { geometry in
                let tileWidth = max(100, (geometry.size.width - 8) / 2)
                HStack(spacing: 8) {
                    clockTile(label: localLabel, zone: .current, local: true)
                        .frame(width: tileWidth)
                    if let selected = remoteZones.first {
                        clockTile(label: selected.displayName, zone: selected.timeZone, local: false)
                            .frame(width: tileWidth)
                    }
                }
            }
            .frame(height: 86)
            if remoteZones.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(remoteZones) { zone in
                            Button(zone.displayName) { primary = zone.identifier; WorldClockMenuBarService.shared.syncWithPreferences() }
                                .font(.caption)
                                .foregroundStyle(zone.identifier == primary ? .orange : .secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.primary.opacity(zone.identifier == primary ? 0.1 : 0.04), in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: 22)
            }
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // The timer's native drag/scroll control, pointer, edge fade,
                    // keyboard interaction and haptics are reused directly.
                    NotchTimerRuler(minutes: Binding(get: { quarters }, set: {
                        quarters = $0; live = false
                    }), label: "Time comparison", locale: .autoupdatingCurrent,
                    range: -96...96, labelEvery: 4,
                    tickLabel: { value in
                        WorldClockSupport.time(WorldClockSupport.shifted(anchor, minutes: Double(value * 15)), in: .current,
                                               twentyFourHour: clock.twentyFourHour)
                    }, valueDescription: { value in
                        let date = WorldClockSupport.shifted(anchor, minutes: Double(value * 15))
                        return WorldClockSupport.day(date, in: .current) + " " + WorldClockSupport.time(date, in: .current, twentyFourHour: clock.twentyFourHour)
                    })
                    .frame(height: 74)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(WorldClockSupport.time(instant, in: .current, twentyFourHour: clock.twentyFourHour))
                            .font(.system(size: 26, weight: .light, design: .rounded))
                            .monospacedDigit().foregroundStyle(.orange)
                            .contentTransition(.numericText())
                        Text(live ? "Now" : "Local time")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                HStack {
                    stepButton(-1)
                    Spacer()
                    Text("Click either tile to set its date and time")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    stepButton(1)
                }
            }
            Text("Drag or scroll the ruler · 15-minute steps · ±24 hours")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand { Text("World clock").font(.system(size: 13, weight: .medium)) } trailing: { nowButton }
        .onAppear { reset() }
        .onReceive(clock.$now) { date in if live { anchor = date } }
        .task {
            // An open island keeps a live reading even if its menu item is off.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if live { anchor = Date() }
            }
        }
    }

    private var nowButton: some View {
        Button(action: reset) {
            Text("Now").font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 26)
                .foregroundStyle(.orange)
                .background(.orange.opacity(0.18), in: Capsule())
        }.buttonStyle(NotchButtonStyle(cornerRadius: 13))
        .accessibilityLabel("Reset to current time")
    }

    private func reset() { anchor = Date(); quarters = 0; live = true }

    private func stepButton(_ direction: Int) -> some View {
        Button {
            quarters = min(96, max(-96, quarters + direction)); live = false
        } label: {
            Image(systemName: direction < 0 ? "gobackward.15" : "goforward.15")
                .font(.system(size: 16)).foregroundStyle(.orange)
                .frame(width: 28, height: 28)
        }.buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .accessibilityLabel(direction < 0 ? "Go back 15 minutes" : "Go forward 15 minutes")
    }

    private func clockTile(label: String, zone: TimeZone, local: Bool) -> some View {
        Button {
            anchor = instant
            quarters = 0
            live = false
            editingZone = zone.identifier
        } label: {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if local {
                    Text("LOCAL").font(.system(size: 7, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.primary.opacity(0.12), in: Capsule())
                }
            }
            Text(WorldClockSupport.time(instant, in: zone, twentyFourHour: clock.twentyFourHour))
                .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Text(WorldClockSupport.day(instant, in: zone))
                if !local { Text(WorldClockSupport.offsetLabel(minutes: WorldClockSupport.differenceMinutes(at: instant, from: .current, to: zone))) }
            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: quarters)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10))
        .accessibilityLabel("Set date and time in " + label)
        .accessibilityValue(WorldClockSupport.time(instant, in: zone, twentyFourHour: clock.twentyFourHour) + " · " + WorldClockSupport.day(instant, in: zone))
        .help("Set a date and time in " + zone.identifier)
        .popover(isPresented: Binding(get: { editingZone == zone.identifier }, set: { if !$0 { editingZone = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label).font(.headline)
                Text(zone.identifier).font(.caption).foregroundStyle(.secondary)
                WorldClockTileDatePicker(date: Binding(get: { instant }, set: {
                    anchor = $0; quarters = 0; live = false
                }), zone: zone, label: "Date and time in " + label)
                .frame(height: 26)
                Text("All timezone tiles update to the same moment.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Done") { editingZone = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(16).frame(width: 290)
        }
    }
}

/// Pin the native field's timezone explicitly; its dateValue is always one
/// absolute instant, regardless of which city's wall time the user edits.
private struct WorldClockTileDatePicker: NSViewRepresentable {
    @Binding var date: Date
    let zone: TimeZone
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.datePickerMode = .single
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.timeZone = zone
        if picker.dateValue != date { picker.dateValue = date }
        picker.setAccessibilityLabel(label)
        picker.setAccessibilityValueDescription(WorldClockSupport.day(date, in: zone) + " " + WorldClockSupport.time(date, in: zone))
    }
    final class Coordinator: NSObject {
        var parent: WorldClockTileDatePicker
        init(_ parent: WorldClockTileDatePicker) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}
