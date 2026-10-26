// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import AppKit

/// One text snippet: typing the trigger inserts the replacement. Stored as
/// JSON in defaults; ids and raw values are persisted, so keep them stable.
struct TextSnippet: Codable, Identifiable, Equatable {
    /// When the replacement fires relative to the trigger.
    enum Expansion: String, Codable, CaseIterable {
        /// The moment the last trigger character is typed.
        case immediate
        /// Only when space, Tab or Return follows the trigger (the delimiter
        /// itself is kept, typed after the replacement).
        case afterDelimiter
    }

    var id = UUID()
    var name = ""
    var trigger = ""
    var replacement = ""
    /// An optional attributed-string archive; older plain snippets remain readable.
    var richReplacement: Data? = nil
    var expansion = Expansion.immediate
    var enabled = true
    var ignoresCase = false
    /// Plain folder name for the library; empty means no folder. Folders are
    /// derived from the snippets themselves, so there is no folder entity to
    /// migrate or orphan.
    var folder = ""
    var showsInLibrary = true

    enum CodingKeys: String, CodingKey {
        case id, name, trigger, replacement, richReplacement, expansion, enabled, ignoresCase, folder, showsInLibrary
    }
}

extension TextSnippet {
    /// Snippets stored before an option existed have no key for it; each one
    /// falls back to the behavior of its day (exact matching, no folder,
    /// visible in the library).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trigger = try container.decode(String.self, forKey: .trigger)
        replacement = try container.decode(String.self, forKey: .replacement)
        richReplacement = try container.decodeIfPresent(Data.self, forKey: .richReplacement)
        expansion = try container.decode(Expansion.self, forKey: .expansion)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        ignoresCase = try container.decodeIfPresent(Bool.self, forKey: .ignoresCase) ?? false
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        showsInLibrary = try container.decodeIfPresent(Bool.self, forKey: .showsInLibrary) ?? true
    }
}

/// The pure half of the snippets engine: buffer bookkeeping, trigger
/// matching and variable expansion, all deterministic and injectable so the
/// harness can pin the behavior down.
enum TextSnippetSupport {
    /// Keystrokes the buffer remembers; longer triggers cannot match.
    // Only a template token creates this internal marker; clipboard/argument
    // values are inserted afterward and are never interpreted as templates.
    static let cursorMarker = "\u{E000}VorssaintCursor\u{E001}"

    static func cursorPayload(_ text: String) -> (text: String, moveLeft: Int) {
        guard let range = text.range(of: cursorMarker) else { return (text, 0) }
        return (text.replacingOccurrences(of: cursorMarker, with: ""),
                text[range.upperBound...].replacingOccurrences(of: cursorMarker, with: "").count)
    }

    static let bufferLimit = 64
    static let maxTriggerLength = 40

    /// Characters that fire an afterDelimiter snippet.
    static let delimiters: Set<Character> = [" ", "\t", "\r", "\n"]

    static let systemSoundsPath = "/System/Library/Sounds"

    /// The file behind a name from `alertSoundNames`: the same directory the
    /// picker was listed from, so what it offers is what plays.
    static func soundFileURL(for name: String) -> URL {
        URL(fileURLWithPath: systemSoundsPath)
            .appendingPathComponent(name)
            .appendingPathExtension("aiff")
    }

    /// The classic macOS alert sounds, used when the sounds directory
    /// cannot be read.
    static let fallbackAlertSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    /// The sound names among `entries` (a directory listing), sorted for a
    /// stable picker order. Falls back rather than returning nothing: an
    /// empty picker would leave the preference unsettable.
    static func alertSoundNames(from entries: [String]) -> [String] {
        let names = entries
            .filter { $0.lowercased().hasSuffix(".aiff") }
            .map { String($0.dropLast(".aiff".count)) }
            .sorted()
        return names.isEmpty ? fallbackAlertSoundNames : names
    }

    /// The alert sounds the picker offers. Read from the directory rather
    /// than hardcoded so a sound macOS adds shows up on its own.
    static let alertSoundNames: [String] = alertSoundNames(
        from: (try? FileManager.default.contentsOfDirectory(atPath: systemSoundsPath)) ?? [])

    /// The sound to actually use for a stored preference. A name saved on
    /// another Mac, or one this macOS no longer ships, would otherwise
    /// leave the picker blank and the expansion silent while the toggle
    /// still reads on.
    static func resolvedSoundName(stored: String?,
                                  available: [String] = alertSoundNames,
                                  fallback: String = Defaults.defaultSnippetSoundName) -> String? {
        if let stored, available.contains(stored) { return stored }
        if available.contains(fallback) { return fallback }
        return available.first
    }

