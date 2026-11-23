import Foundation

/// Token categories the highlighter emits. Themes map each one to a foreground color
/// (`SyntaxPalette`); anything not tokenized keeps the normal text color.
enum SyntaxTokenKind: String, CaseIterable, Sendable {
    case keyword
    case type
    case string
    case number
    case comment
    /// Language constants: `true`, `nil`, `None`, `null`, …
    case literal
    /// Attributes, decorators, and preprocessor directives: `@MainActor`, `#if`, `#include`.
    case attribute
    /// Object keys and variables: JSON/YAML keys, shell `$VAR`, Markdown link targets.
    case property
    /// Markdown headings.
    case heading
}

/// One highlighted run in a line. `range` is a half-open **Character** offset range into the
/// line — the same coordinates as `DiffRow` intra-line highlights.
struct SyntaxToken: Hashable, Sendable {
    var range: Range<Int>
    var kind: SyntaxTokenKind
}

/// The languages the highlighter knows, picked by file name.
enum SyntaxLanguage: String, CaseIterable, Sendable {
    case swift
    case javaScript
    case typeScript
    case python
    case json
    case yaml
    case markdown
    case shell
    /// C, C++, and Objective-C share one grammar.
    case cFamily

    /// The language for a file name or path, from its extension (or, for extensionless shell
    /// dotfiles, its whole name). Nil for anything unrecognized, which stays plain text.
    init?(fileName: String) {
        let name = (fileName.split(separator: "/").last.map(String.init) ?? fileName).lowercased()
        if let language = Self.byName[name] {
            self = language
            return
        }
        // A leading dot is a hidden file's name, not an extension.
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              let language = Self.byExtension[String(name[name.index(after: dot)...])] else { return nil }
        self = language
    }

    private static let byExtension: [String: SyntaxLanguage] = [
        "swift": .swift,
        "js": .javaScript, "mjs": .javaScript, "cjs": .javaScript, "jsx": .javaScript,
        "ts": .typeScript, "tsx": .typeScript, "mts": .typeScript, "cts": .typeScript,
        "py": .python, "pyw": .python, "pyi": .python,
        "json": .json, "jsonc": .json,
        "yml": .yaml, "yaml": .yaml,
        "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
        "sh": .shell, "bash": .shell, "zsh": .shell, "ksh": .shell, "command": .shell,
        "c": .cFamily, "h": .cFamily, "cc": .cFamily, "cpp": .cFamily, "cxx": .cFamily,
        "c++": .cFamily, "hpp": .cFamily, "hh": .cFamily, "hxx": .cFamily, "h++": .cFamily,
        "m": .cFamily, "mm": .cFamily,
    ]

    private static let byName: [String: SyntaxLanguage] = [
        ".bashrc": .shell, ".bash_profile": .shell, ".bash_login": .shell, ".bash_logout": .shell,
        ".profile": .shell, ".zshrc": .shell, ".zshenv": .shell, ".zprofile": .shell,
        ".zlogin": .shell, ".zlogout": .shell,
    ]
}

/// Per-line syntax tokens for both sides of a comparison, indexed by 1-based line number
/// (`DiffRow.leftNumber` / `rightNumber`).
struct SyntaxLines: Sendable {
    var left: [[SyntaxToken]]
    var right: [[SyntaxToken]]

    func left(_ number: Int?) -> [SyntaxToken] { Self.tokens(left, number) }
    func right(_ number: Int?) -> [SyntaxToken] { Self.tokens(right, number) }

    private static func tokens(_ lines: [[SyntaxToken]], _ number: Int?) -> [SyntaxToken] {
        guard let number, number >= 1, number <= lines.count else { return [] }
        return lines[number - 1]
    }
}

