// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The fork's own additions, kept out of the upstream suites so a rebase onto
/// a new upstream never has to merge into them: the Command Bar's generators,
/// dictionary and typed-command hints, and the clipboard's named snippets.
enum ForkFeatureTests {
    static func run(_ suite: TestSuite) {
        func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                    file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(condition, message(), file: file, line: line)
        }

        // MARK: Command bar generators

        func generated(_ input: String) -> CommandBarGenerator.Result? {
            CommandBarGenerator.evaluate(input)
        }

        expect(generated("pwd")?.value.count == CommandBarGenerator.defaultPasswordLength,
               "a bare password request has a length of its own")
        expect(generated("pw 24")?.value.count == 24, "one number is the whole length")
        expect(generated("password 20")?.value.count == 20, "the long name works the same")
        expect(generated("pwd 10 2 2")?.value.count == 14,
               "letters, digits and symbols add up to what was asked for")
        if let composed = generated("pwd 10 2 2")?.value {
            expect(composed.filter(\.isLetter).count == 10, "the letters are counted out exactly")
            expect(composed.filter(\.isNumber).count == 2, "so are the digits")
            expect(composed.filter { !$0.isLetter && !$0.isNumber }.count == 2,
                   "and so are the symbols")
        }
        expect(generated("pwd 8 4")?.value.filter(\.isNumber).count == 4,
               "two numbers mean letters and digits, with no symbols")
        expect(generated("pwd 8 4")?.value.allSatisfy { $0.isLetter || $0.isNumber } == true,
               "a request without symbols gets none")
        if let mixed = generated("pwd 12")?.value {
            expect(mixed.contains(where: \.isLetter) && mixed.contains(where: \.isNumber),
                   "a mixed password is never dealt without a digit in it")
        }
        expect(generated("pwd") != generated("pwd"), "two draws are two passwords")
        expect(generated("pwd 0") == nil, "a password of nothing is not a request")
        expect(generated("pwd 999") == nil, "a length past the bound is refused, not clamped")
        expect(generated("pwd 8 4 2 1") == nil, "a fourth number means it was not a request")
        expect(generated("password manager") == nil,
               "a word after the name leaves it a search, not a password")
        expect(generated("pw for the router") == nil, "so does a whole sentence")

        expect(generated("hex")?.value.count == CommandBarGenerator.defaultHexLength,
               "hex has a length of its own too")
        expect(generated("hex 8")?.value.count == 8, "a number sets it")
        expect(generated("hex")?.value.allSatisfy { $0.isHexDigit && !$0.isUppercase } == true,
               "hex is hex, in one case")
        expect(generated("hex 8 8") == nil, "hex takes one number, not two")

        expect(generated("uuid")?.value.count == 36, "a UUID comes out in its usual shape")
        expect(generated("uuid")?.value.filter { $0 == "-" }.count == 4, "with its four dashes")
        expect(generated("uuid v4") == nil, "a UUID takes nothing after its name")

        expect(generated("md5 hello")?.value
                == "5d41402abc4b2a76b9719d911017c592", "MD5 is the digest everyone knows")
        expect(generated("sha256 hello")?.value
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
               "and so is SHA-256")
        expect(generated("sha256 hello world")?.value.count == 64,
               "the text to hash keeps its spaces")
        expect(generated("md5") == nil, "a digest of nothing is not a request")

        // MARK: Command bar dictionary

        expect(CommandBarDictionary.word(in: "dic 사랑") == "사랑",
               "the trigger is taken off and the word is what is left")
        expect(CommandBarDictionary.word(in: "사전 resilient") == "resilient",
               "the Korean trigger reads the same")
        expect(CommandBarDictionary.word(in: "DIC hello") == "hello", "the trigger ignores case")
        expect(CommandBarDictionary.word(in: "dic take off") == "take off",
               "a phrase stays one word to look up")
        expect(CommandBarDictionary.word(in: "dic") == nil, "the trigger alone asks nothing")
        expect(CommandBarDictionary.word(in: "dice roll") == nil,
               "a longer word that starts the same is not the trigger")

