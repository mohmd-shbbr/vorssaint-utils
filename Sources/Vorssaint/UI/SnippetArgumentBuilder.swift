// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SnippetArgumentBuilder: View {
    let strings: SnippetFeatureStrings
    let cancelLabel: String
    let initial: SnippetArgumentSupport.Argument?
    let confirm: (String) -> Void
    let cancel: () -> Void
    @State private var name: String
    @State private var kind: SnippetArgumentSupport.InputKind
    @State private var choices: [Choice]
    @State private var usesDefault: Bool
    @State private var defaultValue: String
    @FocusState private var nameFocused: Bool

    private struct Choice: Identifiable {
        let id = UUID()
        var value: String
    }

    init(strings: SnippetFeatureStrings, cancelLabel: String,
         initial: SnippetArgumentSupport.Argument?,
         confirm: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.strings = strings
        self.cancelLabel = cancelLabel
        self.initial = initial
        self.confirm = confirm
        self.cancel = cancel
        _name = State(initialValue: initial?.id.hasPrefix("name:") == true ? initial!.name : "")
        _kind = State(initialValue: initial?.options.isEmpty == false ? .dropdown : initial?.password == true ? .password : .text)
        _choices = State(initialValue: initial?.options.isEmpty == false
                         ? initial!.options.map { Choice(value: $0) } : [Choice(value: "")])
        _usesDefault = State(initialValue: initial?.defaultValue != nil)
        _defaultValue = State(initialValue: initial?.defaultValue ?? "")
    }

    private var token: String? {
        SnippetArgumentSupport.token(name: name, kind: kind, choices: choices.map(\.value),
                                     defaultValue: usesDefault ? defaultValue : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? strings.argumentField : strings.argumentEditLabel).font(.headline)
            Form {
                TextField(strings.nameLabel, text: $name).focused($nameFocused)
                Picker(strings.argumentTypeLabel, selection: $kind) {
                    Text(strings.argumentTextType).tag(SnippetArgumentSupport.InputKind.text)
                    Text(strings.argumentDropdownType).tag(SnippetArgumentSupport.InputKind.dropdown)
                    Text(strings.argumentPasswordType).tag(SnippetArgumentSupport.InputKind.password)
                }
            }.formStyle(.columns).fixedSize(horizontal: false, vertical: true)
            if kind == .dropdown {
                Text(strings.argumentChoicesLabel).font(.subheadline)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($choices) { $choice in
                            HStack {
                                TextField(strings.argumentChoicesLabel, text: $choice.value)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    choices.removeAll { $0.id == choice.id }
                                } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(strings.deleteButton)
                            }
                        }
                    }.padding(1)
                }.frame(height: min(170, CGFloat(max(1, choices.count)) * 32))
                Button { choices.append(Choice(value: "")) } label: {
                    Label(strings.argumentAddChoice, systemImage: "plus")
                }
                Text(strings.argumentChoicesHint).font(.caption).foregroundStyle(.secondary)
                if token == nil, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(strings.argumentChoicesError).font(.caption).foregroundStyle(.orange)
                }
            }
            Toggle(strings.argumentUseDefault, isOn: $usesDefault)
            if usesDefault {
                if kind == .dropdown {
                    Picker(strings.argumentDefaultLabel, selection: $defaultValue) {
                        Text(strings.argumentEmptyDefault).tag("")
                        ForEach(Array(Set(choices.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted(), id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                } else if kind == .password {
                    SecureField(strings.argumentDefaultLabel, text: $defaultValue)
                } else {
                    TextField(strings.argumentDefaultLabel, text: $defaultValue)
                }
            }
            HStack {
                Spacer()
                Button(cancelLabel, action: cancel).keyboardShortcut(.cancelAction)
                Button(initial == nil ? strings.argumentInsert : strings.saveButton) {
                    if let token { confirm(token) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(token == nil)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear { nameFocused = true }
        .onChange(of: kind) { _, _ in defaultValue = "" }
        .onChange(of: choices.map(\.value)) { _, values in
            if kind == .dropdown, !values.contains(defaultValue) { defaultValue = "" }
        }
    }
}