/// A small, dependency-free syntax tokenizer: a per-line state machine driven by grammar data
/// (`SyntaxGrammar`). It carries block comments, multi-line strings, and Markdown code fences
/// across lines, so a whole document must be tokenized in order. It is deliberately lexical —
/// no parsing — and favors never mis-coloring long runs over catching every construct.
///
/// Pure and `Sendable`: call it off the main actor (it is linear in the text, but still real
/// work on large files).
enum SyntaxHighlighter {
    /// Texts larger than this (UTF-8 bytes) are not highlighted at all.
    static let maxTextLength = 4_000_000
    /// Lines longer than this (UTF-8 bytes) — typically minified code — stay plain; the
    /// multi-line state passes through them unchanged.
    static let maxLineLength = 4_000

    /// Tokens for each line of `text`, split exactly as `LineDiff.split` splits it. Empty when
    /// the text is too large to highlight.
    static func tokenize(text: String, language: SyntaxLanguage) -> [[SyntaxToken]] {
        guard text.utf8.count <= maxTextLength else { return [] }
        return tokenize(lines: LineDiff.split(text), language: language)
    }

    /// Tokens for each of `lines` (no terminators), in order.
    static func tokenize(lines: [String], language: SyntaxLanguage) -> [[SyntaxToken]] {
        let grammar = SyntaxGrammar.grammar(for: language)
        var state = SyntaxLineState.normal
        var result: [[SyntaxToken]] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            if line.utf8.count > maxLineLength {
                result.append([])
                continue
            }
            result.append(grammar.tokenizeLine(Array(line), state: &state))
        }
        return result
    }
}

/// What carries over from the end of one line to the start of the next.
enum SyntaxLineState: Hashable, Sendable {
    case normal
    case blockComment(depth: Int)
    /// Inside a multi-line string opened by `SyntaxGrammar.strings[rule]`.
    case string(rule: Int)
    /// Inside a Markdown fenced code block opened by `fence` (e.g. "```").
    case fencedCode(fence: String)
    /// Inside a shell here-document, until a line that is exactly `terminator` (after leading
    /// tabs, for `<<-`).
    case heredoc(terminator: String, stripTabs: Bool)
}

/// The data that drives `SyntaxHighlighter` for one language.
struct SyntaxGrammar: Sendable {
    struct StringRule: Sendable {
        var open: [Character]
        var close: [Character]
        var escape: Character? = "\\"
        var multiline = false
    }

    enum HashWords: Sendable {
        case none
        /// `#if`, `#available`, `#Preview` anywhere (Swift).
        case anywhere
        /// Preprocessor directives: `#` as the first non-blank character (C family).
        case lineStart
    }

    var language: SyntaxLanguage
    var lineComments: [[Character]] = []
    /// A line comment only starts at the beginning of a word (shell/YAML `#`).
    var commentNeedsWordStart = false
    var blockCommentOpen: [Character]? = nil
    var blockCommentClose: [Character]? = nil
    var nestedBlockComments = false
    /// Checked in order, so longer openers (`"""`) must come before their prefixes (`"`).
    var strings: [StringRule] = []
    var keywords: Set<String> = []
    var types: Set<String> = []
    var literals: Set<String> = []
    var caseInsensitiveLiterals = false
    /// Words like `String` / `URLSession` (uppercase first, some lowercase) read as types.
    var capitalizedAreTypes = false
    /// What `@word` is: Swift attributes, Python/TS decorators, Objective-C keywords.
    var atWords: SyntaxTokenKind? = nil
    var hashWords: HashWords = .none
    /// `$name`, `${…}`, `$1`, `$@` read as variables.
    var shellVariables = false
    /// A string directly followed by `:` is an object key (JSON).
    var stringKeys = false
    /// A reserved word directly followed by `:` right after `(`, `,`, or `{` is an argument
    /// label or (JS/TS) object key (`move(in: view)`, `{ default: 1 }`), not a keyword.
    var keywordsCanBeLabels = false
    /// JavaScript-style `/regex/flags` literals, recognized only where a value can start.
    var regexLiterals = false
    /// C++14 digit separators (`1'000'000`).
    var quoteDigitSeparators = false
    var identifierStart: Set<Character> = ["_"]
    var identifierContinue: Set<Character> = ["_"]

