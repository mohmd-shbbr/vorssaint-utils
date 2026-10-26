// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Native rich editing keeps pasted links and paragraph styles. The plain
/// string is also retained for search, variables, and plain-text destinations.
struct RichSnippetEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var text: String
    @Binding var rtf: Data?
    @Binding var selectedRange: Range<Int>?
    var onCreate: (NSTextView) -> Void
    @State private var editor: NSTextView?
    @State private var showingArgument = false
    @State private var argumentInitial: SnippetArgumentSupport.Occurrence?
    @State private var argumentRange = NSRange(location: 0, length: 0)
    @State private var argumentSnapshot = ""
    @State private var showingLink = false
    @State private var linkURL = ""
    @State private var linkRange = NSRange(location: 0, length: 0)

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                tool("bold") { toggleFont(.boldFontMask) }
                tool("italic") { toggleFont(.italicFontMask) }
                tool("underline") { toggleAttribute(.underlineStyle) }
                tool("strikethrough") { toggleAttribute(.strikethroughStyle) }
                Divider().frame(height: 16)
                tool("list.bullet") { applyList(numbered: false) }
                tool("list.number") { applyList(numbered: true) }
                tool("link") {
                    guard let editor else { return }
                    linkRange = editor.selectedRange()
                    guard linkRange.length > 0 else { NSSound.beep(); return }
                    linkURL = editor.textStorage?.attribute(.link, at: linkRange.location, effectiveRange: nil)
                        .map { String(describing: $0) } ?? ""
                    showingLink = true
                }
                .popover(isPresented: $showingLink) {
                    HStack {
                        TextField("URL", text: $linkURL).frame(width: 240)
                        Button {
                            let value = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard value.isEmpty || URL(string: value)?.scheme != nil else { NSSound.beep(); return }
                            edit(range: linkRange) { storage in
                                if value.isEmpty { storage.removeAttribute(.link, range: linkRange) }
                                else { storage.addAttribute(.link, value: value, range: linkRange) }
                            }
                            showingLink = false
                        } label: { Image(systemName: "checkmark") }
                    }.padding(10)
                }
                Menu {
                    Button { editor?.alignLeft(nil) } label: { Image(systemName: "text.alignleft") }
                    Button { editor?.alignCenter(nil) } label: { Image(systemName: "text.aligncenter") }
                    Button { editor?.alignRight(nil) } label: { Image(systemName: "text.alignright") }
                    Button { editor?.alignJustified(nil) } label: { Image(systemName: "text.justify") }
                } label: { Image(systemName: "text.alignleft") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                tool("textformat.size") {
                    focus()
                    NSFontManager.shared.orderFrontFontPanel(nil)
                }
                tool("paintpalette") {
                    focus()
                    NSColorPanel.shared.setTarget(editor)
                    NSColorPanel.shared.setAction(#selector(NSTextView.changeColor(_:)))
                    NSColorPanel.shared.orderFront(nil)
                }
                Button {
                    openArgument(at: editor?.selectedRange() ?? NSRange(location: 0, length: 0))
                } label: {
                    Label(detectedArgument == nil ? strings.argumentField : strings.argumentEditLabel,
                          systemImage: detectedArgument == nil ? "plus" : "slider.horizontal.3")
                }
                .popover(isPresented: $showingArgument) {
                    SnippetArgumentBuilder(strings: strings, cancelLabel: l10n.s.uninstallerCancel,
                                           initial: argumentInitial?.argument,
                                           confirm: { token in applyArgument(token); showingArgument = false },
                                           cancel: { showingArgument = false })
                }
                Spacer(minLength: 0)
            }.buttonStyle(.borderless).padding(5)
            Text(FeatureStrings.snippets(l10n.language).richTextHint)
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 5)
            if !SnippetArgumentSupport.occurrences(in: text).isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(SnippetArgumentSupport.occurrences(in: text), id: \.range.location) { occurrence in
                            Button { openArgument(at: occurrence.range) } label: {
                                Label(occurrence.argument.name, systemImage: "slider.horizontal.3")
                                    .font(.caption)
                            }.help(strings.argumentEditLabel)
                        }
                    }
                }.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 5)
            }
            RichSnippetTextView(text: $text, rtf: $rtf, selectedRange: $selectedRange) {
                editor = $0
                onCreate($0)
            }
        }
    }

    private var strings: SnippetFeatureStrings { FeatureStrings.snippets(l10n.language) }

    private var detectedArgument: SnippetArgumentSupport.Occurrence? {
        let range = TextSnippetSupport.selectionRange(in: text, offsets: selectedRange)
        return SnippetArgumentSupport.occurrence(in: text, selection: NSRange(range, in: text))
    }

    private func openArgument(at selection: NSRange) {
        guard let editor else { return }
        argumentSnapshot = editor.string
        argumentInitial = SnippetArgumentSupport.occurrence(in: editor.string, selection: selection)
        argumentRange = argumentInitial?.range ?? selection
        showingArgument = true
    }

    private func applyArgument(_ token: String) {
        guard let editor, let storage = editor.textStorage, editor.string == argumentSnapshot else { NSSound.beep(); return }
        let ranges: [NSRange]
        if let initial = argumentInitial, initial.argument.id.hasPrefix("name:") {
            // Repeated named placeholders configure one input, so edit all of them.
            ranges = SnippetArgumentSupport.occurrences(in: editor.string)
                .filter { $0.argument.id == initial.argument.id }.map(\.range)
        } else { ranges = [argumentRange] }
        guard editor.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                                    replacementStrings: ranges.map { _ in token }) else { return }
        storage.beginEditing()
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let attributes = range.location < storage.length
                ? storage.attributes(at: range.location, effectiveRange: nil) : editor.typingAttributes
            storage.replaceCharacters(in: range, with: NSAttributedString(string: token, attributes: attributes))
        }
        storage.endEditing()
        editor.didChangeText()
        let tokenLength = (token as NSString).length
        let shift = ranges.filter { $0.location < argumentRange.location }.reduce(0) { $0 + tokenLength - $1.length }
        editor.setSelectedRange(NSRange(location: min(storage.length, argumentRange.location + shift + tokenLength), length: 0))
        focus()
    }

    private func tool(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 21, height: 20) }
    }

    private func focus() {
        guard let editor else { return }
        editor.window?.makeFirstResponder(editor)
    }

    private func edit(range: NSRange, _ change: (NSTextStorage) -> Void) {
        guard let editor, let storage = editor.textStorage,
              NSMaxRange(range) <= storage.length,
              editor.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        editor.didChangeText()
        focus()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key) {
        guard let editor else { return }
        let range = editor.selectedRange()
        let current = range.length > 0
            ? editor.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int
            : editor.typingAttributes[key] as? Int
        let value = current == NSUnderlineStyle.single.rawValue ? 0 : NSUnderlineStyle.single.rawValue
        if range.length == 0 { editor.typingAttributes[key] = value; focus() }
        else { edit(range: range) { $0.addAttribute(key, value: value, range: range) } }
    }

    private func toggleFont(_ trait: NSFontTraitMask) {
        guard let editor, let storage = editor.textStorage else { return }
        let range = editor.selectedRange()
        let manager = NSFontManager.shared
        let first = range.length > 0
            ? storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : editor.typingAttributes[.font] as? NSFont
        let removing = first.map { manager.traits(of: $0).contains(trait) } ?? false
        func converted(_ font: NSFont) -> NSFont {
            removing ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
        }
        if range.length == 0 {
            editor.typingAttributes[.font] = converted(first ?? RichSnippetSupport.defaultFont)
            focus()
        } else {
            edit(range: range) { storage in
                let copy = NSAttributedString(attributedString: storage)
                copy.enumerateAttribute(.font, in: range) { font, run, _ in
                    storage.addAttribute(.font, value: converted(font as? NSFont ?? RichSnippetSupport.defaultFont), range: run)
                }
            }
        }
    }

    private func applyList(numbered: Bool) {
        guard let editor, let storage = editor.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: editor.selectedRange())
        let list = NSTextList(markerFormat: numbered ? .decimal : .disc, options: 0)
        let snapshot = storage.string as NSString
        var paragraphs: [NSRange] = []
        var offset = range.location
        repeat {
            let paragraph = snapshot.paragraphRange(for: NSRange(location: offset, length: 0))
            paragraphs.append(paragraph)
            offset = NSMaxRange(paragraph)
        } while offset < NSMaxRange(range)
        let existing = range.location < storage.length
            ? storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
        let removing = existing?.textLists.first?.markerFormat == list.markerFormat
        edit(range: range) { storage in
            for paragraph in paragraphs.reversed() {
                let style = (paragraph.location < storage.length
                    ? storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                    : nil)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                // Modern NSTextView draws markers from NSTextList metadata;
                // inserting literal bullets here would draw each marker twice.
                style.textLists = removing ? [] : [list]
                style.headIndent = removing ? 0 : 28
                style.firstLineHeadIndent = 0
                storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                if paragraph.length == 0 { editor.typingAttributes[.paragraphStyle] = style }
            }
        }
    }
}

private struct RichSnippetTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var rtf: Data?
    @Binding var selectedRange: Range<Int>?
    var onCreate: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFontPanel = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.font = RichSnippetSupport.defaultFont
        if let rich = RichSnippetSupport.decode(rtf, matching: text) { view.textStorage?.setAttributedString(rich) }
        else { view.string = text }
        view.delegate = context.coordinator
        DispatchQueue.main.async { onCreate(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text, !view.hasMarkedText() else { return }
        context.coordinator.updating = true
        if let rich = RichSnippetSupport.decode(rtf, matching: text) { view.textStorage?.setAttributedString(rich) }
        else { view.string = text }
        view.undoManager?.removeAllActions()
        context.coordinator.updating = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichSnippetTextView
        var updating = false
        init(_ parent: RichSnippetTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            parent.rtf = RichSnippetSupport.encode(view.attributedString())
            parent.text = view.string
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView,
                  let range = Range(view.selectedRange(), in: view.string) else { return }
            let start = view.string.distance(from: view.string.startIndex, to: range.lowerBound)
            let end = view.string.distance(from: view.string.startIndex, to: range.upperBound)
            parent.selectedRange = start..<end
        }
    }
}
