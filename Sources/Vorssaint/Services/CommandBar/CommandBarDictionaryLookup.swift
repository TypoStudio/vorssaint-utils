// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Asks every one of Naver's dictionaries for a word at once, debounced so
/// typing does not send a round of requests per keystroke, and cached by
/// exactly what was typed so a slow reply never overwrites the screen with an
/// answer meant for a different word.
///
/// The one place in the app that reaches the network for a person's typing, so
/// it stays behind a trigger word and behind a source switch, and it sends the
/// word and nothing else: no identifier, no history, no cookies.
///
/// Not part of the pure-function test harness (`./build.sh --test`): the
/// behavior here is a set of requests and a timer, not a calculation. What
/// comes back is parsed by `CommandBarDictionary`, which is tested.
final class CommandBarDictionaryLookup {
    struct Result: Equatable {
        let word: String
        let entries: [CommandBarDictionary.Entry]
    }

    /// Longer than the script runner's, because this one leaves the Mac: a
    /// word being typed out should cost one round of requests, not six.
    static let debounce: TimeInterval = 0.35

    /// Called on the main thread whenever a result becomes ready, so the
    /// caller can refresh what is on screen.
    var onResult: (() -> Void)?

    private var cache: [String: Result] = [:]
    /// The words whose requests are in the air right now. Without it, replies
    /// slower than the debounce would be asked for again by the next refresh
    /// while the first round is still coming.
    private var inFlight: Set<String> = []
    private var pendingWorkItem: DispatchWorkItem?
    private var generation = 0
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// A result only belongs to the current opening of the bar, the way a
    /// script's does: what was looked up last time is nobody's business the
    /// next time the bar opens.
    func reset() {
        generation &+= 1
        cancelPending()
        cache.removeAll()
        inFlight.removeAll()
    }

    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    func cachedResult(for word: String) -> Result? {
        cache[word]
    }

    /// Schedules a debounced round of requests, replacing whatever was
    /// pending. Does nothing when this exact word is already answered or
    /// already asked.
    func schedule(word: String) {
        guard cache[word] == nil, !inFlight.contains(word) else { return }
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.fetch(word: word) }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// Every dictionary at once rather than one after another: five replies
    /// arriving together cost what the slowest one costs, and a word is only
    /// worth showing when the row above it is not still being decided.
    private func fetch(word: String) {
        let runGeneration = generation
        inFlight.insert(word)
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [Int: [CommandBarDictionary.Entry]] = [:]
        for (index, book) in CommandBarDictionary.books.enumerated() {
            guard let url = CommandBarDictionary.requestURL(for: word, book: book) else { continue }
            group.enter()
            session.dataTask(with: request(url: url, host: book.host)) { data, _, _ in
                let entries = data.map { CommandBarDictionary.entries(from: $0, book: book) } ?? []
                lock.lock()
                collected[index] = entries
                lock.unlock()
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.generation == runGeneration else { return }
            self.inFlight.remove(word)
            // Kept in the order the dictionaries are listed in, so the same
            // word always reads the same way however the replies raced.
            var seen = Set<String>()
            let entries = collected.keys.sorted()
                .flatMap { collected[$0] ?? [] }
                // The other-language bucket repeats what a named dictionary
                // already answered often enough to matter.
                .filter { seen.insert($0.link?.absoluteString ?? $0.meaning).inserted }
            // An empty answer is cached too: without it, a word the
            // dictionaries do not have would be asked for again on every
            // keystroke that follows it.
            self.cache[word] = Result(word: word, entries: entries)
            self.onResult?()
        }
    }

    private func request(url: URL, host: String) -> URLRequest {
        var request = URLRequest(url: url)
        // The endpoint answers an empty body to anything that does not look
        // like the browser its own site runs in, so every reply would parse as
        // "nothing found" without this and the feature would silently do
        // nothing at all.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
                         + " (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
        return request
    }
}