    // MARK: - Line lexer

    func tokenizeLine(_ c: [Character], state: inout SyntaxLineState) -> [SyntaxToken] {
        if language == .markdown { return markdownLine(c, state: &state) }

        var tokens: [SyntaxToken] = []
        let n = c.count
        var i = 0

        func emit(_ start: Int, _ end: Int, _ kind: SyntaxTokenKind) {
            guard end > start else { return }
            if let last = tokens.last, last.kind == kind, last.range.upperBound == start {
                tokens[tokens.count - 1].range = last.range.lowerBound..<end
            } else {
                tokens.append(SyntaxToken(range: start..<end, kind: kind))
            }
        }

        if case .heredoc(let terminator, let stripTabs) = state {
            let body = stripTabs ? String(c.drop { $0 == "\t" }) : String(c)
            if body == terminator { state = .normal }
            emit(0, n, .string)
            return tokens
        }
        if language == .yaml, state == .normal {
            i = yamlKey(c, emit: emit)
        }
        // A here-document starts on the line after its `<<WORD`, once this line is done.
        var pendingHeredoc: SyntaxLineState?

        while i < n {
            switch state {
            case .blockComment(let depth):
                let start = i
                var depth = depth
                while i < n && depth > 0 {
                    if nestedBlockComments, let open = blockCommentOpen, Self.matches(c, i, open) {
                        depth += 1
                        i += open.count
                    } else if let close = blockCommentClose, Self.matches(c, i, close) {
                        depth -= 1
                        i += close.count
                    } else {
                        i += 1
                    }
                }
                emit(start, i, .comment)
                state = depth == 0 ? .normal : .blockComment(depth: depth)
                continue
            case .string(let index):
                let rule = strings[index]
                let start = i
                let closed = Self.scanString(c, &i, rule)
                emit(start, i, .string)
                if closed || !rule.multiline { state = .normal }
                continue
            case .fencedCode, .heredoc:
                state = .normal   // Handled before the loop; never reached here.
            case .normal:
                break
            }

            let ch = c[i]
            if ch.isWhitespace {
                i += 1
                continue
            }
            if lineComments.contains(where: { Self.matches(c, i, $0) }),
               !commentNeedsWordStart || i == 0 || c[i - 1].isWhitespace {
                emit(i, n, .comment)
                i = n
                continue
            }
            if let open = blockCommentOpen, Self.matches(c, i, open) {
                emit(i, i + open.count, .comment)
                i += open.count
                state = .blockComment(depth: 1)
                continue
            }
            if regexLiterals, ch == "/", regexCanStart(c, at: i), let end = Self.scanRegex(c, from: i) {
                emit(i, end, .string)
                i = end
                continue
            }
            if language == .shell, ch == "<", let (end, heredoc) = Self.heredocStart(c, at: i) {
                emit(i, end, .attribute)
                pendingHeredoc = heredoc
                i = end
                continue
            }
            if let index = stringRule(at: i, in: c) {
                lexString(c, from: i, rule: index, i: &i, state: &state, emit: emit)
                continue
            }
            // `.5` is a number, but not the `5` of a `1...5` range or the `0` of `tuple.0`.
            if Self.isDigit(ch) || (ch == "." && i + 1 < n && Self.isDigit(c[i + 1])
                                    && (i == 0 || (c[i - 1] != "." && !isIdentifierContinue(c[i - 1])))) {
                let start = i
                i = Self.scanNumber(c, from: i, quoteSeparators: quoteDigitSeparators)
                emit(start, i, .number)
                continue
            }
            if isIdentifierStart(ch) {
                let start = i
                i += 1
                while i < n && isIdentifierContinue(c[i]) { i += 1 }
                let word = String(c[start..<i])
                // Python string prefixes: r"…", b'…', f"""…""".
                if language == .python, i < n, c[i] == "\"" || c[i] == "'",
                   Self.pythonStringPrefixes.contains(word.lowercased()),
                   let index = stringRule(at: i, in: c) {
                    lexString(c, from: start, rule: index, i: &i, state: &state, emit: emit)
                    continue
                }
                if let kind = classify(word, previous: start > 0 ? c[start - 1] : nil),
                   !(keywordsCanBeLabels && isLabel(c, start: start, end: i)) {
                    emit(start, i, kind)
                }
                continue
            }
            if ch == "@", let kind = atWords, i + 1 < n, isIdentifierStart(c[i + 1]) {
                let start = i
                i += 1
                // Dotted decorators (`@functools.wraps`) stay one token.
                while i < n && (isIdentifierContinue(c[i])
                                || (c[i] == "." && i + 1 < n && isIdentifierStart(c[i + 1]))) {
                    i += 1
                }
                emit(start, i, kind)
                continue
            }
            if ch == "#", hashWords != .none, i + 1 < n, c[i + 1].isLetter,
               hashWords == .anywhere || c[..<i].allSatisfy(\.isWhitespace) {
                let start = i
                i += 1
                while i < n && isIdentifierContinue(c[i]) { i += 1 }
                emit(start, i, .attribute)
                // `#include <path>` / `#import <path>`: the bracketed path is a string.
                if hashWords == .lineStart {
                    var j = i
                    while j < n && c[j].isWhitespace { j += 1 }
                    if j < n, c[j] == "<", let close = c[(j + 1)...].firstIndex(of: ">") {
                        emit(j, close + 1, .string)
                        i = close + 1
                    }
                }
                continue
            }
            if shellVariables, ch == "$", i + 1 < n {
                let start = i
                let next = c[i + 1]
                // ANSI-C quoting, `$'it\'s'`: single-line, with backslash escapes.
                if next == "'" {
                    i += 2
                    _ = Self.scanString(c, &i, StringRule(open: ["'"], close: ["'"]))
                    emit(start, i, .string)
                    continue
                }
                if next == "{" {
                    i += 2
                    while i < n && c[i] != "}" { i += 1 }
                    if i < n { i += 1 }
                    emit(start, i, .property)
                    continue
                }
                if next.isLetter || next == "_" {
                    i += 2
                    while i < n && (c[i].isLetter || Self.isDigit(c[i]) || c[i] == "_") { i += 1 }
                    emit(start, i, .property)
                    continue
                }
                if Self.isDigit(next) || "@#?*!$-".contains(next) {
                    i += 2
                    emit(start, i, .property)
                    continue
                }
            }
            i += 1
        }
        if let pendingHeredoc, state == .normal { state = pendingHeredoc }
        return tokens
    }