        let koko = CommandBarDictionary.books[0]
        expect(koko.dicType == "koko" && koko.host == "ko.dict.naver.com",
               "the Korean dictionary leads the round of requests")
        expect(CommandBarDictionary.books.contains { $0.dicType == "all" },
               "the bucket that carries every other language is asked too")
        expect(Set(CommandBarDictionary.books.map(\.dicType)).count
                == CommandBarDictionary.books.count,
               "no dictionary is asked twice")
        expect(CommandBarDictionary.requestURL(for: "사랑", book: koko)?.host == "ko.dict.naver.com",
               "the host follows the dictionary")
        expect(CommandBarDictionary.requestURL(for: "café", book: koko)?
                .absoluteString.contains("query=caf%C3%A9") == true,
               "the word is escaped into the address")
        expect(CommandBarDictionary.searchPageURL(for: "성직자")?.absoluteString
                == "https://dict.naver.com/dict.search?query=%EC%84%B1%EC%A7%81%EC%9E%90",
               "the combined page is where a row goes for everything else")

        expect(CommandBarDictionary.plainText("<strong>사랑</strong>") == "사랑",
               "the markup around a headword is taken off")
        expect(CommandBarDictionary.plainText("a &amp; b") == "a & b", "and its entities decoded")
        expect(CommandBarDictionary.plainText("<ruby><rb>聖職</rb><rt>せいしょく</rt></ruby>者")
                == "聖職者",
               "a Japanese reading printed above the kanji is dropped, not run into it")

        let dictionaryReply = Data("""
        {"searchResultMap":{"searchResultListMap":{"WORD":{"items":[
        {"expEntry":"<strong>사랑</strong>","destinationLink":"#/entry/koko/abc",
         "sourceDictnameKO":"표준국어대사전",
         "meansCollector":[{"means":[{"value":"몹시 아끼는 마음."},{"value":"소중히 여기는 일."},
                                     {"value":"세 번째 뜻."}]}]},
        {"expEntry":"<strong>사랑</strong>","destinationLink":"#/entry/koko/def",
         "sourceDictnameKO":"고려대한국어대사전",
         "meansCollector":[{"means":[{"value":"바깥주인이 거처하는 곳."}]}]},
        {"expEntry":"<strong>사랑</strong>","destinationLink":"#/entry/koko/ghi",
         "sourceDictnameKO":"우리말샘","meansCollector":[{"means":[{"value":"세 번째 항목."}]}]},
        {"expEntry":"<strong>없음</strong>","destinationLink":"#/entry/koko/jkl",
         "sourceDictnameKO":"표준국어대사전","meansCollector":[]}
        ]}}}}
        """.utf8)
        let parsed = CommandBarDictionary.entries(from: dictionaryReply, book: koko)
        expect(parsed.count == 2, "each dictionary contributes its first results, not all of them")
        expect(parsed.first?.word == "사랑", "the headword is unwrapped")
        expect(parsed.first?.meaning == "몹시 아끼는 마음. · 소중히 여기는 일.",
               "two meanings make the row and the rest stay in the entry")
        expect(parsed.first?.dictionaryName == "표준국어대사전",
               "the row says which dictionary answered")
        expect(parsed.first?.link?.absoluteString == "https://ko.dict.naver.com/#/entry/koko/abc",
               "a fragment is resolved against the dictionary that sent it")
        expect(CommandBarDictionary.entries(from: dictionaryReply, book: koko, limit: 4)
                .allSatisfy { !$0.meaning.isEmpty },
               "an item with no meaning is not offered a row of its own")
        expect(CommandBarDictionary.entries(from: Data(), book: koko).isEmpty,
               "an empty body reads as nothing found, not as a crash")
        expect(CommandBarDictionary.entries(from: Data("<html>nope</html>".utf8),
                                            book: koko).isEmpty,
               "and so does a body that is not the reply at all")

        // MARK: Command bar hints

        expect(CommandBarHints.matching("di").map(\.trigger) == ["dic"],
               "two letters are enough to be told what dict does")
        expect(CommandBarHints.matching("d").isEmpty,
               "one Latin letter is not, or every d would carry a hint")
        expect(CommandBarHints.matching("사").map(\.trigger) == ["사전"],
               "one Korean syllable is enough, since it belongs to far less")
        expect(CommandBarHints.matching("DIC").map(\.trigger) == ["dic"],
               "the match ignores case the way the command does")
        expect(CommandBarHints.matching("dic 사랑").isEmpty,
               "a command with its argument answers for itself and needs no hint")
        expect(CommandBarHints.matching("sha256").map(\.trigger) == ["sha256"],
               "a name typed in full still says what it takes")
        expect(CommandBarHints.matching("safari").isEmpty, "a word that merely starts alike does not")
        expect(CommandBarHints.matching("").isEmpty, "an empty field is not a half-typed command")
        expect(CommandBarHints.all.filter { $0.source == .generator }.map(\.trigger)
                == ["pwd", "hex", "uuid", "md5", "sha256"],
               "the generator chip lists every command it answers to, in a settled order")
        expect(CommandBarHints.all.filter { $0.source == .dictionary }.map(\.trigger)
                == ["dic", "사전"],
               "and the dictionary chip lists both of its triggers")
        expect(CommandBarHints.all.first { $0.trigger == "uuid" }?.argument == nil,
               "the one command that reads nothing says so")

