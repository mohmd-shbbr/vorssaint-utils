// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Runs the production expansion routine against recorded key events, a
/// stand-in paste and a stand-in reading of the focused field. No key reaches
/// the system, the clipboard is never touched and Accessibility is never asked.
enum TextSnippetExpansionTests {
    static let syntheticMarker: Int64 = 1
    /// Everything the routine does, in order: "ask" when it reads the focused
    /// field's selection, "ask text" with the range when it reads the text
    /// before it, "⌫" for each backspace, typed text as itself, "key N" for
    /// any other key, and the stand-in paste's own steps.
    static var log: [String] = []
    static var focusedSelection: (range: NSRange, textLength: Int)?
    static var textBefore: String?
    static var ownWindowIsKey = false

    final class CGEventSource {
        var userData: Int64 = 0
        init?(stateID: CGEventSourceStateID) {}
    }

    final class CGEvent {
        let keyCode: CGKeyCode
        let keyDown: Bool
        var flags: CGEventFlags = []
        var text = ""
        init?(keyboardEventSource: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {
            keyCode = virtualKey
            self.keyDown = keyDown
        }
        func keyboardSetUnicodeString(stringLength: Int, unicodeString: [UInt16]) {
            text = String(decoding: unicodeString.prefix(stringLength), as: UTF16.self)
        }
        func post(tap: CGEventTapLocation) {
            guard keyDown else { return }
            if !text.isEmpty {
                log.append(text)
            } else {
                log.append(keyCode == CGKeyCode(kVK_Delete) ? "⌫" : "key \(keyCode)")
            }
        }
    }

    enum NSWorkspace {
        static let shared = Workspace()
        struct Workspace { let frontmostApplication: Application? = Application() }
        struct Application { let processIdentifier: pid_t = 42 }
    }

    enum SelectedTextReader {
        struct FocusedTextSelection {
            let range: NSRange
            let textLength: Int
            func text(in range: NSRange) -> String? {
                log.append("ask text \(range.location)..<\(NSMaxRange(range))")
                return textBefore
            }
        }
        static func focusedTextSelection(processID: pid_t, timeout: TimeInterval) -> FocusedTextSelection? {
            log.append("ask")
            return focusedSelection.map { FocusedTextSelection(range: $0.range, textLength: $0.textLength) }
        }
    }

