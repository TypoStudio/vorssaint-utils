// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Handing what was typed over to a search engine in the default browser, for
/// the moment the bar itself has no answer worth giving.
///
/// The engine is chosen here rather than read from the browser: Chrome, Arc
/// and Firefox keep their search engine to themselves, and the system's own
/// setting only follows Safari, so asking would get a different answer from
/// the one the person sees in their own browser.
enum CommandBarWebSearch {
    enum Engine: String, CaseIterable, Identifiable {
        case google
        case naver
        case bing
        case duckDuckGo

        var id: String { rawValue }

        /// A brand, written the same in every language.
        var name: String {
            switch self {
            case .google: return "Google"
            case .naver: return "Naver"
            case .bing: return "Bing"
            case .duckDuckGo: return "DuckDuckGo"
            }
        }

        private var base: (host: String, path: String, parameter: String) {
            switch self {
            case .google: return ("www.google.com", "/search", "q")
            case .naver: return ("search.naver.com", "/search.naver", "query")
            case .bing: return ("www.bing.com", "/search", "q")
            case .duckDuckGo: return ("duckduckgo.com", "/", "q")
            }
        }

        func url(for query: String) -> URL? {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = base.host
            components.path = base.path
            components.queryItems = [URLQueryItem(name: base.parameter, value: trimmed)]
            return components.url
        }
    }

    static let defaultEngine = Engine.google

    /// What was saved, or the default for anything that is not an engine this
    /// build knows: a value written by a later version must not leave the row
    /// with nowhere to go.
    static func engine(from raw: String?) -> Engine {
        raw.flatMap(Engine.init(rawValue:)) ?? defaultEngine
    }
}