    /// Whether a `/` at `i` can open a regex rather than divide: at the start of the line, after
    /// an operator or opening punctuation, or after a keyword such as `return`.
    private func regexCanStart(_ c: [Character], at i: Int) -> Bool {
        guard let before = c[..<i].lastIndex(where: { !$0.isWhitespace }) else { return true }
        let p = c[before]
        // `i++ / 2` divides; `</p>` closes a JSX tag.
        if (p == "+" || p == "-"), before > 0, c[before - 1] == p { return false }
        if "(,=:[!&|?{};+-*%>~^".contains(p) { return true }
        guard isIdentifierContinue(p) else { return false }
        var start = before
        while start > 0 && isIdentifierContinue(c[start - 1]) { start -= 1 }
        return Self.regexPrecedingWords.contains(String(c[start...before]))
    }

    private static let regexPrecedingWords: Set<String> = [
        "return", "typeof", "case", "do", "else", "in", "of", "new", "delete", "void", "throw",
        "yield", "await",
    ]

    /// The end of a `/…/flags` regex starting at `i`, or nil when it doesn't close on this line
    /// (then the `/` is treated as division and no state carries over).
    private static func scanRegex(_ c: [Character], from i: Int) -> Int? {
        var j = i + 1
        var inClass = false
        while j < c.count {
            switch c[j] {
            case "\\":
                j += 2
                continue
            case "[":
                inClass = true
            case "]":
                inClass = false
            case "/" where !inClass:
                j += 1
                while j < c.count && c[j].isLetter { j += 1 }
                return j
            default:
                break
            }
            j += 1
        }
        return nil
    }

