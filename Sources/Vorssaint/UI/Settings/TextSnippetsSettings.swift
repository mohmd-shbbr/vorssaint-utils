// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The text snippets page: the enable toggle, the snippet list and a simple
/// editor sheet. Edits persist to defaults and nudge the service, so a change
/// works on the very next keystroke.
struct TextSnippetsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var library = SnippetLibraryService.shared
    @ObservedObject private var secureInput = SecureInputMonitor.shared
    @AppStorage(DefaultsKey.textSnippetsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.snippetLibraryEnabled) private var libraryEnabled = false
    @AppStorage(DefaultsKey.snippetSoundEnabled) private var soundEnabled = false
    @AppStorage(DefaultsKey.snippetSoundName) private var soundName = Defaults.defaultSnippetSoundName
    @State private var snippets: [TextSnippet] = TextSnippetSupport.decode(
        UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
    @State private var editing: TextSnippet?
    @State private var creating = false

    private var text: SnippetFeatureStrings {
        FeatureStrings.snippets(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        TextSnippetService.shared.syncWithPreferences()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
                if enabled {
                    Toggle(text.soundToggle, isOn: $soundEnabled)
                        .onChange(of: soundEnabled) { _, _ in
                            TextSnippetService.shared.syncExpansionSound()
                        }
                    Text(text.soundCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if soundEnabled {
                        Picker(text.soundPickerLabel, selection: $soundName) {
                            ForEach(AlertSoundStrings.sortedNames(TextSnippetSupport.alertSoundNames,
                                                                  language: l10n.language), id: \.self) { name in
                                Text(AlertSoundStrings.displayName(for: name, language: l10n.language)).tag(name)
                            }
                            // A name stored on another Mac, or dropped by a
                            // macOS update, needs a row of its own or the
                            // picker shows an empty selection. Asked through
                            // the same resolver the service arms the sound
                            // with, so the row cannot call a name usable that
                            // an expansion would substitute away from.
                            if TextSnippetSupport.resolvedSoundName(stored: soundName) != soundName {
                                Text(text.soundUnavailable).tag(soundName)
                            }
                        }
                        .onChange(of: soundName) { _, _ in
                            TextSnippetService.shared.syncExpansionSound()
                            TextSnippetService.shared.previewExpansionSound()
                        }
                    }
                }
            }

            Section {
                Toggle(text.libraryToggle, isOn: $libraryEnabled)
                    .onChange(of: libraryEnabled) { _, _ in
                        SnippetLibraryService.shared.syncWithPreferences()
                    }
                Text(text.libraryCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if libraryEnabled {
                    ShortcutPreferenceRow(role: .snippetLibrary,
                                          isEnabled: libraryEnabled) {
                        SnippetLibraryService.shared.syncWithPreferences()
                    }
                    if library.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text(text.libraryTitle)
            }

            // The library beeps under secure input whether or not trigger
            // expansion is on, so either toggle earns the explanation. It
            // answers to both, so it sits under both rather than inside the
            // section for one of them.
            if enabled || libraryEnabled, secureInput.holder != .off {
                Section { SecureInputRow() }
            }

            Section {
                if snippets.isEmpty {
                    Text(text.emptyList)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(snippets) { snippet in
                    SnippetRow(snippet: snippet,
                               modeLabel: snippet.expansion == .immediate
                                   ? text.expansionImmediate
                                   : text.expansionDelimiter,
                               toggle: { setEnabled($0, id: snippet.id) },
                               edit: { editing = snippet })
                }
                Button {
                    creating = true
                } label: {
                    Label(text.addButton, systemImage: "plus")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.variablesHint)
                    Text(text.variablesCaption)
                    Text(text.variablesFormatCaption)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .observesSecureInput(isActive: enabled || libraryEnabled)
        .sheet(isPresented: $creating) {
            SnippetEditor(text: text,
                          snippet: TextSnippet(),
                          isNew: true,
                          others: snippets,
                          save: { upsert($0) },
                          delete: nil)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(text: text,
                          snippet: snippet,
                          isNew: false,
                          others: snippets.filter { $0.id != snippet.id },
                          save: { upsert($0) },
                          delete: { remove(id: snippet.id) })
        }
    }

    private func upsert(_ snippet: TextSnippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        persist()
    }

    private func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    private func setEnabled(_ on: Bool, id: UUID) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[index].enabled = on
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(TextSnippetSupport.encode(snippets),
                                  forKey: DefaultsKey.textSnippets)
        TextSnippetService.shared.syncWithPreferences()
        SnippetLibraryService.shared.syncWithPreferences()
    }
}

private struct SnippetRow: View {
    let snippet: TextSnippet
    let modeLabel: String
    let toggle: (Bool) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(snippet.name.isEmpty ? snippet.trigger : snippet.name)
                            .fontWeight(.medium)
                        Text(snippet.trigger)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                        if !snippet.folder.isEmpty {
                            Label(snippet.folder, systemImage: "folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text(modeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Toggle("", isOn: Binding(get: { snippet.enabled }, set: toggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 1)
    }

    private var preview: String {
        snippet.replacement.replacingOccurrences(of: "\n", with: " ")
    }
}

/// Holds the replacement field's text view so the date/time builder can
/// edit through it. Weak, since the view belongs to the editor sheet.
private final class EditorHandle {
    weak var view: NSTextView?
}

private struct SnippetEditor: View {
    let text: SnippetFeatureStrings
    @State var snippet: TextSnippet
    let isNew: Bool
    let others: [TextSnippet]
    let save: (TextSnippet) -> Void
    let delete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var replacementSelection: Range<Int>?
    @State private var showingDateBuilder = false
    @State private var dateBuilderInitial: TextSnippetSupport.DetectedDateToken?
    /// @State so the handle outlives a view rebuild, and a class so the
    /// text view can be stored into it while it is being made without
    /// publishing a change from inside a view update.
    @State private var replacementEditor = EditorHandle()

    private var sanitizedTrigger: String {
        TextSnippetSupport.sanitizedTrigger(snippet.trigger)
    }

    private var triggerTooShort: Bool {
        sanitizedTrigger.count < 2
    }

    private var duplicateTrigger: Bool {
        others.contains { other in
            if snippet.ignoresCase || other.ignoresCase {
                return other.trigger.compare(sanitizedTrigger, options: .caseInsensitive) == .orderedSame
            }
            return other.trigger == sanitizedTrigger
        }
    }

    private var folderSuggestions: [String] {
        TextSnippetSupport.folderSuggestions(others)
    }

    private var selectedRange: Range<String.Index> {
        TextSnippetSupport.selectionRange(in: snippet.replacement,
                                          offsets: replacementSelection)
    }

    private var detectedTokenAtCursor: TextSnippetSupport.DetectedDateToken? {
        TextSnippetSupport.dateToken(in: snippet.replacement, at: selectedRange.lowerBound)
    }

    /// Splices the built token into the replacement text, replacing an
    /// existing token in edit mode or the current selection otherwise.
    /// Edits through the text view rather than the binding so the insert
    /// joins its undo stack and leaves the caret after the token; going
    /// through the binding replaces the whole string, which drops the
    /// caret at the end and discards everything the user could undo.
    private func insertDateToken(_ tokenText: String) {
        let text = snippet.replacement
        let range = TextSnippetSupport.selectionRange(
            in: text, offsets: dateBuilderInitial?.offsets ?? replacementSelection)
        guard let textView = replacementEditor.view else {
            snippet.replacement.replaceSubrange(range, with: tokenText)
            return
        }
        let target = NSRange(range, in: text)
        guard textView.shouldChangeText(in: target, replacementString: tokenText) else { return }
        textView.replaceCharacters(in: target, with: tokenText)
        textView.didChangeText()
        textView.setSelectedRange(
            NSRange(location: target.location + (tokenText as NSString).length, length: 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? text.newTitle : text.editTitle)
                .font(.headline)
            Form {
                TextField(text.nameLabel, text: $snippet.name, prompt: Text(text.namePlaceholder))
                TextField(text.triggerLabel, text: $snippet.trigger, prompt: Text(text.triggerPlaceholder))
                    .font(.body.monospaced())
                Picker(text.expansionLabel, selection: $snippet.expansion) {
                    Text(text.expansionDelimiter).tag(TextSnippet.Expansion.afterDelimiter)
                    Text(text.expansionImmediate).tag(TextSnippet.Expansion.immediate)
                }
                Toggle(text.ignoreCaseLabel, isOn: $snippet.ignoresCase)
                HStack(spacing: 6) {
                    TextField(text.folderLabel, text: $snippet.folder, prompt: Text(text.folderPlaceholder))
                    if !folderSuggestions.isEmpty {
                        Menu {
                            ForEach(folderSuggestions, id: \.self) { name in
                                Button(name) { snippet.folder = name }
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                Toggle(text.showInLibraryLabel, isOn: $snippet.showsInLibrary)
            }
            .formStyle(.columns)
            .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(text.replacementLabel)
                        Spacer()
                        Button {
                            dateBuilderInitial = detectedTokenAtCursor
                            showingDateBuilder = true
                        } label: {
                            Label(detectedTokenAtCursor == nil ? text.dateTimeInsertButton : text.dateTimeEditButton,
                                  systemImage: "calendar.badge.plus")
                        }
                        .popover(isPresented: $showingDateBuilder) {
                            DateVariableBuilder(
                                text: text,
                                cancelLabel: l10n.s.uninstallerCancel,
                                locale: .current,
                                initial: dateBuilderInitial,
                                confirm: { tokenText in
                                    insertDateToken(tokenText)
                                    showingDateBuilder = false
                                },
                                cancel: { showingDateBuilder = false }
                            )
                            .frame(width: 340)
                        }
                    }
                    RichSnippetEditor(text: $snippet.replacement,
                                    rtf: $snippet.richReplacement,
                                    selectedRange: $replacementSelection,
                                    onCreate: { replacementEditor.view = $0 })
                        .frame(minHeight: 220, maxHeight: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                    Text(text.variablesHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text.editorFormatCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if triggerTooShort, !snippet.trigger.isEmpty {
                Text(text.triggerTooShort)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if duplicateTrigger {
                Text(text.duplicateTrigger)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                if let delete {
                    Button(role: .destructive) {
                        delete()
                        dismiss()
                    } label: {
                        Text(text.deleteButton)
                    }
                }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                Button(text.saveButton) {
                    var saved = snippet
                    saved.trigger = sanitizedTrigger
                    saved.name = snippet.name.trimmingCharacters(in: .whitespaces)
                    saved.folder = TextSnippetSupport.sanitizedFolder(snippet.folder)
                    save(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(triggerTooShort || duplicateTrigger || snippet.replacement.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity,
               minHeight: 600, idealHeight: 740, maxHeight: .infinity)
        .background(SnippetEditorWindowSizing())
    }
}

/// Let the native sheet resize in both dimensions. The text area fills the
/// available space instead of occupying the metadata form's narrow column.
private struct SnippetEditorWindowSizing: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizingView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class SizingView: NSView {
        private weak var configuredWindow: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window !== self.configuredWindow else { return }
                self.configuredWindow = window
                window.styleMask.insert(.resizable)
                window.contentMinSize = NSSize(width: 640, height: 600)
                let visible = window.screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
                window.setContentSize(NSSize(width: min(760, visible.width - 80), height: min(740, visible.height - 100)))
            }
        }
    }
}
