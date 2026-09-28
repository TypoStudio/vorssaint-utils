// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rows that teach the bar's typed commands while they are being typed.
///
/// Every other row in the bar is found by its own name, so a person meets it
/// by looking for something. A command that answers to a word and reads what
/// follows it has no such row to bump into: nothing in the list says that
/// `dict` takes a word or that `pwd` takes three numbers, so the feature is
/// invisible until somebody is told about it. These rows are that telling,
/// offered while the word is still half typed and gone the moment it has an
/// argument and a real answer to show.
enum CommandBarHints {
    struct Hint: Equatable, Identifiable {
        /// The word that runs it, which is also what the row completes into
        /// the field.
        let trigger: String
        let source: CommandBarSource
        /// The shape of what comes after the word, for the ones that take
        /// something. Nil for a command that runs on its own name.
        let argument: Argument?

        var id: String { trigger }

        /// What Tab puts in the field, and what the row is ranked against.
        ///
        /// Not the row's title: that spells the argument out as "[word]", and
        /// completing it would leave those words in the field and look them
        /// up. A command that reads nothing is complete as it stands; the rest
        /// want the caret one space past the name, ready for the argument.
        /// The ranking folds the trailing space away, so it costs nothing
        /// there.
        var completion: String { argument == nil ? trigger : trigger + " " }
    }

    /// What a command reads after its name. Named rather than spelled out
    /// here, because the words it is spelled with are translated.
    enum Argument: Equatable {
        case word
        case text
        case length
        case passwordCounts
    }

    static let all: [Hint] = [
        Hint(trigger: "dic", source: .dictionary, argument: .word),
        Hint(trigger: "사전", source: .dictionary, argument: .word),
        Hint(trigger: "pwd", source: .generator, argument: .passwordCounts),
        Hint(trigger: "hex", source: .generator, argument: .length),
        Hint(trigger: "uuid", source: .generator, argument: nil),
        Hint(trigger: "md5", source: .generator, argument: .text),
        Hint(trigger: "sha256", source: .generator, argument: .text),
    ]

    /// The hints for what has been typed so far: every command whose name
    /// starts this way, and nothing once a space has been typed, because past
    /// that point the command is answering for itself.
    ///
    /// Two letters before an ASCII command is offered, so the single letter
    /// that starts half the apps on the Mac never has a hint sitting above
    /// them. One is enough for a Korean trigger: a syllable already carries
    /// what two Latin letters do, and 사 belongs to far less.
    static func matching(_ query: String) -> [Hint] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return [] }
        let minimum = trimmed.allSatisfy(\.isASCII) ? 2 : 1
        guard trimmed.count >= minimum else { return [] }
        return all.filter { $0.trigger.hasPrefix(trimmed) }
    }
}