    /// `<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`, `<<\WORD` (not `<<<`, and not a shift inside
    /// `(( … ))` arithmetic): the end of the operator and word, and the state that starts on the
    /// next line.
    private static func heredocStart(_ c: [Character], at i: Int) -> (Int, SyntaxLineState)? {
        let n = c.count
        guard matches(c, i, ["<", "<"]), !matches(c, i + 2, ["<"]), i == 0 || c[i - 1] != "<" else { return nil }
        // Inside `$(( … ))` / `(( … ))`, `<<` is a left shift.
        let before = String(c[..<i])
        if before.components(separatedBy: "((").count > before.components(separatedBy: "))").count {
            return nil
        }
        var j = i + 2
        let stripTabs = j < n && c[j] == "-"
        if stripTabs { j += 1 }
        while j < n && (c[j] == " " || c[j] == "\t") { j += 1 }
        guard j < n else { return nil }
        let word: String
        if c[j] == "'" || c[j] == "\"" {
            let quote = c[j]
            guard let close = c[(j + 1)...].firstIndex(of: quote), close > j + 1 else { return nil }
            word = String(c[(j + 1)..<close])
            j = close + 1
        } else {
            if c[j] == "\\" { j += 1 }
            let wordStart = j
            while j < n && !c[j].isWhitespace && !";|&<>()'\"".contains(c[j]) { j += 1 }
            guard j > wordStart, c[wordStart].isLetter || c[wordStart] == "_" else { return nil }
            word = String(c[wordStart..<j])
        }
        return (j, .heredoc(terminator: word, stripTabs: stripTabs))
    }

    private func lexString(_ c: [Character], from start: Int, rule index: Int, i: inout Int,
                           state: inout SyntaxLineState,
                           emit: (Int, Int, SyntaxTokenKind) -> Void) {
        let rule = strings[index]
        // `i` may sit after a Python prefix; the opener starts at the quote.
        var j = i
        while !Self.matches(c, j, rule.open) { j += 1 }
        j += rule.open.count
        let closed = Self.scanString(c, &j, rule)
        var kind = SyntaxTokenKind.string
        if closed, stringKeys, Self.nextNonBlank(c, from: j) == ":" { kind = .property }
        emit(start, j, kind)
        i = j
        if !closed && rule.multiline { state = .string(rule: index) }
    }

    private func classify(_ word: String, previous: Character?) -> SyntaxTokenKind? {
        // Member access (`node.type`, `options.default`) is a name, not a keyword.
        if previous == "." { return nil }
        // The tail of a longer word the lexer split (shell `--done`, YAML `x-if`).
        if let previous, identifierContinue.contains(previous) { return nil }
        if literals.contains(caseInsensitiveLiterals ? word.lowercased() : word) { return .literal }
        if keywords.contains(word) { return .keyword }
        if types.contains(word) { return .type }
        if capitalizedAreTypes, let first = word.first, first.isUppercase,
           word.contains(where: \.isLowercase) {
            return .type
        }
        return nil
    }

    /// `word:` (not `word::`) right after `(`, `,`, or (JS/TS) `{` on the same line.
    private func isLabel(_ c: [Character], start: Int, end: Int) -> Bool {
        guard end < c.count, c[end] == ":", end + 1 == c.count || c[end + 1] != ":",
              let before = c[..<start].last(where: { !$0.isWhitespace }) else { return false }
        // Swift has no `{ key: value }` literals, so `{ default:` there is a one-line switch.
        return before == "(" || before == "," || (before == "{" && language != .swift)
    }

