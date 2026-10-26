// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Prompt asynchronously: never hold the event-tap callback while a user types.
/// Nothing is persisted. Focus returns to the application that requested input.
enum SnippetArgumentPrompt {
    private static var isPresenting = false

    @discardableResult
    static func request(_ snippet: TextSnippet,
                        completion: @escaping ([String: String]?) -> Void) -> Bool {
        guard Thread.isMainThread, !isPresenting,
              let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let arguments = SnippetArgumentSupport.arguments(in: snippet.replacement)
        guard !arguments.isEmpty else { completion([:]); return true }
        isPresenting = true
        DispatchQueue.main.async {
            let strings = FeatureStrings.snippets(L10n.shared.language)
            let alert = NSAlert()
            alert.messageText = snippet.name.isEmpty ? strings.argumentTitle : snippet.name
            alert.informativeText = strings.argumentHint
            alert.addButton(withTitle: strings.argumentInsert)
            alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            var readValues: [() -> (String, String)] = []
            for (index, argument) in arguments.enumerated() {
                let label = argument.id.hasPrefix("position:") ? "\(strings.argumentField) \(index + 1)" : argument.name
                stack.addArrangedSubview(NSTextField(labelWithString: label + (argument.required ? " *" : "")))
                if !argument.options.isEmpty {
                    let field = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
                    if argument.defaultValue == nil || argument.defaultValue == "" { field.addItem(withTitle: "") }
                    field.addItems(withTitles: argument.options)
                    if let value = argument.defaultValue { field.selectItem(withTitle: value) }
                    stack.addArrangedSubview(field)
                    readValues.append { (argument.id, field.titleOfSelectedItem ?? "") }
                } else {
                    let field: NSTextField = argument.password ? NSSecureTextField() : NSTextField()
                    field.stringValue = argument.defaultValue ?? ""
                    field.placeholderString = label
                    field.widthAnchor.constraint(equalToConstant: 340).isActive = true
                    stack.addArrangedSubview(field)
                    readValues.append { (argument.id, field.stringValue) }
                }
            }
            alert.accessoryView = stack
            stack.layoutSubtreeIfNeeded()
            stack.setFrameSize(NSSize(width: 340, height: stack.fittingSize.height))
            NSApp.activate()
            var values: [String: String]?
            while alert.runModal() == .alertFirstButtonReturn {
                let entered = Dictionary(uniqueKeysWithValues: readValues.map { $0() })
                if SnippetArgumentSupport.isValid(entered, for: arguments) { values = entered; break }
                alert.informativeText = strings.argumentInvalid
                NSSound.beep()
            }
            isPresenting = false
            guard !target.isTerminated else { completion(nil); return }
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // If focus changed or secure input began, do not type elsewhere.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                      !IsSecureEventInputEnabled() else { return }
                completion(values)
            }
        }
        return true
    }
}