    /// Posts at once what the real paste posts after the modifiers come up.
    final class TransientPaste {
        static let shared = TransientPaste()
        func paste(_ text: String,
                   formats: [NSPasteboard.PasteboardType: Data] = [:],
                   willPostShortcut: (() -> Void)? = nil,
                   didPostShortcut: (() -> Void)? = nil,
                   didFail: (() -> Void)? = nil) -> Bool {
            log.append("modifiers up")
            willPostShortcut?()
            log.append("paste \(text)")
            didPostShortcut?()
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        RichSnippetTests.run(suite)
        SnippetArgumentTests.run(suite)
        func reset() {
            log = []
            focusedSelection = nil
            textBefore = nil
            ownWindowIsKey = false
        }
        defer { reset() }
        let defaultFont = RichSnippetSupport.defaultFont
        let fontSample = NSAttributedString(string: "Example", attributes: [.font: defaultFont, .link: "https://example.com"])
        let fontFormats = RichSnippetSupport.pasteFormats(fontSample, trailingText: "")
        let fontHTML = fontFormats[.html].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        suite.expect(defaultFont.familyName == "Verdana" && defaultFont.pointSize == 10
                     && fontHTML.contains("13.3px") && fontHTML.contains("Verdana"),
                     "the default font uses Verdana at ten native points and equivalent CSS pixels")
        let fontRTF = fontFormats[.rtf].flatMap {
            try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        suite.expect((fontRTF?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 10
                     && fontRTF?.attribute(.link, at: 0, effectiveRange: nil) != nil,
                     "RTF uses equivalent native point size while retaining hyperlinks")

        var short = TextSnippet()
        short.trigger = ";reply"
        var longer = TextSnippet()
        longer.trigger = ";reply2"
        var debounce = SnippetExpansionDebounce()
        let shortTicket = debounce.update(buffer: ";reply", snippets: [short, longer])!
        let longTicket = debounce.update(buffer: ";reply2", snippets: [short, longer])!
        suite.expect(debounce.take(shortTicket) == nil,
                     "typing a longer trigger cancels the shorter trigger deadline")
        suite.expect(debounce.take(longTicket)?.id == longer.id,
                     "the longer snippet wins after typing pauses")
        suite.expect(debounce.take(longTicket) == nil,
                     "a delayed expansion runs only once")
        let cancelled = debounce.update(buffer: ";reply", snippets: [short, longer])!
        debounce.cancel()
        suite.expect(debounce.take(cancelled) == nil,
                     "focus changes, cursor moves and shortcuts cancel pending expansion")
        let continued = debounce.update(buffer: ";reply", snippets: [short, longer])!
        _ = debounce.update(buffer: ";replyx", snippets: [short, longer])
        suite.expect(debounce.take(continued) == nil,
                     "continuing with nonmatching text leaves the typed trigger unchanged")
        let edited = debounce.update(buffer: ";reply", snippets: [short, longer])!
        suite.expect(debounce.take(edited)?.id == short.id && SnippetExpansionDebounce.delay == 1,
                     "a complete shorter trigger expands after the one-second pause")

        let cursorTemplate = "Hi {{cursor}}👩🏽‍💻!"
        let cursorExpanded = TextSnippetSupport.expand(cursorTemplate, date: Date(), clipboard: nil)
        let cursorPayload = TextSnippetSupport.cursorPayload(cursorExpanded)
        suite.expect(cursorPayload.text == "Hi 👩🏽‍💻!" && cursorPayload.moveLeft == 2,
                     "cursor positions count composed characters after the placeholder")
        let literalClipboard = TextSnippetSupport.expand("{{clipboard}}", date: Date(), clipboard: "{{cursor}}")
        suite.expect(TextSnippetSupport.cursorPayload(literalClipboard).text == "{{cursor}}",
                     "clipboard values do not create cursor placeholders")
        reset()
        _ = postExpansion(deleteCount: 0, typedTrigger: "", text: cursorExpanded,
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["Hi 👩🏽‍💻!", "key 123", "key 123"],
                     "typed cursor snippets omit the marker and move to the requested position")

        let completion = (range: NSRange(location: 6, length: 2), textLength: 8)
        let deletes = { (count: Int) in Array(repeating: "⌫", count: count) }

        reset()
        focusedSelection = completion
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(7) + ["StartEnd"],
                     "an inline completion after a typed trigger takes one more backspace (issue #1377)")

        reset()
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask"] + deletes(6) + ["StartEnd"],
                     "a field without a completion gets exactly the trigger's backspaces")

        reset()
        focusedSelection = (range: NSRange(location: 6, length: 4), textLength: 31)
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask"] + deletes(6) + ["StartEnd"],
                     "a selection short of the end, like a terminal's scrollback, keeps the trigger's backspaces")

        reset()
        ownWindowIsKey = true
        focusedSelection = completion
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == deletes(6) + ["StartEnd"],
                     "a key panel of ours, like the island's scratchpad, never asks the app behind it")

        reset()
        focusedSelection = completion
        textBefore = "search"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(6) + ["StartEnd"],
                     "a selection after text other than the typed trigger, as behind a launcher, keeps the count")

        reset()
        focusedSelection = completion
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(6) + ["StartEnd"],
                     "a field that gives only its selection and length, or runs out of time, keeps the count")

        reset()
        focusedSelection = completion
        textBefore = ";test"
        _ = postExpansion(deleteCount: 5, typedTrigger: ";test", text: "test123",
                          trailingKeyCode: CGKeyCode(kVK_Space), trailingFlags: [], trailingText: " ")
        suite.expect(log == ["ask", "ask text 1..<6"] + deletes(6) + ["test123", "key \(kVK_Space)"],
                     "a delimiter-completed trigger clears the completion before typing and the delimiter")

        reset()
        focusedSelection = completion
        textBefore = ";test"
        _ = postExpansion(deleteCount: 5, typedTrigger: ";test", text: "first\nsecond",
                          trailingKeyCode: CGKeyCode(kVK_Space), trailingFlags: [], trailingText: " ")
        suite.expect(log == ["modifiers up", "ask", "ask text 1..<6"] + deletes(6) + ["paste first\nsecond "],
                     "a multi-line snippet asks the field only when its backspaces go out with the paste")

        reset()
        focusedSelection = completion
        _ = postExpansion(deleteCount: 0, typedTrigger: "", text: "StartEnd", trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["StartEnd"],
                     "an insertion with no trigger to clear never asks the field or deletes")
    }
}