    /// Triggers cannot contain whitespace (the buffer resets on it) and stay
    /// within a sane length.
    static func sanitizedTrigger(_ raw: String) -> String {
        String(raw.filter { !$0.isWhitespace }.prefix(maxTriggerLength))
    }

    /// The typing buffer after one insertion. Anything beyond the limit
    /// slides off the front; the buffer only ever needs to hold the longest
    /// possible trigger.
    static func bufferAppending(_ buffer: String, typed: String) -> String {
        let next = buffer + typed
        return String(next.suffix(bufferLimit))
    }

    /// The snippet whose trigger the buffer just completed for the given
    /// expansion mode. The longest trigger wins, so ";email2" beats ";email"
    /// the way the user expects.
    static func match(buffer: String,
                      expansion: TextSnippet.Expansion,
                      snippets: [TextSnippet]) -> TextSnippet? {
        var best: TextSnippet?
        for snippet in snippets where snippet.enabled
            && snippet.expansion == expansion
            && !snippet.trigger.isEmpty
            && completes(buffer, trigger: snippet.trigger, ignoresCase: snippet.ignoresCase) {
            if let current = best, current.trigger.count >= snippet.trigger.count { continue }
            best = snippet
        }
        return best
    }

    /// Whether the buffer just finished typing the trigger. The insensitive
    /// path compares exactly `trigger.count` characters, so the deletes the
    /// expansion posts always erase precisely what the user typed.
    static func completes(_ buffer: String, trigger: String, ignoresCase: Bool) -> Bool {
        guard ignoresCase else { return buffer.hasSuffix(trigger) }
        guard buffer.count >= trigger.count else { return false }
        return String(buffer.suffix(trigger.count))
            .compare(trigger, options: .caseInsensitive) == .orderedSame
    }

    /// The part of `trigger` the expansion's backspaces clear, as it was
    /// typed: the end of `buffer` that completed it, less `swallowed`, the key
    /// that completed an immediate trigger and never reached the field. The
    /// stored trigger can differ in case, or in Unicode normalization when it
    /// was pasted in, and so in UTF-16 length.
    static func typedTrigger(_ trigger: String, buffer: String, swallowed: String = "") -> String {
        String(buffer.suffix(trigger.count).dropLast(swallowed.count))
    }

    /// The snippet `buffer` just completed, with the backspaces that clear
    /// its trigger and the text they clear, both decided by `swallowed` in
    /// one place: the key that completed an immediate trigger, or "" after a
    /// delimiter, which never enters the buffer.
    static func expansionMatch(buffer: String,
                               expansion: TextSnippet.Expansion,
                               snippets: [TextSnippet],
                               swallowed: String)
        -> (snippet: TextSnippet, deleteCount: Int, typedTrigger: String)? {
        guard let snippet = match(buffer: buffer, expansion: expansion, snippets: snippets) else { return nil }
        return (snippet,
                max(0, snippet.trigger.count - swallowed.count),
                typedTrigger(snippet.trigger, buffer: buffer, swallowed: swallowed))
    }

    /// Replaces the dynamic variables. Unknown {{tags}} pass through
    /// untouched, so a typo stays visible instead of vanishing silently.
    /// The one variable whose value comes from somewhere that can hang: the
    /// general pasteboard may hold content an app renders only on demand, and
    /// an app that stops answering never answers. Both expansion paths ask
    /// this first, so a replacement without the variable pays nothing.
    static func needsClipboard(_ replacement: String) -> Bool {
        replacement.contains("{{clipboard}}")
    }

    static func requiresPaste(_ text: String) -> Bool {
        text.contains(where: \.isNewline)
    }

    static func pastePayload(text: String, trailingText: String) -> String {
        text + trailingText.replacingOccurrences(of: "\r", with: "\n")
    }

