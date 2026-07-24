//
//  GS1ApplicationIdentifier.swift
//  Model for one AI definition, plus a parser for the GS1 Barcode Syntax
//  Dictionary line format.
//
//  Line format (see GS1SyntaxDictionaryData.swift for the embedded table):
//
//      AIs  [Flags]  Specification  [Attributes...]  [# Title]
//
//      Flags:          "*" pre-defined length (no FNC1 separator required)
//                      "?" permitted as a Digital Link data attribute
//      Specification:  whitespace separated components, e.g.
//                      "N13,csum,gcppos1 [X..17]"
//      Attributes:     req=..., ex=..., dlpkey[=...]
//

/// One component of an AI's data field.
public struct GS1AIComponent: Sendable, Equatable {

    public let characterSet: GS1CharacterSet
    public let minimumLength: Int
    public let maximumLength: Int
    /// Components in square brackets may be omitted.
    public let isOptional: Bool
    /// Names of the GS1 "linter" content checks attached to this component.
    public let linters: [String]

    public init(characterSet: GS1CharacterSet,
                minimumLength: Int,
                maximumLength: Int,
                isOptional: Bool = false,
                linters: [String] = []) {
        self.characterSet = characterSet
        self.minimumLength = minimumLength
        self.maximumLength = maximumLength
        self.isOptional = isOptional
        self.linters = linters
    }

    public var isFixedLength: Bool { minimumLength == maximumLength }

    public var formatSpecification: String {
        let body = isFixedLength
            ? "\(characterSet.formatSymbol)\(maximumLength)"
            : "\(characterSet.formatSymbol)..\(maximumLength)"
        return isOptional ? "[\(body)]" : body
    }
}

/// A complete Application Identifier definition.
public struct GS1ApplicationIdentifier: Sendable, Equatable {

    /// The AI itself, e.g. `"01"`, `"3103"`, `"8013"`.
    public let ai: String
    /// Short GS1 data title, e.g. `"NET WEIGHT (kg)"`.
    public let title: String
    public let components: [GS1AIComponent]
    /// `true` when the element string has a pre-defined length, meaning no
    /// FNC1 separator is needed after it.
    public let predefinedLength: Bool
    /// `true` when the AI may appear as a GS1 Digital Link data attribute.
    public let digitalLinkAttribute: Bool
    /// Mandatory associations. Satisfied when *every* AI of at least one inner
    /// group is present. Entries may be patterns where `n` matches any digit.
    public let requires: [[String]]
    /// Invalid pairings. Entries may be patterns where `n` matches any digit.
    public let excludes: [String]
    /// Digital Link primary key qualifier list, when present.
    public let digitalLinkKeyQualifiers: [String]?

    public init(ai: String,
                title: String,
                components: [GS1AIComponent],
                predefinedLength: Bool,
                digitalLinkAttribute: Bool = false,
                requires: [[String]] = [],
                excludes: [String] = [],
                digitalLinkKeyQualifiers: [String]? = nil) {
        self.ai = ai
        self.title = title
        self.components = components
        self.predefinedLength = predefinedLength
        self.digitalLinkAttribute = digitalLinkAttribute
        self.requires = requires
        self.excludes = excludes
        self.digitalLinkKeyQualifiers = digitalLinkKeyQualifiers
    }

    /// Shortest legal data field.
    public var minimumDataLength: Int {
        components.reduce(0) { $0 + ($1.isOptional ? 0 : $1.minimumLength) }
    }

    /// Longest legal data field.
    public var maximumDataLength: Int {
        components.reduce(0) { $0 + $1.maximumLength }
    }

    /// Total element string length (AI + data) for pre-defined length AIs.
    public var predefinedElementLength: Int? {
        guard predefinedLength else { return nil }
        return ai.count + maximumDataLength
    }

    /// Human readable format, e.g. `"N13,csum [X..17]"`.
    public var formatSpecification: String {
        components.map { $0.formatSpecification }.joined(separator: " ")
    }

    /// Does `candidate` (an AI) match `pattern`, where `n` is a digit wildcard?
    public static func matches(_ candidate: String, pattern: String) -> Bool {
        guard candidate.count == pattern.count else { return false }
        for (c, p) in zip(candidate, pattern) {
            if p == "n" {
                if !c.isNumber { return false }
            } else if c != p {
                return false
            }
        }
        return true
    }
}

// MARK: - Syntax dictionary line parsing

public enum GS1SyntaxDictionaryError: Error, CustomStringConvertible {
    case malformedLine(String, reason: String)

    public var description: String {
        switch self {
        case .malformedLine(let line, let reason):
            return "Malformed GS1 syntax dictionary line (\(reason)): \(line)"
        }
    }
}

extension GS1ApplicationIdentifier {