        // Tab completes the command, not the row's title: completing the title
        // would put the words "[word]" in the field and then look them up.
        let dictionaryHint = CommandBarHints.all.first { $0.trigger == "dic" }
        expect(dictionaryHint?.completion == "dic ",
               "Tab leaves the caret one space past the command, ready for the word")
        expect(CommandBarCompletion.completedQuery(current: "di",
                                                   title: "dic [word]",
                                                   matchTitle: dictionaryHint?.completion) == "dic ",
               "so pressing Tab on the row leaves the field asking for a word")
        expect(CommandBarSearch.normalized(dictionaryHint?.completion ?? "") == "dic",
               "and the trailing space is nothing to the ranking")
        expect(CommandBarHints.all.first { $0.trigger == "uuid" }?.completion == "uuid",
               "a command that reads nothing completes without a trailing space")
        expect(CommandBarHints.all.allSatisfy { hint in
                   hint.source == .dictionary || CommandBarGenerator.evaluate(
                       hint.argument == nil ? hint.trigger : "\(hint.trigger) test") != nil
                       || hint.argument == .passwordCounts || hint.argument == .length
               },
               "every generator hint names a command the generator actually answers to")

        // MARK: Clipboard snippets

        let snippetList = [
            ClipboardSnippet(label: "Email", value: "gabi@example.com"),
            ClipboardSnippet(label: "주소", value: "서울시 강남구"),
            ClipboardSnippet(label: "Signature", value: "Thanks,\nGabi\nemail me"),
            ClipboardSnippet(label: "Café", value: "flat white"),
        ]
        func snippetLabels(_ query: String) -> [String] {
            ClipboardSnippetStore.matching(query, in: snippetList).map(\.label)
        }

        expect(snippetLabels("emai").first == "Email",
               "a snippet is found by the start of its label")
        expect(snippetLabels("EMAI").first == "Email", "and case is not what decides it")
        expect(snippetLabels("주소") == ["주소"], "a Korean label is matched as it was typed")
        expect(snippetLabels("cafe") == ["Café"], "accents are set aside on both sides")
        expect(snippetLabels("example.com") == ["Email"],
               "the text is searched too, not only the name")
        expect(snippetLabels("ema") == ["Email", "Signature"],
               "a label match leads a match found only in the text")
        expect(snippetLabels("thanks") == ["Signature"],
               "a phrase only the text carries still finds its snippet")
        expect(snippetLabels("").isEmpty, "an empty query offers no snippets at all")
        expect(snippetLabels("   ").isEmpty, "and neither does one that is only spaces")
        expect(snippetLabels("zzz").isEmpty, "a query that matches nothing offers nothing")

        expect(ClipboardSnippetStore.sanitized(
                [ClipboardSnippet(label: "  spaced  ", value: "x")]).first?.label == "spaced",
               "a label is trimmed on the way in")
        expect(ClipboardSnippetStore.sanitized(
                [ClipboardSnippet(label: "   ", value: "")]).isEmpty,
               "a snippet with no name and nothing to paste is dropped")
        expect(ClipboardSnippetStore.sanitized(
                [ClipboardSnippet(label: "", value: "still useful")]).count == 1,
               "but one with only text is kept, since it can still be pasted")

        let encoded = ClipboardSnippetStore.encode(snippetList)
        expect(ClipboardSnippetStore.decode(encoded) == snippetList,
               "a saved list comes back exactly as it went in")
        expect(ClipboardSnippetStore.decode(nil).isEmpty, "nothing saved decodes to no snippets")
        expect(ClipboardSnippetStore.decode(Data("not json".utf8)).isEmpty,
               "and a damaged list reads as empty rather than throwing")
        expect(ClipboardSnippetStore.decode(Data(#"[{"label":"old"}]"#.utf8)).first?.value == "",
               "a snippet saved before a field existed still loads")
    }
}