    private func stringRule(at i: Int, in c: [Character]) -> Int? {
        strings.firstIndex { Self.matches(c, i, $0.open) }
    }

    private func isIdentifierStart(_ ch: Character) -> Bool {
        ch.isLetter || identifierStart.contains(ch)
    }

    private func isIdentifierContinue(_ ch: Character) -> Bool {
        ch.isLetter || Self.isDigit(ch) || identifierContinue.contains(ch)
    }

    // MARK: - YAML keys

    /// Emits a block-mapping key at the start of the line (after indentation and `- ` sequence
    /// markers) and returns where general lexing should resume.
    private func yamlKey(_ c: [Character], emit: (Int, Int, SyntaxTokenKind) -> Void) -> Int {
        let n = c.count
        var i = 0
        while i < n && c[i].isWhitespace { i += 1 }
        while i + 1 < n && c[i] == "-" && c[i + 1].isWhitespace {
            i += 2
            while i < n && c[i].isWhitespace { i += 1 }
        }
        guard i < n else { return i }
        func endsKey(_ colon: Int) -> Bool {
            colon < n && c[colon] == ":" && (colon + 1 == n || c[colon + 1].isWhitespace)
        }
        if c[i] == "\"" || c[i] == "'" {
            guard let close = c[(i + 1)...].firstIndex(of: c[i]), endsKey(close + 1) else { return i }
            emit(i, close + 1, .property)
            return close + 2
        }
        guard !"#{[&*!|>%@`,?:-".contains(c[i]) else { return i }
        var j = i
        while j < n {
            if endsKey(j) {
                var end = j
                while end > i && c[end - 1].isWhitespace { end -= 1 }
                emit(i, end, .property)
                return j + 1
            }
            if c[j] == "#" && c[j - 1].isWhitespace { break }
            j += 1
        }
        return i
    }

    // MARK: - Markdown

    private func markdownLine(_ c: [Character], state: inout SyntaxLineState) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let n = c.count
        func emit(_ start: Int, _ end: Int, _ kind: SyntaxTokenKind) {
            if end > start { tokens.append(SyntaxToken(range: start..<end, kind: kind)) }
        }
        var indent = 0
        while indent < n && c[indent] == " " { indent += 1 }

        if case .fencedCode(let fence) = state {
            if indent < 4, Self.matches(c, indent, Array(fence)),
               c[(indent + fence.count)...].allSatisfy({ $0 == fence.first || $0.isWhitespace }) {
                state = .normal
            }
            emit(0, n, .string)
            return tokens
        }

        var i = 0
        if case .blockComment = state {
            let close = Self.htmlCommentClose
            while i < n && !Self.matches(c, i, close) { i += 1 }
            if i == n {
                emit(0, n, .comment)
                return tokens
            }
            i += close.count
            emit(0, i, .comment)
            state = .normal
        } else if indent < 4 && indent < n {
            let lead = c[indent]
            // Code fence: three or more backticks or tildes.
            if lead == "`" || lead == "~" {
                var run = indent
                while run < n && c[run] == lead { run += 1 }
                // A backtick fence's info string can't contain backticks (```a``` is inline code).
                if run - indent >= 3, lead == "~" || !c[run...].contains("`") {
                    state = .fencedCode(fence: String(c[indent..<run]))
                    emit(0, n, .string)
                    return tokens
                }
            }
            // ATX heading: 1–6 `#` then a space or the end of the line.
            if lead == "#" {
                var run = indent
                while run < n && c[run] == "#" { run += 1 }
                if run - indent <= 6 && (run == n || c[run] == " ") {
                    emit(indent, n, .heading)
                    return tokens
                }
            }
            if lead == ">" {
                emit(indent, n, .comment)
                return tokens
            }
            // List markers: `- `, `* `, `+ `, `1. `, `1) `.
            if "-*+".contains(lead), indent + 1 < n, c[indent + 1] == " " {
                emit(indent, indent + 1, .keyword)
                i = indent + 2
            } else if Self.isDigit(lead) {
                var run = indent
                while run < n && Self.isDigit(c[run]) { run += 1 }
                if run + 1 < n, c[run] == "." || c[run] == ")", c[run + 1] == " " {
                    emit(indent, run + 1, .keyword)
                    i = run + 2
                }
            }
        }