    /// Characters that may appear in the flags field.
    static let flagCharacters = Set("*!?\"$%&'()+,-./:;<=>@[\\]^_`{|}~")

    /// Parses one line of the GS1 Barcode Syntax Dictionary. A line may define
    /// a range of AIs, so an array is returned.
    public static func parse(dictionaryLine line: String) throws -> [GS1ApplicationIdentifier] {
        // Split off the title.
        var body = line
        var title = ""
        if let hash = line.firstIndex(of: "#") {
            body = String(line[line.startIndex..<hash])
            title = String(line[line.index(after: hash)...]).trimmed()
        }

        let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let aiToken = tokens.first else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "no AI field")
        }

        var index = 1
        var predefined = false
        var digitalLink = false

        // Optional flags field: made up only of flag characters, and never
        // looks like a specification component (which starts N/X/Y/Z/[).
        if index < tokens.count, isFlagsToken(tokens[index]) {
            predefined = tokens[index].contains("*")
            digitalLink = tokens[index].contains("?")
            index += 1
        }

        var componentTokens: [String] = []
        var requires: [[String]] = []
        var excludes: [String] = []
        var qualifiers: [String]? = nil

        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("req=") {
                let list = String(token.dropFirst(4))
                requires = list.split(separator: ",").map { group in
                    group.split(separator: "+").map(String.init)
                }
            } else if token.hasPrefix("ex=") {
                excludes = String(token.dropFirst(3)).split(separator: ",").map(String.init)
            } else if token == "dlpkey" {
                qualifiers = []
            } else if token.hasPrefix("dlpkey=") {
                qualifiers = String(token.dropFirst(7))
                    .split(whereSeparator: { $0 == "," || $0 == "|" })
                    .map(String.init)
            } else {
                componentTokens.append(token)
            }
            index += 1
        }

        guard !componentTokens.isEmpty else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "no specification")
        }
        let components = try componentTokens.map { try parseComponent($0, line: line) }

        return try expand(aiToken, line: line).map { ai in
            GS1ApplicationIdentifier(ai: ai,
                                     title: title,
                                     components: components,
                                     predefinedLength: predefined,
                                     digitalLinkAttribute: digitalLink,
                                     requires: requires,
                                     excludes: excludes,
                                     digitalLinkKeyQualifiers: qualifiers)
        }
    }

    static func isFlagsToken(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { flagCharacters.contains($0) && $0 != "[" && $0 != "," }
    }

    /// "01" -> ["01"];  "3100-3105" -> ["3100", ... , "3105"]
    static func expand(_ token: String, line: String) throws -> [String] {
        guard let dash = token.firstIndex(of: "-") else { return [token] }
        let lower = String(token[token.startIndex..<dash])
        let upper = String(token[token.index(after: dash)...])
        guard lower.count == upper.count,
              let start = Int(lower), let end = Int(upper), start <= end else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "bad AI range")
        }
        return (start...end).map { value in
            var text = String(value)
            while text.count < lower.count { text = "0" + text }
            return text
        }
    }

    /// "N13,csum,gcppos1" / "[X..17]" / "[N3],iso3166"
    static func parseComponent(_ token: String, line: String) throws -> GS1AIComponent {
        let pieces = token.split(separator: ",").map(String.init)
        guard var type = pieces.first else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "empty component")
        }
        let linters = Array(pieces.dropFirst())

        var isOptional = false
        if type.hasPrefix("[") {
            guard type.hasSuffix("]") else {
                throw GS1SyntaxDictionaryError.malformedLine(line, reason: "unclosed optional component")
            }
            isOptional = true
            type = String(type.dropFirst().dropLast())
        }

        guard let symbol = type.first else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "empty component type")
        }
        let characterSet: GS1CharacterSet
        switch symbol {
        case "N": characterSet = .numeric
        case "X": characterSet = .cset82
        case "Y": characterSet = .cset39
        case "Z": characterSet = .cset64
        default:
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "unknown character set '\(symbol)'")
        }

        var lengthText = String(type.dropFirst())
        var variable = false
        if lengthText.hasPrefix("..") {
            variable = true
            lengthText = String(lengthText.dropFirst(2))
        }
        guard let length = Int(lengthText), length > 0 else {
            throw GS1SyntaxDictionaryError.malformedLine(line, reason: "bad component length")
        }

        return GS1AIComponent(characterSet: characterSet,
                              minimumLength: variable ? 1 : length,
                              maximumLength: length,
                              isOptional: isOptional,
                              linters: linters)
    }
}

extension String {
    func trimmed() -> String {
        var characters = Array(self)
        while let first = characters.first, first == " " || first == "\t" || first == "\r" {
            characters.removeFirst()
        }
        while let last = characters.last, last == " " || last == "\t" || last == "\r" {
            characters.removeLast()
        }
        return String(characters)
    }
}
