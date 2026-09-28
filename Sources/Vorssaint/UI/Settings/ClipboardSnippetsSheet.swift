// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The whole snippet list in one sheet: names down the left, the text of
/// whichever one is picked on the right.
///
/// A sheet rather than a page of its own, because this is a list somebody
/// opens when they want to change it and closes again, not a set of switches
/// they read past on the way to something else.
struct ClipboardSnippetsSheet: View {
    let text: ClipboardFeatureStrings

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = ClipboardHistoryService.shared
    @State private var draft: [ClipboardSnippet] = []
    @State private var selection: UUID?

    private var selectedIndex: Int? {
        draft.firstIndex { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(text.snippetsTitle)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            Divider()
            HStack(spacing: 0) {
                list
                Divider()
                editor
            }
            Divider()
            HStack {
                Text(text.snippetsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.s.menuClose) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 640, height: 420)
        .onAppear { draft = history.snippets }
        // Written on every edit rather than on close, so a sheet dismissed by
        // the Escape key or by the window going away keeps the work.
        .onChange(of: draft) { _, list in history.setSnippets(list) }
    }

    private var l10n: L10n { .shared }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($draft) { $snippet in
                    Text(snippet.label.isEmpty ? text.snippetsUntitled : snippet.label)
                        .lineLimit(1)
                        .tag(snippet.id)
                }
                .onMove { source, destination in
                    draft.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack(spacing: 0) {
                Button {
                    let snippet = ClipboardSnippet(label: text.snippetsUntitled)
                    draft.append(snippet)
                    selection = snippet.id
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help(text.snippetsAdd)
                Button {
                    guard let index = selectedIndex else { return }
                    draft.remove(at: index)
                    selection = draft.indices.contains(index) ? draft[index].id : draft.last?.id
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help(text.snippetsRemove)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private var editor: some View {
        if let index = selectedIndex {
            Form {
                TextField(text.snippetsLabel, text: $draft[index].label)
                Section {
                    TextEditor(text: $draft[index].value)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 200)
                } header: {
                    Text(text.snippetsValue)
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.star")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(text.snippetsEmpty)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
