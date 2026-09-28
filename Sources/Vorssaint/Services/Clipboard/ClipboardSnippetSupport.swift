// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A piece of text kept on purpose, under a name of the person's choosing.
///
/// The history is what the Mac happened to copy; this is what somebody decided
/// was worth keeping. Pinning served that before and served it badly: a pinned
/// row still shows the text itself, cannot be renamed and sits in the same
/// list as everything else. A snippet is the label and the text kept apart, so
/// the list reads as names and the text stays out of the way until it is used.
struct ClipboardSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// What the row is called and what it is usually found by.
    var label = ""
    /// What gets pasted.
    var value = ""

    /// Decoded a field at a time, so a snippet saved before a field existed
    /// still loads. The list is decoded in one call, so a single missing key
    /// would otherwise throw and take every saved snippet down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    init(id: UUID = UUID(), label: String = "", value: String = "") {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// Reading, writing and searching the saved snippets. Pure, so every rule here
/// is pinned by tests and the service only has to store the result.
enum ClipboardSnippetStore {
    static func decode(_ data: Data?) -> [ClipboardSnippet] {
        guard let data, !data.isEmpty,
              let snippets = try? JSONDecoder().decode([ClipboardSnippet].self, from: data)
        else { return [] }
        return snippets
    }

    static func encode(_ snippets: [ClipboardSnippet]) -> Data {
        (try? JSONEncoder().encode(snippets)) ?? Data()
    }

    /// A snippet with neither a name nor anything to paste is not a snippet.
    /// Trimmed on the way in so a stray space cannot make an empty one look
    /// filled, and so two labels that differ only in spacing sort together.
    static func sanitized(_ snippets: [ClipboardSnippet]) -> [ClipboardSnippet] {
        snippets
            .map {
                ClipboardSnippet(id: $0.id,
                                 label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                                 value: $0.value)
            }
            .filter { !$0.label.isEmpty || !$0.value.isEmpty }
    }

    /// The snippets worth offering for what was typed, best first.
    ///
    /// Both halves are searched, because a person looks for a snippet by its
    /// name most of the time and by a phrase they remember being inside it the
    /// rest of the time. A name match still wins: it is the half they wrote
    /// deliberately, and the value can be a page long and match by accident.
    static func matching(_ query: String, in snippets: [ClipboardSnippet]) -> [ClipboardSnippet] {
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }
        return snippets
            .compactMap { snippet -> (ClipboardSnippet, Int)? in
                guard let rank = rank(snippet, needle: needle) else { return nil }
                return (snippet, rank)
            }
            // Stable within a rank, so the list does not reshuffle itself
            // between two keystrokes that match the same snippets.
            .enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }

    /// Lower is better: the name from its first letter, then the name
    /// anywhere, then the text itself.
    private static func rank(_ snippet: ClipboardSnippet, needle: String) -> Int? {
        let label = fold(snippet.label)
        if label.hasPrefix(needle) { return 0 }
        if label.contains(needle) { return 1 }
        if fold(snippet.value).contains(needle) { return 2 }
        return nil
    }

    /// Case and accents set aside, so "cafe" finds "Café" and a Korean label
    /// is matched as it was typed.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
