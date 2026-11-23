import Testing
import Foundation
@testable import Differentialis

@Suite("Syntax highlighting")
struct SyntaxHighlighterTests {
    /// The text each token covers, paired with its kind, for readable expectations.
    private func spans(_ line: String, _ language: SyntaxLanguage) -> [String: SyntaxTokenKind] {
        let tokens = SyntaxHighlighter.tokenize(lines: [line], language: language)[0]
        return pieces(line, tokens)
    }

    private func pieces(_ line: String, _ tokens: [SyntaxToken]) -> [String: SyntaxTokenKind] {
        let chars = Array(line)
        var result: [String: SyntaxTokenKind] = [:]
        for token in tokens {
            result[String(chars[token.range])] = token.kind
        }
        return result
    }

    private func lines(_ text: String, _ language: SyntaxLanguage) -> [[String: SyntaxTokenKind]] {
        let split = LineDiff.split(text)
        let tokens = SyntaxHighlighter.tokenize(text: text, language: language)
        return zip(split, tokens).map { pieces($0, $1) }
    }

    // MARK: - Language detection

    @Test func detectsLanguagesFromFileNames() {
        #expect(SyntaxLanguage(fileName: "Package.swift") == .swift)
        #expect(SyntaxLanguage(fileName: "src/App.TSX") == .typeScript)
        #expect(SyntaxLanguage(fileName: "index.mjs") == .javaScript)
        #expect(SyntaxLanguage(fileName: "setup.py") == .python)
        #expect(SyntaxLanguage(fileName: ".eslintrc.json") == .json)
        #expect(SyntaxLanguage(fileName: "ci.yml") == .yaml)
        #expect(SyntaxLanguage(fileName: "README.md") == .markdown)
        #expect(SyntaxLanguage(fileName: "build.sh") == .shell)
        #expect(SyntaxLanguage(fileName: ".zshrc") == .shell)
        #expect(SyntaxLanguage(fileName: "/Users/me/.bash_profile") == .shell)
        #expect(SyntaxLanguage(fileName: "main.cpp") == .cFamily)
        #expect(SyntaxLanguage(fileName: "View.m") == .cFamily)
        #expect(SyntaxLanguage(fileName: "notes.txt") == nil)
        #expect(SyntaxLanguage(fileName: "Makefile") == nil)
        #expect(SyntaxLanguage(fileName: ".gitignore") == nil)
    }

    // MARK: - Per-language basics