    /// The backspaces that clear the `deleteCount` characters of a trigger,
    /// `typed`, from the focused text. A field that completes as you type
    /// shows the rest selected after the caret: a browser's address bar turns
    /// "gitgra" into "gitgra[ph]". The first backspace then removes only that
    /// selection, so it takes one more, or the trigger keeps its first
    /// character (issue #1377). Only a selection that starts after the
    /// trigger and runs to the end of the text counts, measured in the UTF-16
    /// units Accessibility counts in. A selection elsewhere is not where the
    /// backspaces land: a terminal can keep one in its scrollback while you
    /// type at the prompt.
    ///
    /// Such a selection is then checked against `textBefore`, the field's
    /// text in the range right before it, which has to be the typed trigger:
    /// keys can go to a launcher's panel that never activates its app, while
    /// the field asked belongs to the app behind it. Compared without case,
    /// since a field can capitalize what was typed. A field that does not say,
    /// or does not answer in time, keeps the plain count: the extra backspace
    /// would otherwise go out unchecked exactly when an app is slow. Without
    /// `typed` there is nothing to check, so no selection counts.
    static func triggerDeleteCount(_ deleteCount: Int,
                                   typed: String,
                                   focusedSelection: (range: NSRange, textLength: Int)?,
                                   textBefore: (NSRange) -> String?) -> Int {
        guard deleteCount > 0, !typed.isEmpty, let focusedSelection else { return deleteCount }
        let range = focusedSelection.range
        let typedLength = typed.utf16.count
        guard range.length > 0,
              range.location >= typedLength,
              NSMaxRange(range) == focusedSelection.textLength
        else { return deleteCount }
        guard let before = textBefore(NSRange(location: range.location - typedLength, length: typedLength))
        else { return deleteCount }
        return before.compare(typed, options: .caseInsensitive) == .orderedSame ? deleteCount + 1 : deleteCount
    }

    static func expand(_ replacement: String,
                       date: Date,
                       clipboard: String?,
                       locale: Locale = .current) -> String {
        guard replacement.contains("{{") else { return replacement }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let dateText = dateFormatter.string(from: date)
        let timeText = timeFormatter.string(from: date)
        let expanded = replacement
            .replacingOccurrences(of: "{{cursor}}", with: cursorMarker)
            .replacingOccurrences(of: "{{date}}", with: dateText)
            .replacingOccurrences(of: "{{time}}", with: timeText)
            .replacingOccurrences(of: "{{datetime}}", with: "\(dateText) \(timeText)")
        // The clipboard goes in last so pasted text is never re-expanded.
        return expandingFormattedDates(expanded, date: date, locale: locale)
            .replacingOccurrences(of: "{{clipboard}}", with: clipboard ?? "")
    }

    /// The date variables also take an explicit pattern after a colon, in the
    /// system's own date-format language: {{date:yyyy-MM-dd}}, and the same
    /// for time and datetime so every spelling works. The pattern keeps the
    /// user's locale, so month and weekday names come out in their language.
    /// A variant with an explicit IANA identifier after the kind,
    /// {{date-tz(America/New_York):yyyy-MM-dd}}, overrides the device's
    /// current time zone for that one token.
    private static let formattedDateKinds = ["date", "time", "datetime"]

    /// Configures a DateFormatter's pattern and timezone override. Called by
    /// both expandingFormattedDates and configuredFormatter to ensure a single
    /// place decides how these two properties map from pattern and identifier.
    private static func configure(_ formatter: DateFormatter,
                                  pattern: String,
                                  timeZoneIdentifier: String?) {
        formatter.dateFormat = pattern
        formatter.timeZone = timeZoneIdentifier.flatMap { TimeZone(identifier: $0) }
    }

    /// A fresh formatter for one-off use (a preview), as opposed to
    /// expandingFormattedDates's single instance reused across a whole
    /// replacement string's tokens.
    private static func configuredFormatter(pattern: String,
                                            timeZoneIdentifier: String?,
                                            locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        configure(formatter, pattern: pattern, timeZoneIdentifier: timeZoneIdentifier)
        return formatter
    }

