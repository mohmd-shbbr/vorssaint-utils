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
        let blank = SnippetArgumentSupport.arguments(in: #"{argument default=""}"#)
        suite.expect(SnippetArgumentSupport.isValid([:], for: blank), "an explicitly empty default makes a field optional")
    }
}