    @Test func swiftLine() {
        let s = spans(#"@MainActor func load(id: Int) -> String? { return "x\"y" // done"#, .swift)
        #expect(s["@MainActor"] == .attribute)
        #expect(s["func"] == .keyword)
        #expect(s["Int"] == .type)
        #expect(s["String"] == .type)
        #expect(s["return"] == .keyword)
        #expect(s[#""x\"y""#] == .string)
        #expect(s["// done"] == .comment)
        #expect(s["load"] == nil)
        #expect(s["id"] == nil)
    }

    @Test func swiftDirectivesLiteralsAndNumbers() {
        let s = spans("#if DEBUG let x = nil ?? 0x1F + 1.5e-3", .swift)
        #expect(s["#if"] == .attribute)
        #expect(s["DEBUG"] == nil)   // all caps: a constant, not a type
        #expect(s["nil"] == .literal)
        #expect(s["0x1F"] == .number)
        #expect(s["1.5e-3"] == .number)
    }

    @Test func memberAccessIsNotAKeyword() {
        let s = spans("node.type = options.default", .typeScript)
        #expect(s["type"] == nil)
        #expect(s["default"] == nil)
        #expect(spans("type Point = { x: number }", .typeScript)["type"] == .keyword)
    }

    @Test func keywordsUsedAsLabelsStayPlain() {
        let swift = spans("move(in: view, default: 1)", .swift)
        #expect(swift["in"] == nil)
        #expect(swift["default"] == nil)
        #expect(spans("    default: break", .swift)["default"] == .keyword)
        #expect(spans("switch x { default: break }", .swift)["default"] == .keyword)
        let js = spans("const o = { default: 1, if: 2 }; o ? a : b", .javaScript)
        #expect(js["default"] == nil)
        #expect(js["if"] == nil)
        #expect(js["const"] == .keyword)
        // Python has no such labels: `lambda:` is always the keyword.
        #expect(spans("sorted(xs, key=lambda: 0)", .python)["lambda"] == .keyword)
    }

    @Test func swiftNestedBlockCommentsSpanLines() {
        let result = lines("""
        let a = 1 /* outer
        /* inner */ still comment
        end */ let b = 2
        """, .swift)
        #expect(result[0]["/* outer"] == .comment)
        #expect(result[1]["/* inner */ still comment"] == .comment)
        #expect(result[2]["end */"] == .comment)
        #expect(result[2]["let"] == .keyword)
        #expect(result[2]["2"] == .number)
    }

    @Test func multilineStringsCarryAcrossLines() {
        let swift = lines(#"""
        let s = """
        if not code
        """
        return s
        """#, .swift)
        #expect(swift[1]["if not code"] == .string)
        #expect(swift[3]["return"] == .keyword)

        let python = lines("""
        x = '''doc
        def not_a_def
        ''' if y else None
        """, .python)
        #expect(python[1]["def not_a_def"] == .string)
        #expect(python[2]["if"] == .keyword)
        #expect(python[2]["None"] == .literal)
    }

    @Test func unterminatedSingleLineStringStopsAtEndOfLine() {
        let result = lines("""
        let s = "open
        return
        """, .swift)
        #expect(result[0]["\"open"] == .string)
        #expect(result[1]["return"] == .keyword)
    }

    @Test func pythonPrefixesDecoratorsAndComments() {
        let s = spans(#"@functools.wraps(f) def g(): return rb"\x00" # bytes"#, .python)
        #expect(s["@functools.wraps"] == .attribute)
        #expect(s["def"] == .keyword)
        #expect(s[#"rb"\x00""#] == .string)
        #expect(s["# bytes"] == .comment)
        #expect(s["rb"] == nil)
    }

    @Test func javaScriptTemplateLiteralSpansLines() {
        let result = lines("""
        const s = `a
        if ${b}`; let c = $d
        """, .javaScript)
        #expect(result[0]["const"] == .keyword)
        #expect(result[1]["if ${b}`"] == .string)
        #expect(result[1]["let"] == .keyword)
        #expect(result[1]["$d"] == nil)   // `$` is an identifier character in JS
    }

    @Test func jsonKeysValuesAndLiterals() {
        let s = spans(#"{"name": "diff", "count" : 3, "ok": true, "none": null}"#, .json)
        #expect(s[#""name""#] == .property)
        #expect(s[#""count""#] == .property)
        #expect(s[#""diff""#] == .string)
        #expect(s["3"] == .number)
        #expect(s["true"] == .literal)
        #expect(s["null"] == .literal)
    }

    @Test func yamlKeysCommentsAndScalars() {
        #expect(spans("  - name: build # step", .yaml)["name"] == .property)
        #expect(spans("  - name: build # step", .yaml)["# step"] == .comment)
        let url = spans("url: http://example.com#anchor", .yaml)
        #expect(url["url"] == .property)
        #expect(url["#anchor"] == nil)   // not at a word start
        #expect(spans("enabled: True", .yaml)["True"] == .literal)
        #expect(spans(#""quoted key": 'v'"#, .yaml)[#""quoted key""#] == .property)
        #expect(spans(#""quoted key": 'v'"#, .yaml)["'v'"] == .string)
        #expect(spans("a:b: c", .yaml)["a:b"] == .property)
        #expect(spans("- plain item", .yaml).isEmpty)
    }

    @Test func shellVariablesStringsAndComments() {
        let s = spans(#"if [ -n "$HOME" ]; then echo ${PATH} $1 'it''s' --done; fi # end"#, .shell)
        #expect(s["if"] == .keyword)
        #expect(s["then"] == .keyword)
        #expect(s["fi"] == .keyword)
        #expect(s["${PATH}"] == .property)
        #expect(s["$1"] == .property)
        #expect(s[#""$HOME""#] == .string)
        #expect(s["# end"] == .comment)
        #expect(s["done"] == nil)
        #expect(spans("echo a#b ${#arr}", .shell)["${#arr}"] == .property)
        #expect(spans("echo a#b ${#arr}", .shell)["#b ${#arr}"] == nil)
    }

    @Test func shellHeredocsEndAtTheirTerminator() {
        let result = lines("""
        cat <<-'EOF' > out.txt
        Don't panic
        \tEOF
        echo hi # done
        """, .shell)
        #expect(result[0]["<<-'EOF'"] == .attribute)
        #expect(result[1]["Don't panic"] == .string)
        #expect(result[2]["\tEOF"] == .string)
        #expect(result[3]["# done"] == .comment)
        #expect(result[3]["echo hi"] == nil)
        // A here-string and arithmetic shifts are not here-documents.
        #expect(lines("x=$(( 1 << 2 ))\nif true", .shell)[1]["if"] == .keyword)
        #expect(lines("tr a b <<< word\nif true", .shell)[1]["if"] == .keyword)
        // ANSI-C quoting escapes its quote and stays on its line.
        let ansi = lines("echo $'it\\'s'\nif true", .shell)
        #expect(ansi[0]["$'it\\'s'"] == .string)
        #expect(ansi[1]["if"] == .keyword)
    }

    @Test func javaScriptRegexLiteralsDontOpenStringsOrComments() {
        let result = lines("""
        x = s.replace(/`/g, '').replace(/\\/*$/, "")
        const y = a / b / c
        return /[/]x/i.test(z)
        """, .javaScript)
        #expect(result[0]["/`/g"] == .string)
        #expect(result[0]["/\\/*$/"] == .string)
        #expect(result[1]["const"] == .keyword)
        #expect(result[1].count == 1)   // division, not a regex
        #expect(result[2]["/[/]x/i"] == .string)
        #expect(result[2]["return"] == .keyword)
    }

    @Test func numbersInRangesAndCppSeparators() {
        let swift = spans("for i in 1...5 { t.0 }", .swift)
        #expect(swift["1"] == .number)
        #expect(swift["5"] == .number)
        #expect(swift[".5"] == nil)
        #expect(spans("int n = 1'000'000;", .cFamily)["1'000'000"] == .number)
    }

    @Test func cFamilyPreprocessorAndObjectiveC() {
        let include = spans("#include <stdio.h> // io", .cFamily)
        #expect(include["#include"] == .attribute)
        #expect(include["<stdio.h>"] == .string)
        #expect(include["// io"] == .comment)
        let objc = spans(#"@property (nonatomic) NSString *name; // x"#, .cFamily)
        #expect(objc["@property"] == .keyword)
        #expect(objc["NSString"] == .type)
        let cpp = spans("static_cast<uint8_t>(x) == nullptr ? 'a' : sizeof(int)", .cFamily)
        #expect(cpp["static_cast"] == .keyword)
        #expect(cpp["uint8_t"] == .type)
        #expect(cpp["nullptr"] == .literal)
        #expect(cpp["'a'"] == .string)
        #expect(spans("x = a # b", .cFamily)["#"] == nil)   // only a directive at line start
    }

    @Test func markdownBlocks() {
        let result = lines("""
        # Title
        - item with `code` and [link](https://x.y)
        ```swift
        # not a heading
        ```
        > quoted
        1. first <!-- note
        still note --> after
        """, .markdown)
        #expect(result[0]["# Title"] == .heading)
        #expect(result[1]["-"] == .keyword)
        #expect(result[1]["`code`"] == .string)
        #expect(result[1]["(https://x.y)"] == .property)
        #expect(result[2]["```swift"] == .string)
        #expect(result[3]["# not a heading"] == .string)
        #expect(result[4]["```"] == .string)
        #expect(result[5]["> quoted"] == .comment)
        #expect(result[6]["1."] == .keyword)
        #expect(result[6]["<!-- note"] == .comment)
        #expect(result[7]["still note -->"] == .comment)
        #expect(result[7].count == 1)
        #expect(spans("#hashtag", .markdown).isEmpty)
        // ```code``` is inline code, not a fence: the next line is still a heading.
        let inline = lines("```code``` here\n# Next", .markdown)
        #expect(inline[0]["```code```"] == .string)
        #expect(inline[1]["# Next"] == .heading)
    }

    // MARK: - Coordinates, limits, and robustness

    @Test func offsetsAreCharacterOffsets() {
        // Emoji and combining marks are one Character each, matching DiffRow highlight offsets.
        let line = #"let 👩‍👩‍👧 = "é" // ok"#
        let tokens = SyntaxHighlighter.tokenize(lines: [line], language: .swift)[0]
        let chars = Array(line)
        let string = tokens.first { $0.kind == .string }
        #expect(string.map { String(chars[$0.range]) } == #""é""#)
        #expect(tokens.allSatisfy { $0.range.upperBound <= chars.count })
    }

    @Test func tokensAreSortedAndDisjoint() {
        let text = """
        import Foundation
        /// Doc
        struct A<T: Hashable>: Sendable { let x = [1, 2.0, -3]; var s = "\\(x)" }
        """
        for line in SyntaxHighlighter.tokenize(text: text, language: .swift) {
            for (a, b) in zip(line, line.dropFirst()) {
                #expect(a.range.upperBound <= b.range.lowerBound)
            }
            #expect(line.allSatisfy { !$0.range.isEmpty })
        }
    }

    @Test func lineSplittingMatchesTheDiff() {
        let text = "a = 1\r\nb = 'x'\rc = None\n"
        let tokens = SyntaxHighlighter.tokenize(text: text, language: .python)
        #expect(tokens.count == LineDiff.split(text).count)
        let mapped = SyntaxLines(left: tokens, right: [])
        #expect(mapped.left(3).map(\.kind) == [.literal])
        #expect(mapped.left(0).isEmpty)
        #expect(mapped.left(4).isEmpty)
        #expect(mapped.right(1).isEmpty)
        #expect(mapped.left(nil).isEmpty)
    }

    @Test func overlongLinesStayPlainAndKeepState() {
        let long = String(repeating: "x", count: SyntaxHighlighter.maxLineLength + 1)
        let result = SyntaxHighlighter.tokenize(lines: ["/* open", long, "*/ let a"], language: .swift)
        #expect(result[1].isEmpty)
        #expect(result[2].map(\.kind) == [.comment, .keyword])
    }

    @Test func oversizedTextIsNotHighlighted() {
        let huge = String(repeating: "let x = 1\n", count: SyntaxHighlighter.maxTextLength / 10 + 1)
        #expect(SyntaxHighlighter.tokenize(text: huge, language: .swift).isEmpty)
    }

    @Test func everyLanguageSurvivesHostileInput() {
        let hostile = [
            "", "\"", "'", "`", "\\", "/*", "*/", "#", "$", "${", "@", "<!--", "]((", "```",
            "\"\"\"", "'''", "0x", "1e", ".5", "- ", ": :", "\u{301}", "a\\", "\"\\",
        ]
        for language in SyntaxLanguage.allCases {
            let result = SyntaxHighlighter.tokenize(lines: hostile, language: language)
            #expect(result.count == hostile.count)
            for (line, tokens) in zip(hostile, result) {
                #expect(tokens.allSatisfy { $0.range.lowerBound >= 0 && $0.range.upperBound <= line.count })
            }
        }
    }
}