    private static func expandingFormattedDates(_ text: String,
                                                date: Date,
                                                locale: Locale) -> String {
        guard formattedDateKinds.contains(where: { text.contains("{{\($0)") }) else { return text }
        let formatter = DateFormatter()
        formatter.locale = locale
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            result += rest[..<start.lowerBound]
            let tail = rest[start.lowerBound...]
            guard let close = tail.range(of: "}}"),
                  let match = formattedPattern(in: tail[..<close.lowerBound]) else {
                result += "{{"
                rest = rest[start.upperBound...]
                continue
            }
            configure(formatter, pattern: match.pattern, timeZoneIdentifier: match.timeZoneIdentifier)
            result += formatter.string(from: date)
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    /// The kind, pattern and optional time zone inside one "{{name:pattern"
    /// or "{{name-tz(identifier):pattern" chunk, nil when the tag is not a
    /// date variable, malformed, or the pattern is empty (all stay visible,
    /// like any unknown tag).
    private static func formattedPattern(in tag: Substring) -> (kind: String, pattern: String, timeZoneIdentifier: String?)? {
        for kind in formattedDateKinds {
            let tzPrefix = "{{\(kind)-tz("
            if tag.hasPrefix(tzPrefix) {
                let afterPrefix = tag.dropFirst(tzPrefix.count)
                guard let closeParen = afterPrefix.firstIndex(of: ")") else { return nil }
                let identifier = String(afterPrefix[..<closeParen])
                let afterIdentifier = afterPrefix[afterPrefix.index(after: closeParen)...]
                guard afterIdentifier.hasPrefix(":") else { return nil }
                let pattern = String(afterIdentifier.dropFirst())
                // An identifier this Mac cannot resolve leaves the tag
                // literal rather than quietly formatting in the device's
                // own zone: a plausible-looking wrong time is worse than a
                // tag the user can see is wrong, and the captions now
                // invite typing these by hand.
                guard !pattern.isEmpty, TimeZone(identifier: identifier) != nil else { return nil }
                return (kind, pattern, identifier)
            }
            let plainPrefix = "{{\(kind):"
            if tag.hasPrefix(plainPrefix) {
                let pattern = String(tag.dropFirst(plainPrefix.count))
                return pattern.isEmpty ? nil : (kind, pattern, nil)
            }
        }
        return nil
    }

    // MARK: - Date variable builder

    /// The three shapes a date/time snippet variable can take.
    enum DateVariableKind: String, CaseIterable {
        case date, time, datetime
    }

    /// How a date/time variable's pattern gets chosen: one of the system's
    /// built-in styles, the fixed ISO 8601 shape, or a hand-typed pattern.
    enum DateVariableStyle: String, CaseIterable {
        case short, medium, long, full, iso8601, custom

        /// The styles that resolve through the current locale, so the
        /// pattern saved in the token is the one that locale used at the
        /// time. iso8601 and custom are fixed patterns and carry no such
        /// dependency.
        static let localeDependent: Set<DateVariableStyle> = [.short, .medium, .long, .full]
    }

    private static let isoPatterns: [DateVariableKind: String] = [
        .date: "yyyy-MM-dd",
        .time: "HH:mm:ssXXX",
        .datetime: "yyyy-MM-dd'T'HH:mm:ssXXX"
    ]

    private static func systemStyle(_ style: DateVariableStyle) -> DateFormatter.Style {
        switch style {
        case .short: return .short
        case .medium: return .medium
        case .long: return .long
        case .full: return .full
        case .iso8601, .custom: return .none
        }
    }

    /// The ICU pattern a builder selection resolves to: the raw text for
    /// Custom, a fixed shape for ISO 8601, or whatever DateFormatter reports
    /// for a system style at this locale.
    static func resolvedDatePattern(kind: DateVariableKind,
                                    style: DateVariableStyle,
                                    customPattern: String,
                                    locale: Locale) -> String {
        switch style {
        case .custom:
            return customPattern
        case .iso8601:
            return isoPatterns[kind] ?? ""
        case .short, .medium, .long, .full:
            let formatter = DateFormatter()
            formatter.locale = locale
            let dateStyle = systemStyle(style)
            switch kind {
            case .date:
                formatter.dateStyle = dateStyle
                formatter.timeStyle = .none
            case .time:
                formatter.dateStyle = .none
                formatter.timeStyle = dateStyle
            case .datetime:
                formatter.dateStyle = dateStyle
                formatter.timeStyle = dateStyle
            }
            return formatter.dateFormat
        }
    }

    /// The literal "{{kind:pattern}}" (or "{{kind-tz(id):pattern}}") text a
    /// builder selection inserts into a snippet's replacement.
    static func dateVariableText(kind: DateVariableKind,
                                 style: DateVariableStyle,
                                 customPattern: String,
                                 timeZoneIdentifier: String?,
                                 locale: Locale) -> String {
        let pattern = resolvedDatePattern(kind: kind, style: style,
                                          customPattern: customPattern, locale: locale)
        let tzPart = timeZoneIdentifier.map { "-tz(\($0))" } ?? ""
        return "{{\(kind.rawValue)\(tzPart):\(pattern)}}"
    }

    /// What a builder selection would format the given date as, using the
    /// same formatter configuration expandingFormattedDates uses, so the
    /// preview always matches what expansion actually produces.
    static func dateVariablePreview(kind: DateVariableKind,
                                    style: DateVariableStyle,
                                    customPattern: String,
                                    timeZoneIdentifier: String?,
                                    date: Date,
                                    locale: Locale) -> String {
        let pattern = resolvedDatePattern(kind: kind, style: style,
                                          customPattern: customPattern, locale: locale)
        guard !pattern.isEmpty else { return "" }
        let formatter = configuredFormatter(pattern: pattern,
                                            timeZoneIdentifier: timeZoneIdentifier,
                                            locale: locale)
        return formatter.string(from: date)
    }

    /// Reconstructs which Style an already-built pattern came from, by
    /// comparing it against what each style would resolve to right now.
    /// Falls back to Custom when nothing matches (e.g. a hand-typed
    /// pattern, or a system style whose OS-resolved text has since
    /// changed).
    static func matchingDateStyle(pattern: String,
                                  kind: DateVariableKind,
                                  locale: Locale) -> DateVariableStyle {
        let candidates: [DateVariableStyle] = [.iso8601, .short, .medium, .long, .full]
        for candidate in candidates {
            if resolvedDatePattern(kind: kind, style: candidate,
                                   customPattern: "", locale: locale) == pattern {
                return candidate
            }
        }
        return .custom
    }

    /// Lowercased with underscores folded to spaces, so "New_York" and
    /// "new york" compare equal: identifiers spell city names with
    /// underscores, but nobody types a timezone query that way.
    private static func normalizedTimeZoneText(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    /// How well an identifier answers a query, lowest first, so that a
    /// zone whose city the user actually typed leads the list instead of
    /// whichever zone merely contains those letters earliest in the
    /// alphabet.
    private static func timeZoneMatchRank(_ identifier: String, query: String) -> Int {
        let normalized = normalizedTimeZoneText(identifier)
        if normalized == query { return 0 }
        // The city is what people type; it is the part after the region.
        let city = normalized.split(separator: "/").last.map(String.init) ?? normalized
        if city == query { return 1 }
        if city.hasPrefix(query) { return 2 }
        if normalized.hasPrefix(query) { return 3 }
        return 4
    }

    /// Every timezone identifier whose name or common abbreviation
    /// contains the query, case- and separator-insensitive, best matches
    /// first. Uncapped: the picker scrolls, and any cap drops the very
    /// identifier a broad query is looking for.
    static func matchingTimeZoneIdentifiers(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let normalizedQuery = normalizedTimeZoneText(query)
        var seen = Set<String>()
        var matches: [String] = []
        for identifier in TimeZone.knownTimeZoneIdentifiers
        where normalizedTimeZoneText(identifier).contains(normalizedQuery) {
            if seen.insert(identifier).inserted { matches.append(identifier) }
        }
        for (abbreviation, identifier) in TimeZone.abbreviationDictionary
        where normalizedTimeZoneText(abbreviation).contains(normalizedQuery) {
            if seen.insert(identifier).inserted { matches.append(identifier) }
        }
        return matches.sorted {
            let left = timeZoneMatchRank($0, query: normalizedQuery)
            let right = timeZoneMatchRank($1, query: normalizedQuery)
            return left == right ? $0 < $1 : left < right
        }
    }

    /// The single timezone identifier the query unambiguously names, if
    /// any: an exact match on a full identifier or a common abbreviation
    /// (e.g. "PST"), or the one candidate left when the substring search
    /// in matchingTimeZoneIdentifiers(for:) narrows to exactly one result
    /// (e.g. "new york" narrows to only "America/New_York", so it counts
    /// as confirmed even though it isn't a literal identifier spelling).
    /// Never a raw UTC offset: several cities can share one offset, and
    /// daylight saving makes the mapping depend on the date, so an offset
    /// alone doesn't name one timezone.
    /// Pass `matches` when the caller already has the list for this same
    /// query (the picker renders it), so the search is not repeated.
    static func resolvedTimeZoneIdentifier(for query: String,
                                           matches: [String]? = nil) -> String? {
        guard !query.isEmpty else { return nil }
        let normalizedQuery = normalizedTimeZoneText(query)
        if let identifier = TimeZone.knownTimeZoneIdentifiers.first(where: {
            normalizedTimeZoneText($0) == normalizedQuery
        }) {
            return identifier
        }
        if let abbreviation = TimeZone.abbreviationDictionary.first(where: {
            normalizedTimeZoneText($0.key) == normalizedQuery
        }) {
            return abbreviation.value
        }
        let candidates = matches ?? matchingTimeZoneIdentifiers(for: query)
        return candidates.count == 1 ? candidates.first : nil
    }

    struct DetectedDateToken: Equatable {
        /// Character offsets, not String.Index: the editor holds this
        /// across the popover's lifetime and uses it to splice the text
        /// afterwards, and an index is only valid against the exact string
        /// it was computed from.
        let offsets: Range<Int>
        let kind: DateVariableKind
        let pattern: String
        let timeZoneIdentifier: String?
    }

    /// Turns the editor's tracked selection offsets into a range of `text`,
    /// clamping them to it. The offsets are recorded against whatever the
    /// text was when the selection last moved, so an edit that shortened
    /// the text since then leaves them pointing past the end; nil means
    /// nothing is tracked yet and the caret belongs at the end.
    static func selectionRange(in text: String, offsets: Range<Int>?) -> Range<String.Index> {
        let count = text.count
        let lower = min(max(offsets?.lowerBound ?? count, 0), count)
        let upper = min(max(offsets?.upperBound ?? count, lower), count)
        return text.index(text.startIndex, offsetBy: lower)
            ..< text.index(text.startIndex, offsetBy: upper)
    }

    /// The recognized date/time tag containing `index`, if any: used by the
    /// snippet editor to tell whether the cursor sits inside an existing
    /// token (so the builder edits it) or not (so it inserts a new one).
    /// Mirrors expandingFormattedDates's own traversal (skip past a bare
    /// "{{" on any mismatch, rather than jumping to an unrelated "}}"), so
    /// an earlier malformed or unrecognized tag never swallows a later
    /// well-formed one.
    static func dateToken(in text: String, at index: String.Index) -> DetectedDateToken? {
        var rest = Substring(text)
        while let start = rest.range(of: "{{") {
            let tail = rest[start.lowerBound...]
            guard let close = tail.range(of: "}}"),
                  let match = formattedPattern(in: tail[..<close.lowerBound]),
                  let kind = DateVariableKind(rawValue: match.kind) else {
                rest = rest[start.upperBound...]
                continue
            }
            let tagEnd = close.upperBound
            if index > start.lowerBound, index < tagEnd {
                return DetectedDateToken(
                    offsets: text.distance(from: text.startIndex, to: start.lowerBound)
                        ..< text.distance(from: text.startIndex, to: tagEnd),
                    kind: kind,
                    pattern: match.pattern,
                    timeZoneIdentifier: match.timeZoneIdentifier)
            }
            rest = rest[tagEnd...]
        }
        return nil
    }

    // MARK: - Library

    /// One folder worth of library rows. An empty name is the loose group,
    /// rendered without a header.
    struct LibrarySection: Equatable {
        let folder: String
        let snippets: [TextSnippet]
    }

    /// The library's content for a search text: enabled snippets marked to
    /// show, matched against name, trigger, text and folder (case and
    /// diacritic insensitive), grouped by folder. Folders come first in
    /// alphabetical order; snippets without one close the list, both keeping
    /// the stored order inside. An empty search shows everything.
    static func librarySections(_ snippets: [TextSnippet], query: String) -> [LibrarySection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = snippets.filter { snippet in
            guard snippet.enabled, snippet.showsInLibrary else { return false }
            guard !trimmed.isEmpty else { return true }
            return snippet.name.localizedStandardContains(trimmed)
                || snippet.trigger.localizedStandardContains(trimmed)
                || snippet.replacement.localizedStandardContains(trimmed)
                || snippet.folder.localizedStandardContains(trimmed)
        }
        var byFolder: [String: [TextSnippet]] = [:]
        for snippet in visible {
            byFolder[snippet.folder, default: []].append(snippet)
        }
        var sections = byFolder
            .filter { !$0.key.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { LibrarySection(folder: $0.key, snippets: $0.value) }
        if let loose = byFolder[""], !loose.isEmpty {
            sections.append(LibrarySection(folder: "", snippets: loose))
        }
        return sections
    }

    /// The same content as one flat list, in reading order, for the keyboard
    /// selection to walk.
    static func libraryRows(_ sections: [LibrarySection]) -> [TextSnippet] {
        sections.flatMap(\.snippets)
    }

    /// Existing folder names for the editor's suggestions, distinct and
    /// alphabetical.
    static func folderSuggestions(_ snippets: [TextSnippet]) -> [String] {
        Set(snippets.map(\.folder).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Folder names travel inside each snippet; a rename is a plain rewrite
    /// of every member. Whitespace-only names mean no folder.
    static func sanitizedFolder(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Persistence

    static func decode(_ data: Data?) -> [TextSnippet] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([TextSnippet].self, from: data)) ?? []
    }

    static func encode(_ snippets: [TextSnippet]) -> Data? {
        try? JSONEncoder().encode(snippets)
    }
}

/// Shared by typed expansion, library insertion and the editor. Never interprets
/// clipboard text as markup or fetches links/resources.
enum RichSnippetSupport {
    /// Ten CSS pixels at 96 dpi corresponds to 7.5 native typographic points.
    static var defaultFont: NSFont { NSFont(name: "Verdana", size: 7.5) ?? .systemFont(ofSize: 7.5) }

    static func decode(_ data: Data?, matching text: String) -> NSAttributedString? {
        guard let data,
              let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data),
              value.string == text else { return nil }
        return value
    }

    static func encode(_ value: NSAttributedString) -> Data? {
        // RTF import normalizes list markers on recent macOS releases, changing
        // text ranges. Archive native attributes for exact editor round trips;
        // generate interoperable RTF/HTML only at the clipboard boundary.
        try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    }

    static func expanded(_ snippet: TextSnippet, date: Date, clipboard: String?,
                         locale: Locale = .current) -> NSAttributedString? {
        guard let original = decode(snippet.richReplacement, matching: snippet.replacement) else { return nil }
        let result = NSMutableAttributedString(attributedString: original)
        // Work backwards so replacements cannot invalidate the remaining UTF-16
        // ranges. Expand whole tokens even when formatting splits their runs.
        let regex = try! NSRegularExpression(pattern: #"\{\{[^{}]*\}\}"#)
        for match in regex.matches(in: original.string, range: NSRange(location: 0, length: original.length)).reversed() {
            let token = (original.string as NSString).substring(with: match.range)
            let value = TextSnippetSupport.expand(token, date: date, clipboard: clipboard, locale: locale)
            if value != token {
                let attributes = original.attributes(at: match.range.location, effectiveRange: nil)
                result.replaceCharacters(in: match.range, with: NSAttributedString(string: value, attributes: attributes))
            }
        }
        return result
    }

    /// Text-only destinations cannot draw NSTextList metadata. Materialize
    /// markers in that flavor while RTF and HTML keep native semantic lists.
    static func plainText(_ value: NSAttributedString) -> String {
        let text = value.string as NSString
        var output = ""
        var location = 0
        var counters: [ObjectIdentifier: Int] = [:]
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            let style = value.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            if let lists = style?.textLists, let list = lists.last {
                let key = ObjectIdentifier(list)
                let number = counters[key] ?? list.startingItemNumber
                counters[key] = number + 1
                output += String(repeating: "  ", count: max(0, lists.count - 1))
                    + list.marker(forItemNumber: number) + " "
            } else { counters.removeAll() }
            output += text.substring(with: range)
            location = NSMaxRange(range)
        }
        return output
    }

    static func pasteFormats(_ value: NSAttributedString, trailingText: String) -> [NSPasteboard.PasteboardType: Data] {
        let payload = NSMutableAttributedString(attributedString: value)
        // Delimiters must not extend a link or inherit the last word's style.
        payload.append(NSAttributedString(string: trailingText))
        let range = NSRange(location: 0, length: payload.length)
        var formats: [NSPasteboard.PasteboardType: Data] = [:]
        if let rtf = try? payload.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ]) { formats[.rtf] = rtf }
        // AppKit emits native point sizes as CSS px without converting units.
        // Scale only the HTML copy so web and RTF destinations use the same size.
        let htmlPayload = NSMutableAttributedString(attributedString: payload)
        payload.enumerateAttribute(.font, in: range) { value, run, _ in
            if let font = value as? NSFont {
                htmlPayload.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: font.pointSize * 4 / 3), range: run)
            }
        }
        if let html = try? htmlPayload.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html
        ]) { formats[.html] = html }
        return formats
    }
}

