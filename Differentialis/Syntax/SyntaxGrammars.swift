import Foundation

/// Grammar data for each `SyntaxLanguage`. Word lists favor reserved words; contextual keywords
/// that are common identifiers (Swift `get`/`set`, Python `match`) are left out on purpose.
extension SyntaxGrammar {
    static func grammar(for language: SyntaxLanguage) -> SyntaxGrammar {
        switch language {
        case .swift: return swift
        case .javaScript: return javaScript
        case .typeScript: return typeScript
        case .python: return python
        case .json: return json
        case .yaml: return yaml
        case .markdown: return SyntaxGrammar(language: .markdown)
        case .shell: return shell
        case .cFamily: return cFamily
        }
    }

    private static let cStyleComments: (line: [[Character]], open: [Character], close: [Character]) =
        ([Array("//")], Array("/*"), Array("*/"))

    static let swift: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .swift)
        g.lineComments = cStyleComments.line
        g.blockCommentOpen = cStyleComments.open
        g.blockCommentClose = cStyleComments.close
        g.nestedBlockComments = true
        g.strings = [
            StringRule(open: Array("\"\"\""), close: Array("\"\"\""), multiline: true),
            StringRule(open: ["\""], close: ["\""]),
        ]
        g.keywords = [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "convenience", "default", "defer", "deinit", "didSet", "do",
            "else", "enum", "extension", "fallthrough", "fileprivate", "final", "for", "func",
            "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy",
            "let", "mutating", "nonisolated", "nonmutating", "open", "operator", "override",
            "precedencegroup", "private", "protocol", "public", "repeat", "required", "rethrows",
            "return", "self", "some", "static", "struct", "subscript", "super", "switch", "throw",
            "throws", "try", "typealias", "unowned", "var", "weak", "where", "while", "willSet",
        ]
        g.literals = ["true", "false", "nil"]
        g.keywordsCanBeLabels = true
        g.capitalizedAreTypes = true
        g.atWords = .attribute
        g.hashWords = .anywhere
        return g
    }()

    private static let javaScriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "finally", "for", "function",
        "if", "import", "in", "instanceof", "let", "new", "return", "static", "super", "switch",
        "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
    ]

    static let javaScript: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .javaScript)
        g.lineComments = cStyleComments.line
        g.blockCommentOpen = cStyleComments.open
        g.blockCommentClose = cStyleComments.close
        g.strings = [
            StringRule(open: ["`"], close: ["`"], multiline: true),
            StringRule(open: ["\""], close: ["\""]),
            StringRule(open: ["'"], close: ["'"]),
        ]
        g.keywords = javaScriptKeywords
        g.literals = ["true", "false", "null", "undefined", "NaN", "Infinity"]
        g.keywordsCanBeLabels = true
        g.capitalizedAreTypes = true
        g.atWords = .attribute
        g.identifierStart = ["_", "$"]
        g.identifierContinue = ["_", "$"]
        return g
    }()

    static let typeScript: SyntaxGrammar = {
        var g = javaScript
        g.language = .typeScript
        g.keywords.formUnion([
            "abstract", "as", "declare", "enum", "implements", "infer", "interface", "is", "keyof",
            "module", "namespace", "override", "private", "protected", "public", "readonly",
            "satisfies", "type", "unique",
        ])
        g.types = ["any", "bigint", "boolean", "never", "number", "object", "string", "symbol",
                   "unknown"]
        return g
    }()

    static let python: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .python)
        g.lineComments = [["#"]]
        g.strings = [
            StringRule(open: Array("\"\"\""), close: Array("\"\"\""), multiline: true),
            StringRule(open: Array("'''"), close: Array("'''"), multiline: true),
            StringRule(open: ["\""], close: ["\""]),
            StringRule(open: ["'"], close: ["'"]),
        ]
        g.keywords = [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
            "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
            "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
            "with", "yield",
        ]
        g.types = ["bool", "bytearray", "bytes", "complex", "dict", "float", "frozenset", "int",
                   "list", "object", "set", "str", "tuple"]
        g.literals = ["True", "False", "None"]
        g.capitalizedAreTypes = true
        g.atWords = .attribute
        return g
    }()

    static let json: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .json)
        // JSONC comments are harmless in plain JSON, where they never appear.
        g.lineComments = cStyleComments.line
        g.blockCommentOpen = cStyleComments.open
        g.blockCommentClose = cStyleComments.close
        g.strings = [StringRule(open: ["\""], close: ["\""])]
        g.literals = ["true", "false", "null"]
        g.stringKeys = true
        return g
    }()

    static let yaml: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .yaml)
        g.lineComments = [["#"]]
        g.commentNeedsWordStart = true
        g.strings = [
            StringRule(open: ["\""], close: ["\""]),
            // '' inside a single-quoted scalar closes and reopens, which lexes the same.
            StringRule(open: ["'"], close: ["'"], escape: nil),
        ]
        g.literals = ["true", "false", "null"]
        g.caseInsensitiveLiterals = true
        g.identifierContinue = ["_", "-"]
        return g
    }()

    static let shell: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .shell)
        g.lineComments = [["#"]]
        g.commentNeedsWordStart = true
        g.strings = [
            StringRule(open: ["\""], close: ["\""], multiline: true),
            StringRule(open: ["'"], close: ["'"], escape: nil, multiline: true),
        ]
        g.keywords = [
            "alias", "break", "case", "continue", "declare", "do", "done", "elif", "else", "esac",
            "eval", "exec", "exit", "export", "fi", "for", "function", "if", "in", "local",
            "readonly", "return", "select", "set", "shift", "source", "then", "trap", "unset",
            "until", "while",
        ]
        g.shellVariables = true
        // Flags, paths, and file names (`--done`, `bin/if.sh`) are one word, never keywords.
        g.identifierContinue = ["_", "-", ".", "/"]
        return g
    }()

    static let cFamily: SyntaxGrammar = {
        var g = SyntaxGrammar(language: .cFamily)
        g.lineComments = cStyleComments.line
        g.blockCommentOpen = cStyleComments.open
        g.blockCommentClose = cStyleComments.close
        g.strings = [
            StringRule(open: ["\""], close: ["\""]),
            StringRule(open: ["'"], close: ["'"]),
        ]
        g.keywords = [
            // C
            "auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
            "extern", "for", "goto", "if", "inline", "register", "restrict", "return", "sizeof",
            "static", "struct", "switch", "typedef", "union", "volatile", "while",
            // C++
            "alignas", "alignof", "catch", "class", "co_await", "co_return", "co_yield",
            "consteval", "constexpr", "constinit", "const_cast", "decltype", "delete",
            "dynamic_cast", "explicit", "export", "friend", "mutable", "namespace", "new",
            "noexcept", "operator", "private", "protected", "public", "reinterpret_cast",
            "static_assert", "static_cast", "template", "this", "thread_local", "throw", "try",
            "typeid", "typename", "using", "virtual",
            // Objective-C
            "self", "super",
        ]
        g.types = [
            "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned",
            "bool", "_Bool", "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t",
            "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t",
            "uint64_t", "wchar_t", "char8_t", "char16_t", "char32_t",
            "id", "instancetype", "BOOL", "SEL", "Class", "IMP",
        ]
        g.literals = ["true", "false", "NULL", "nullptr", "nil", "Nil", "YES", "NO"]
        g.capitalizedAreTypes = true
        g.atWords = .keyword   // @interface, @property, @end
        g.hashWords = .lineStart
        return g
    }()
}
