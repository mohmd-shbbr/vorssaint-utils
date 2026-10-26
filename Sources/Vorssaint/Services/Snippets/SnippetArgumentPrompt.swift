// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Prompt asynchronously: never hold the event-tap callback while a user types.
/// Nothing is persisted. Focus returns to the application that requested input.
enum SnippetArgumentPrompt {
    private static var session: ArgumentSession?

    @discardableResult
    static func request(_ snippet: TextSnippet,
                        completion: @escaping ([String: String]?) -> Void) -> Bool {
        guard Thread.isMainThread, session == nil,
              let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let arguments = SnippetArgumentSupport.arguments(in: snippet.replacement)
        guard !arguments.isEmpty else { completion([:]); return true }
        let prompt = ArgumentSession(snippet: snippet, arguments: arguments) { values in
            session = nil
            guard !target.isTerminated else { completion(nil); return }
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Never paste into another app if the user switched away.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                      !IsSecureEventInputEnabled() else { return }
                completion(values)
            }
        }
        session = prompt
        DispatchQueue.main.async { prompt.show() }
        return true
    }
}

/// A nonactivating panel receives keyboard input without activating Settings or
/// raising any other Vorssaint windows over the application being edited.
private final class ArgumentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

private final class ArgumentFormView: NSView {
    override var isFlipped: Bool { true }
}

private final class ArgumentSession: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let panel = ArgumentPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                                     styleMask: [.titled, .closable, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
    private let arguments: [SnippetArgumentSupport.Argument]
    private let completion: ([String: String]?) -> Void
    private var fields: [NSControl] = []
    private var readers: [() -> (String, String)] = []
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var finished = false

    init(snippet: TextSnippet, arguments: [SnippetArgumentSupport.Argument],
         completion: @escaping ([String: String]?) -> Void) {
        self.arguments = arguments
        self.completion = completion
        super.init()
        let strings = FeatureStrings.snippets(L10n.shared.language)
        panel.title = snippet.name.isEmpty ? strings.argumentTitle : snippet.name
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        hint.stringValue = strings.argumentHint
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        for (index, argument) in arguments.enumerated() {
            let label = argument.id.hasPrefix("position:") ? "\(strings.argumentField) \(index + 1)" : argument.name
            stack.addArrangedSubview(NSTextField(labelWithString: label + (argument.required ? " *" : "")))
            let control: NSControl
            if !argument.options.isEmpty {
                let field = NSPopUpButton()
                if argument.defaultValue == nil || argument.defaultValue == "" { field.addItem(withTitle: "") }
                field.addItems(withTitles: argument.options)
                if let value = argument.defaultValue { field.selectItem(withTitle: value) }
                readers.append { (argument.id, field.titleOfSelectedItem ?? "") }
                control = field
            } else {
                let field: NSTextField = argument.password ? NSSecureTextField() : NSTextField()
                field.stringValue = argument.defaultValue ?? ""
                field.placeholderString = label
                field.delegate = self
                readers.append { (argument.id, field.stringValue) }
                control = field
            }
            control.widthAnchor.constraint(equalToConstant: 392).isActive = true
            fields.append(control)
            stack.addArrangedSubview(control)
        }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        let cancel = NSButton(title: L10n.shared.s.uninstallerCancel, target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let insert = NSButton(title: strings.argumentInsert, target: self, action: #selector(insert))
        insert.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(insert)
        stack.addArrangedSubview(buttons)
        // Scroll long forms rather than placing fields off screen.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let document = ArgumentFormView()
        scroll.documentView = document
        document.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalToConstant: 392)
        ])
        document.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 40
        document.setFrameSize(NSSize(width: 440, height: height))
        panel.contentView = scroll
        panel.setContentSize(NSSize(width: 440, height: min(600, height)))
        for (index, field) in fields.enumerated() {
            field.nextKeyView = index + 1 < fields.count ? fields[index + 1] : insert
        }
        insert.nextKeyView = cancel
        cancel.nextKeyView = fields.first
        panel.initialFirstResponder = fields.first
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(fields.first)
    }

    @objc private func insert() {
        let values = Dictionary(uniqueKeysWithValues: readers.map { $0() })
        guard SnippetArgumentSupport.isValid(values, for: arguments) else {
            hint.stringValue = FeatureStrings.snippets(L10n.shared.language).argumentInvalid
            if let index = arguments.firstIndex(where: { $0.required && (values[$0.id] ?? "").isEmpty }) {
                panel.makeFirstResponder(fields[index])
            }
            NSSound.beep()
            return
        }
        finish(values)
    }

    @objc private func cancel() { finish(nil) }
    func windowWillClose(_ notification: Notification) { finish(nil) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { insert(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        return false
    }

    private func finish(_ values: [String: String]?) {
        guard !finished else { return }
        finished = true
        panel.orderOut(nil)
        panel.close()
        completion(values)
    }
}