/// Raycast-style argument placeholders, independent of the input UI. Values
/// are substituted as literal text and are never reinterpreted as variables.
enum SnippetArgumentSupport {
    struct Argument: Identifiable, Equatable {
        let id: String
        let name: String
        let defaultValue: String?
        let options: [String]
        let password: Bool
        var required: Bool { defaultValue == nil }
    }
    struct Occurrence {
        let range: NSRange
        let argument: Argument
    }
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"(?<!\{)\{argument(?:\s+(?:name|default|options|type)="(?:\\.|[^"\\])*")*\s*\}(?!\})"#)
    private static let propertyRegex = try! NSRegularExpression(
        pattern: #"(name|default|options|type)="((?:\\.|[^"\\])*)""#)

    static func occurrences(in text: String) -> [Occurrence] {
        let ns = text as NSString
        return tokenRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated().map { index, match in
            let token = ns.substring(with: match.range)
            let tokenNS = token as NSString
            var fields: [String: String] = [:]
            for property in propertyRegex.matches(in: token, range: NSRange(location: 0, length: tokenNS.length)) {
                let raw = tokenNS.substring(with: property.range(at: 2))
                fields[tokenNS.substring(with: property.range(at: 1))] = raw
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    .replacingOccurrences(of: #"\\"#, with: #"\"#)
            }
            let name = fields["name"] ?? ""
            let options = fields["options"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
            return Occurrence(range: match.range, argument: Argument(
                id: name.isEmpty ? "position:\(index)" : "name:\(name)",
                name: name.isEmpty ? "Argument \(index + 1)" : name,
                defaultValue: fields["default"], options: options, password: fields["type"] == "password"))
        }
    }

    static func arguments(in text: String) -> [Argument] {
        var seen = Set<String>()
        return occurrences(in: text).compactMap { seen.insert($0.argument.id).inserted ? $0.argument : nil }
    }

    static func isValid(_ values: [String: String], for arguments: [Argument]) -> Bool {
        arguments.allSatisfy { argument in
            let value = values[argument.id] ?? argument.defaultValue ?? ""
            return (!argument.required || !value.isEmpty)
                && (argument.options.isEmpty || argument.options.contains(value) || (value.isEmpty && !argument.required))
        }
    }

    static func render(_ snippet: TextSnippet, values: [String: String], date: Date, clipboard: String?) -> NSAttributedString {
        let original = RichSnippetSupport.decode(snippet.richReplacement, matching: snippet.replacement)
            ?? NSAttributedString(string: snippet.replacement)
        let result = NSMutableAttributedString(attributedString: original)
        let arguments = occurrences(in: snippet.replacement)
        let variableRegex = try! NSRegularExpression(pattern: #"\{\{[^{}]*\}\}"#)
        var replacements: [(NSRange, String)] = variableRegex.matches(in: original.string,
            range: NSRange(location: 0, length: original.length))
            .filter { match in !arguments.contains { NSIntersectionRange($0.range, match.range).length > 0 } }
            .map { match in
                let token = (original.string as NSString).substring(with: match.range)
                return (match.range, TextSnippetSupport.expand(token, date: date, clipboard: clipboard))
            }
        for occurrence in arguments {
            let argument = occurrence.argument
            replacements.append((occurrence.range, values[argument.id] ?? argument.defaultValue ?? ""))
        }
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            let attributes = original.attributes(at: range.location, effectiveRange: nil)
            result.replaceCharacters(in: range, with: NSAttributedString(string: value, attributes: attributes))
        }
        return result
    }
}

extension SnippetArgumentSupport {
    enum InputKind: String, CaseIterable { case text, dropdown, password }

    /// Build parser-compatible placeholders without requiring users to edit syntax.
    static func token(name: String, kind: InputKind, choices: [String], defaultValue: String?) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let choices = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if kind == .dropdown {
            guard !choices.isEmpty, choices.allSatisfy({ !$0.isEmpty && !$0.contains(",") && !$0.contains(where: \.isNewline) }),
                  Set(choices).count == choices.count,
                  defaultValue == nil || defaultValue == "" || choices.contains(defaultValue!) else { return nil }
        }
        func quoted(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        var properties = ["name=\"\(quoted(name))\""]
        if kind == .dropdown { properties.append("options=\"\(quoted(choices.joined(separator: ",")))\"") }
        if let defaultValue { properties.append("default=\"\(quoted(defaultValue))\"") }
        if kind == .password { properties.append("type=\"password\"") }
        return "{argument \(properties.joined(separator: " "))}"
    }

    static func occurrence(in text: String, selection: NSRange) -> Occurrence? {
        occurrences(in: text).first { occurrence in
            selection.location >= occurrence.range.location && NSMaxRange(selection) <= NSMaxRange(occurrence.range)
        }
    }
}

/// A new keystroke or focus change invalidates an earlier expansion deadline.
/// Tickets are consumed once, so a shorter trigger cannot win after a longer
/// trigger has been typed during the pause.
struct SnippetExpansionDebounce {
    static let delay: TimeInterval = 1
    private var revision: UInt64 = 0
    private var pending: TextSnippet?

    struct Ticket {
        let revision: UInt64
        let typedTrigger: String
    }

    mutating func cancel() {
        revision &+= 1
        pending = nil
    }

    mutating func update(buffer: String, snippets: [TextSnippet]) -> Ticket? {
        cancel()
        guard let snippet = TextSnippetSupport.match(buffer: buffer, expansion: .immediate, snippets: snippets) else { return nil }
        pending = snippet
        return Ticket(revision: revision, typedTrigger: String(buffer.suffix(snippet.trigger.count)))
    }

    mutating func take(_ ticket: Ticket) -> TextSnippet? {
        guard ticket.revision == revision, let snippet = pending else { return nil }
        cancel()
        return snippet
    }
}
