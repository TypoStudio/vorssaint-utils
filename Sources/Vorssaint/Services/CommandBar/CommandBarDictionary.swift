// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reading Naver's dictionaries: the addresses that ask each of them for a
/// word, and what comes back.
///
/// Breadth rather than depth, the way the site's own combined search page
/// reads: the first result or two out of every dictionary that has the word,
/// so one glance says which languages carry it. Following one of them into its
/// full entry is what the browser is for.
///
/// Everything here is pure, so the shape of a reply is pinned by tests and the
/// lookup only has to fetch. The reply is the one Naver's own site asks for,
/// not a published API: it can change without notice, which is why every field
/// is optional and a reply that no longer parses reads as "nothing found"
/// rather than as an error worth showing.
enum CommandBarDictionary {
    /// The one word that puts the bar in the dictionary, in English and in
    /// Korean. A prefix rather than a mode: nothing is looked up until it is
    /// asked for by name, so ordinary typing never leaves the Mac.
    static let triggers = ["dic", "사전"]

    /// One of Naver's dictionaries, each of which answers on its own host.
    ///
    /// `all` is the site's own bucket for every language that has no host of
    /// its own, and it is what makes a word like 성직자 come back in French,
    /// Spanish and Thai as well. The hanja dictionary is missing on purpose:
    /// its host answers with that same bucket rather than with hanja, so
    /// asking it only produces the rows `all` already carries.
    struct Book: Equatable {
        let dicType: String
        let host: String
    }

    static let books: [Book] = [
        Book(dicType: "koko", host: "ko.dict.naver.com"),
        Book(dicType: "enko", host: "en.dict.naver.com"),
        Book(dicType: "jako", host: "ja.dict.naver.com"),
        Book(dicType: "zhko", host: "zh.dict.naver.com"),
        Book(dicType: "all", host: "ko.dict.naver.com"),
    ]

    struct Entry: Equatable {
        let word: String
        /// What the entry means, short enough for one row.
        let meaning: String
        /// The dictionary it came out of, named as Naver names it. Korean even
        /// in another interface language, because it is the dictionary's own
        /// name and not a word this app has to say.
        let dictionaryName: String
        let link: URL?
    }

    /// The whole query the bar was given, or nil when it is not asking for a
    /// word. Everything after the trigger is the word, spaces and all, so a
    /// two-word phrase looks up as one.
    static func word(in query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.prefix(while: { !$0.isWhitespace })
        guard triggers.contains(head.lowercased()) else { return nil }
        let word = trimmed.dropFirst(head.count).trimmingCharacters(in: .whitespaces)
        return word.isEmpty ? nil : word
    }

    static func requestURL(for word: String, book: Book) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = book.host
        components.path = "/api3/\(book.dicType)/search"
        components.queryItems = [
            URLQueryItem(name: "query", value: word),
            URLQueryItem(name: "m", value: "pc"),
            URLQueryItem(name: "range", value: "word"),
            URLQueryItem(name: "page", value: "1"),
        ]
        return components.url
    }

    /// The page a row opens when Return is pressed on it. Naver hands back a
    /// fragment ("#/entry/koko/…"), which only means anything against the host
    /// that produced it.
    static func entryURL(destination: String, book: Book) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http") { return URL(string: trimmed) }
        return URL(string: "https://\(book.host)/\(trimmed)")
    }

    /// The combined page every dictionary answers on, for the row that leaves
    /// the bar when there is nothing to show or more to read.
    static func searchPageURL(for word: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dict.naver.com"
        components.path = "/dict.search"
        components.queryItems = [URLQueryItem(name: "query", value: word)]
        return components.url
    }

    // MARK: - Reading the reply

    /// The first entries of one dictionary's reply, in the order Naver ranked
    /// them. Empty for a body that is not JSON at all, which is what the
    /// endpoint answers with when it does not like the request.
    static func entries(from data: Data, book: Book, limit: Int = 2) -> [Entry] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        let items = payload.searchResultMap?.searchResultListMap?.word?.items ?? []
        return items.compactMap { entry(from: $0, book: book) }.prefix(limit).map { $0 }
    }

    /// Nil for an item with no headword or nothing to say about it: a row that
    /// shows a word and no meaning is a row worth nobody's line.
    private static func entry(from item: Item, book: Book) -> Entry? {
        let word = plainText(item.expEntry ?? "")
        guard !word.isEmpty else { return nil }
        // Two meanings at most. One is often a single gloss and reads thin;
        // the whole list belongs in the entry the row opens, not in the row.
        let meanings = (item.meansCollector ?? [])
            .flatMap { $0.means ?? [] }
            .compactMap { mean -> String? in
                let text = plainText(mean.value ?? "")
                return text.isEmpty ? nil : text
            }
            .prefix(2)
        guard !meanings.isEmpty else { return nil }
        return Entry(word: word,
                     meaning: meanings.joined(separator: " · "),
                     dictionaryName: plainText(item.sourceDictnameKO ?? ""),
                     link: entryURL(destination: item.destinationLink ?? "", book: book))
    }

    /// Every field in the reply is marked-up HTML: the searched word comes
    /// back wrapped in <strong>, and a homograph carries its number in <sup>.
    static func plainText(_ raw: String) -> String {
        var output = ""
        var insideTag = false
        for character in dropRubyReadings(raw) {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { output.append(character) }
            }
        }
        return decodeEntities(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Japanese dictionary prints kanji with their reading above them, as
    /// <rb>聖職</rb><rt>せいしょく</rt>. Taking the tags off alone would leave
    /// the two runs jammed together and neither of them readable, so the
    /// reading goes before the tags do.
    private static func dropRubyReadings(_ raw: String) -> String {
        guard raw.contains("<rt") else { return raw }
        var output = ""
        var remainder = Substring(raw)
        while let open = remainder.range(of: "<rt") {
            output += remainder[remainder.startIndex..<open.lowerBound]
            guard let close = remainder.range(of: "</rt>", range: open.lowerBound..<remainder.endIndex)
            else { return output }
            remainder = remainder[close.upperBound...]
        }
        return output + remainder
    }

    private static func decodeEntities(_ text: String) -> String {
        var output = text
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            output = output.replacingOccurrences(of: entity, with: character)
        }
        return output
    }

    // MARK: - The shape of the reply

    private struct Payload: Decodable {
        let searchResultMap: ResultMap?
    }

    private struct ResultMap: Decodable {
        let searchResultListMap: ListMap?
    }

    private struct ListMap: Decodable {
        let word: WordList?

        enum CodingKeys: String, CodingKey {
            case word = "WORD"
        }
    }

    private struct WordList: Decodable {
        let items: [Item]?
    }

    private struct Item: Decodable {
        let expEntry: String?
        let destinationLink: String?
        let sourceDictnameKO: String?
        let meansCollector: [MeansCollector]?
    }

    private struct MeansCollector: Decodable {
        let means: [Mean]?
    }

    private struct Mean: Decodable {
        let value: String?
    }
}
