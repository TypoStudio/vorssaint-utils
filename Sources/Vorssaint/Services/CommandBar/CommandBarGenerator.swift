// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// The bar's answer when what was typed asks for a string to be made rather
/// than found: a password, a run of hex, a UUID, or the digest of some text.
///
/// Strict about its own names, the way the calculator is strict about sums: a
/// word it knows followed by anything it cannot read as a length is not a
/// request, so "password manager" stays a search.
enum CommandBarGenerator {
    enum Kind: Equatable {
        case password
        case hex
        case uuid
        case md5
        case sha256
    }

    struct Result: Equatable {
        let kind: Kind
        let value: String
    }

    /// Long enough for any key worth carrying in a row, short enough that a
    /// mistyped length cannot fill the bar with noise.
    static let maxLength = 256
    static let defaultPasswordLength = 16
    static let defaultHexLength = 32

    private static let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digits = Array("0123456789")
    /// Kept to the symbols every field, shell and site accepts. A password
    /// that has to be retyped by hand because a site rejected a quote is a
    /// password the person stops using.
    private static let symbols = Array("!@#$%^&*()-_=+[]{};:,.?")

    /// Nil when the query is not asking for one of these, which is most of the
    /// time. A fresh value on every call: the caller holds on to the one it
    /// showed, or the row would change under the person as they type.
    static func evaluate(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let head = trimmed.prefix(while: { !$0.isWhitespace })
        let tail = trimmed.dropFirst(head.count).trimmingCharacters(in: .whitespaces)
        switch head.lowercased() {
        case "pwd", "pw", "password":
            return password(arguments: tail).map { Result(kind: .password, value: $0) }
        case "hex":
            return hex(arguments: tail).map { Result(kind: .hex, value: $0) }
        case "uuid":
            guard tail.isEmpty else { return nil }
            return Result(kind: .uuid, value: UUID().uuidString)
        case "md5":
            guard !tail.isEmpty else { return nil }
            return Result(kind: .md5, value: hexDigest(Insecure.MD5.hash(data: Data(tail.utf8))))
        case "sha256":
            guard !tail.isEmpty else { return nil }
            return Result(kind: .sha256, value: hexDigest(SHA256.hash(data: Data(tail.utf8))))
        default:
            return nil
        }
    }

    // MARK: - Passwords

    /// Nothing, a length, or a composition: how many letters, then how many
    /// digits, then how many symbols. Anything else is not a request.
    private static func password(arguments: String) -> String? {
        guard let counts = lengths(in: arguments) else { return nil }
        switch counts.count {
        case 0:
            return mixedPassword(total: defaultPasswordLength)
        case 1:
            return mixedPassword(total: counts[0])
        case 2:
            return password(parts: [(letters, counts[0]), (digits, counts[1])])
        case 3:
            return password(parts: [(letters, counts[0]), (digits, counts[1]), (symbols, counts[2])])
        default:
            return nil
        }
    }

    /// A length on its own draws from everything, and guarantees one character
    /// of each kind once there is room for it: a random draw that happens to
    /// hold no digit is the one a site rejects.
    private static func mixedPassword(total: Int) -> String? {
        guard (1...maxLength).contains(total) else { return nil }
        let pool = Self.letters + digits + symbols
        var characters: [Character] = []
        if total >= 3 {
            characters.append(contentsOf: [Self.letters, digits, symbols].compactMap { $0.randomElement() })
        }
        while characters.count < total {
            guard let pick = pool.randomElement() else { return nil }
            characters.append(pick)
        }
        return String(characters.shuffled())
    }

    private static func password(parts: [([Character], Int)]) -> String? {
        let total = parts.reduce(0) { $0 + $1.1 }
        guard (1...maxLength).contains(total) else { return nil }
        var characters: [Character] = []
        for (pool, count) in parts {
            for _ in 0..<count {
                guard let pick = pool.randomElement() else { return nil }
                characters.append(pick)
            }
        }
        return String(characters.shuffled())
    }

    // MARK: - Hex

    private static func hex(arguments: String) -> String? {
        guard let counts = lengths(in: arguments), counts.count <= 1 else { return nil }
        let length = counts.first ?? defaultHexLength
        guard (1...maxLength).contains(length) else { return nil }
        let alphabet = Array("0123456789abcdef")
        var characters: [Character] = []
        characters.reserveCapacity(length)
        for _ in 0..<length {
            guard let pick = alphabet.randomElement() else { return nil }
            characters.append(pick)
        }
        return String(characters)
    }

    // MARK: - Reading the arguments

    /// The whole tail as numbers, or nil the moment one word is not one. A
    /// partial read would turn "pw for the router" into a password.
    static func lengths(in arguments: String) -> [Int]? {
        let words = arguments.split(whereSeparator: \.isWhitespace)
        var numbers: [Int] = []
        for word in words {
            guard let value = Int(word), value >= 0, value <= maxLength else { return nil }
            numbers.append(value)
        }
        return numbers
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