        while i < n {
            let ch = c[i]
            if ch == "\\" {
                i += 2
            } else if ch == "`" {
                var run = i
                while run < n && c[run] == "`" { run += 1 }
                let fence = Array(c[i..<run])
                var j = run
                while j < n && !Self.matches(c, j, fence) { j += 1 }
                if j < n {
                    emit(i, j + fence.count, .string)
                    i = j + fence.count
                } else {
                    i = run
                }
            } else if Self.matches(c, i, Self.htmlCommentOpen) {
                let start = i
                let close = Self.htmlCommentClose
                i += 4
                while i < n && !Self.matches(c, i, close) { i += 1 }
                if i < n {
                    i += close.count
                } else {
                    state = .blockComment(depth: 1)
                }
                emit(start, i, .comment)
            } else if ch == "]", i + 1 < n, c[i + 1] == "(",
                      let close = c[(i + 2)...].firstIndex(of: ")") {
                // Link or image target: `[text](url)`.
                emit(i + 1, close + 1, .property)
                i = close + 1
            } else {
                i += 1
            }
        }
        return tokens
    }

    // MARK: - Scanning helpers

    private static func matches(_ c: [Character], _ i: Int, _ pattern: [Character]) -> Bool {
        guard i >= 0, i + pattern.count <= c.count else { return false }
        for (offset, ch) in pattern.enumerated() where c[i + offset] != ch { return false }
        return true
    }

    /// Advances past a string body (the opener already consumed) through its closer, or to the
    /// end of the line. Returns whether the closer was found.
    private static func scanString(_ c: [Character], _ i: inout Int, _ rule: StringRule) -> Bool {
        while i < c.count {
            if let escape = rule.escape, c[i] == escape {
                i = min(i + 2, c.count)
                continue
            }
            if matches(c, i, rule.close) {
                i += rule.close.count
                return true
            }
            i += 1
        }
        return false
    }

    private static let htmlCommentOpen = Array("<!--")
    private static let htmlCommentClose = Array("-->")

    private static func scanNumber(_ c: [Character], from start: Int, quoteSeparators: Bool) -> Int {
        let n = c.count
        let isHex = start + 1 < n && c[start] == "0" && (c[start + 1] == "x" || c[start + 1] == "X")
        var i = start + 1
        while i < n {
            let ch = c[i]
            if ch.isASCII && (ch.isLetter || ch.isNumber) || ch == "_" {
                i += 1
            } else if ch == ".", i + 1 < n, isDigit(c[i + 1]) {
                i += 1
            } else if ch == "'", quoteSeparators, i + 1 < n, c[i + 1].isHexDigit {
                i += 1
            } else if ch == "+" || ch == "-", !isHex, c[i - 1] == "e" || c[i - 1] == "E" {
                i += 1
            } else {
                break
            }
        }
        return i
    }

    private static func nextNonBlank(_ c: [Character], from i: Int) -> Character? {
        c[i...].first { !$0.isWhitespace }
    }

    private static func isDigit(_ ch: Character) -> Bool {
        ch.isASCII && ch.isNumber
    }

    private static let pythonStringPrefixes: Set<String> = [
        "r", "u", "b", "f", "br", "rb", "fr", "rf",
    ]
}