/// Round trips through the same storage and clipboard serializers used by the
/// app, including a variable whose token spans differently formatted runs.
enum RichSnippetTests {
    static func run(_ suite: TestSuite) {
        let source = NSMutableAttributedString(string: "Guide {{clipboard}}\nFirst\nSecond")
        let whole = NSRange(location: 0, length: source.length)
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: whole)
        source.addAttributes([.link: URL(string: "https://example.com/guide")!,
                              .underlineStyle: NSUnderlineStyle.single.rawValue],
                             range: NSRange(location: 0, length: 5))
        source.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: 5))
        source.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        let listRange = (source.string as NSString).range(of: "First\nSecond")
        source.addAttribute(.paragraphStyle, value: style, range: listRange)
        source.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 10, length: 4))
        var snippet = TextSnippet()
        snippet.replacement = source.string
        snippet.richReplacement = RichSnippetSupport.encode(source)
        let stored = try! JSONDecoder().decode(TextSnippet.self, from: JSONEncoder().encode(snippet))
        let decoded = RichSnippetSupport.decode(stored.richReplacement, matching: stored.replacement)
        suite.expect(decoded?.string == source.string, "rich text survives snippet JSON backup and restore")
        suite.expect(decoded?.attribute(.link, at: 0, effectiveRange: nil) != nil, "hyperlink survives storage")
        suite.expect((decoded?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int) == 1, "underline survives storage")
        suite.expect((decoded?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == 1, "strikethrough survives storage")
        let font = decoded?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        suite.expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "bold survives storage")
        let paragraph = decoded?.attribute(.paragraphStyle, at: listRange.location, effectiveRange: nil) as? NSParagraphStyle
        suite.expect(paragraph?.textLists.first?.markerFormat == .disc, "bullet list metadata survives storage")
        let expanded = RichSnippetSupport.expanded(stored, date: Date(), clipboard: "{{date}} <tag> & text")!
        suite.expect(expanded.string.hasPrefix("Guide {{date}} <tag> & text\n"), "split-run variable expands once and clipboard stays literal")
        suite.expect(expanded.attribute(.link, at: 0, effectiveRange: nil) != nil, "expansion retains the surrounding hyperlink")
        suite.expect(RichSnippetSupport.plainText(expanded).hasSuffix("• First\n• Second"),
                     "plain-text fallback materializes list markers for text-only apps")
        let formats = RichSnippetSupport.pasteFormats(expanded, trailingText: " ")
        suite.expect(formats[.rtf] != nil && formats[.html] != nil, "paste offers both RTF and HTML")
        let payload = try! NSAttributedString(data: formats[.rtf]!, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        suite.expect(payload.string == expanded.string + " ",
                     "RTF keeps list content and the trailing delimiter")
        let pastedList = (payload.string as NSString).range(of: "First")
        suite.expect((payload.attribute(.paragraphStyle, at: pastedList.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first?.markerFormat == .disc,
                     "rich clipboard retains native bullet-list metadata")
        suite.expect(payload.attribute(.link, at: payload.length - 1, effectiveRange: nil) == nil, "delimiter does not inherit a hyperlink")
        suite.expect(RichSnippetSupport.decode(Data("bad RTF".utf8), matching: "plain") == nil, "corrupt formatting falls back to plain text")
        suite.expect(RichSnippetSupport.decode(stored.richReplacement, matching: "changed") == nil, "stale formatting cannot insert old content")
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Old","trigger":"old","replacement":"plain","expansion":"immediate","enabled":true}"#.utf8)
        let old = try! JSONDecoder().decode(TextSnippet.self, from: legacy)
        suite.expect(old.richReplacement == nil && old.replacement == "plain", "legacy snippets load without a migration")
    }
}

enum SnippetArgumentTests {
    static func run(_ suite: TestSuite) {
        let template = #"Hi {argument name="Customer"}, {argument name="Tone" options="Happy, Professional" default="Professional"}. {argument name="Customer"}! {argument} {argument type="password"}"#
        let fields = SnippetArgumentSupport.arguments(in: template)
        suite.expect(fields.count == 4, "named arguments share a field and unnamed arguments stay independent")
        suite.expect(fields[0].name == "Customer" && fields[0].required, "text arguments are required by default")
        suite.expect(fields[1].options == ["Happy", "Professional"] && !fields[1].required, "dropdown choices and defaults are parsed")
        suite.expect(fields.last?.password == true, "password argument uses a masked field")
        suite.expect(!SnippetArgumentSupport.isValid([:], for: fields), "missing required values cannot insert")
        let values = [fields[0].id: "A & B <tag> {{date}} {argument}", fields[2].id: "One", fields[3].id: "Secret"]
        suite.expect(SnippetArgumentSupport.isValid(values, for: fields), "optional dropdown uses its default")
        var invalid = values
        invalid[fields[1].id] = "Other"
        suite.expect(!SnippetArgumentSupport.isValid(invalid, for: fields), "dropdown rejects values outside its choices")
        var snippet = TextSnippet()
        snippet.replacement = template
        let rich = NSMutableAttributedString(string: template)
        rich.addAttributes([.underlineStyle: 1, .font: NSFont.boldSystemFont(ofSize: 13)], range: NSRange(location: 0, length: rich.length))
        snippet.richReplacement = RichSnippetSupport.encode(rich)
        let result = SnippetArgumentSupport.render(snippet, values: values, date: Date(), clipboard: nil)
        suite.expect(result.string == "Hi A & B <tag> {{date}} {argument}, Professional. A & B <tag> {{date}} {argument}! One Secret",
                     "arguments substitute once, reuse names, apply defaults, and preserve literal user input")
        suite.expect(result.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int == 1,
                     "argument replacement inherits the placeholder formatting")
        suite.expect(SnippetArgumentSupport.arguments(in: "{{argument}} {argument name=bad}").isEmpty,
                     "unrecognized placeholder syntax stays literal")
        var nestedDefault = TextSnippet()
        nestedDefault.replacement = #"{argument default="{{date}}"}"#
        suite.expect(SnippetArgumentSupport.render(nestedDefault, values: [:], date: Date(), clipboard: nil).string == "{{date}}",
                     "variables inside argument defaults stay literal and do not create overlapping edits")
        var adminLink = TextSnippet()
        adminLink.replacement = #"https://portal{argument name="DC" options=".com,.eu"}.example.com/admin/"#
        let dc = SnippetArgumentSupport.arguments(in: adminLink.replacement)
        suite.expect(dc.count == 1 && dc[0].options == [".com", ".eu"], "DC example creates one dropdown with literal domain suffixes")
        for suffix in [".com", ".eu"] {
            let expandedURL = SnippetArgumentSupport.render(adminLink, values: [dc[0].id: suffix], date: Date(), clipboard: nil)
            suite.expect(expandedURL.string == "https://portal\(suffix).example.com/admin/",
                         "DC selection substitutes the suffix directly without URL encoding or generation")
        }
        let configured = SnippetArgumentSupport.token(name: "  Region ", kind: .dropdown,
                                                       choices: ["one", "two"], defaultValue: "two")!
        let configuredFields = SnippetArgumentSupport.arguments(in: configured)
        suite.expect(configuredFields.count == 1 && configuredFields[0].name == "Region"
                     && configuredFields[0].options == ["one", "two"] && configuredFields[0].defaultValue == "two",
                     "native builder serializes a named dropdown that the production parser understands")
        let escaped = SnippetArgumentSupport.token(name: #"Path \"A\""#, kind: .password,
                                                   choices: [], defaultValue: #"C:\folder\file"#)!
        let escapedField = SnippetArgumentSupport.arguments(in: escaped).first
        suite.expect(escapedField?.name == #"Path \"A\""# && escapedField?.defaultValue == #"C:\folder\file"#
                     && escapedField?.password == true, "builder escapes quotes and backslashes without losing values")
        suite.expect(SnippetArgumentSupport.token(name: "", kind: .text, choices: [], defaultValue: nil) == nil,
                     "builder requires a usable field name")
        for invalidChoices in [[], [""], ["one", "one"], ["one,two"], ["one\ntwo"]] {
            suite.expect(SnippetArgumentSupport.token(name: "Field", kind: .dropdown, choices: invalidChoices, defaultValue: nil) == nil,
                         "builder rejects choices that cannot round trip through placeholder syntax")
        }
        suite.expect(SnippetArgumentSupport.token(name: "Field", kind: .dropdown, choices: ["one"], defaultValue: "two") == nil,
                     "builder requires a dropdown default to be a valid choice")
        let around = "Before " + configured + " after"
        let tokenRange = (around as NSString).range(of: configured)
        suite.expect(SnippetArgumentSupport.occurrence(in: around, selection: NSRange(location: tokenRange.location + 5, length: 0))?.argument.name == "Region",
                     "placing the cursor inside a token finds it for native editing")
        suite.expect(SnippetArgumentSupport.occurrence(in: around, selection: NSRange(location: 0, length: 3)) == nil,
                     "ordinary selected text opens a new argument rather than editing a different token")
        let blank = SnippetArgumentSupport.arguments(in: #"{argument default=""}"#)
        suite.expect(SnippetArgumentSupport.isValid([:], for: blank), "an explicitly empty default makes a field optional")
    }
}
