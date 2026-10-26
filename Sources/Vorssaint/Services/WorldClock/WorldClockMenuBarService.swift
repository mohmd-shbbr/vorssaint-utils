// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class WorldClockMenuBarService: NSObject, ObservableObject {
    static let shared = WorldClockMenuBarService()
    @Published private(set) var now = Date()
    @Published private(set) var zones: [WorldClockZone] = []
    @Published private(set) var twentyFourHour = true
    private var item: NSStatusItem?
    private var stackedTitle: WorldClockStatusTitleView?
    private var popover: NSPopover?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncWithPreferences()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        syncWithPreferences()
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let saved = WorldClockSupport.savedZones()
        if zones != saved { zones = saved }
        let format = defaults.object(forKey: WorldClockSupport.twentyFourHourKey) as? Bool ?? true
        if twentyFourHour != format { twentyFourHour = format }
        guard defaults.bool(forKey: WorldClockSupport.enabledKey) else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            stackedTitle = nil
            timer?.invalidate()
            timer = nil
            popover?.close()
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "VorssaintWorldClock"
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            item.button?.setAccessibilityLabel("World clock")
            if let button = item.button {
                let title = WorldClockStatusTitleView(frame: button.bounds)
                title.autoresizingMask = [.width, .height]
                title.setAccessibilityElement(false)
                button.addSubview(title)
                stackedTitle = title
            }
            self.item = item
        }
        if timer == nil {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        stackedTitle = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        started = false
    }

    private func refresh() {
        now = Date()
        let primaryID = UserDefaults.standard.string(forKey: WorldClockSupport.primaryKey)
        guard let primary = zones.first(where: { $0.identifier == primaryID }) ?? zones.first else { return }
        let label = String(primary.displayName.prefix(10))
        let time = WorldClockSupport.time(now, in: primary.timeZone, twentyFourHour: twentyFourHour)
        stackedTitle?.label = label
        stackedTitle?.time = time
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let timeWidth = NSAttributedString(string: time, attributes: [.font: font]).size().width
        let labelWidth = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 8.5, weight: .semibold)]).size().width
        item?.length = ceil(max(34, max(timeWidth, labelWidth) + 8))
        item?.button?.title = ""
        item?.button?.setAccessibilityValue(label + " " + time)
        stackedTitle?.needsDisplay = true
        item?.button?.toolTip = "World clock · \(primary.identifier)\nClick to compare times in Dynamic Island"
    }

    @objc private func clicked() {
        if AppFeature.notch.isAvailable, NotchSupport.isEnabled(), NotchService.shared.openWorldClock() { return }
        // World time remains usable if Dynamic Island has been switched off.
        guard let button = item?.button else { return }
        if popover?.isShown == true { popover?.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 360)
        popover.contentViewController = NSHostingController(rootView: WorldClockView(size: NSSize(width: 460, height: 360), usesIslandHeader: false).padding(16))
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

/// The button retains native menu-bar click and highlight handling; its
/// content uses the same compact two-line arrangement as a system clock.
private final class WorldClockStatusTitleView: NSView {
    var label = ""
    var time = ""
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let top = max(0, (bounds.height - 23) / 2)
        NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: style
        ]).draw(in: NSRect(x: 0, y: top, width: bounds.width, height: 11))
        NSAttributedString(string: time, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: style
        ]).draw(in: NSRect(x: 0, y: top + 10, width: bounds.width, height: 13))
    }
}
