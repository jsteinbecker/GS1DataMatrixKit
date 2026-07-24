//
//  GS1ElementString.swift
//  Parsing and validation of GS1 element strings.
//

/// The FNC1 field separator as it appears in a decoded data stream.
public let gs1GroupSeparator: Character = "\u{1D}"

/// One AI and its data.
public struct GS1Element: Equatable, Sendable {
    public let ai: String
    public let value: String
    public let definition: GS1ApplicationIdentifier

    public init(ai: String, value: String, definition: GS1ApplicationIdentifier) {
        self.ai = ai
        self.value = value
        self.definition = definition
    }

    public var title: String { definition.title }
    /// Human Readable Interpretation, e.g. `"(01)00300005123996"`.
    public var hri: String { "(\(ai))\(value)" }
    /// Whether this element must be terminated by FNC1 when another element
    /// follows it.
    public var requiresSeparator: Bool { !definition.predefinedLength }
}

public struct GS1ValidationOptions: Sendable {

    /// Run the content linters (check digits, dates, code formats).
    public var runLinters: Bool
    /// Enforce `req=` mandatory AI associations.
    public var enforceMandatoryAssociations: Bool
    /// Enforce `ex=` invalid AI pairings.
    public var enforceInvalidPairings: Bool
    /// Reject an element string that uses the same AI twice.
    public var rejectRepeatedAIs: Bool
    /// Accept AIs that are not in the syntax dictionary, treating their data as
    /// variable length CSET 82. Off by default.
    public var allowUnknownAIs: Bool
    /// Treat a separator after a pre-defined length element as an error rather
    /// than a warning.
    public var rejectRedundantSeparators: Bool
    /// Extra or replacement linters, keyed by linter name.
    public var additionalLinters: [String: GS1Linters.Linter]

    public init(runLinters: Bool = true,
                enforceMandatoryAssociations: Bool = true,
                enforceInvalidPairings: Bool = true,
                rejectRepeatedAIs: Bool = true,
                allowUnknownAIs: Bool = false,
                rejectRedundantSeparators: Bool = false,
                additionalLinters: [String: GS1Linters.Linter] = [:]) {
        self.runLinters = runLinters
        self.enforceMandatoryAssociations = enforceMandatoryAssociations
        self.enforceInvalidPairings = enforceInvalidPairings
        self.rejectRepeatedAIs = rejectRepeatedAIs
        self.allowUnknownAIs = allowUnknownAIs
        self.rejectRedundantSeparators = rejectRedundantSeparators
        self.additionalLinters = additionalLinters
    }

    /// Everything on. Use this for label generation.
    public static let strict = GS1ValidationOptions()

    /// Structure only: lengths and character sets, no check digits or AI
    /// association rules. Useful when re-encoding data captured from a scan.
    public static let lenient = GS1ValidationOptions(runLinters: false,
                                                     enforceMandatoryAssociations: false,
                                                     enforceInvalidPairings: false,
                                                     rejectRepeatedAIs: false,
                                                     allowUnknownAIs: true)
}

public enum GS1Error: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case unknownAI(String, position: Int)
    case notAnAI(String, position: Int)
    case unterminatedBracket(position: Int)
    case emptyValue(ai: String)
    case dataTooShort(ai: String, minimum: Int, actual: Int)
    case dataTooLong(ai: String, maximum: Int, actual: Int)
    case invalidCharacter(ai: String, character: Character, characterSet: GS1CharacterSet)
    case contentRejected(ai: String, value: String, failure: GS1LinterFailure)
    case repeatedAI(String)
    case missingMandatoryAssociation(ai: String, requires: [[String]])
    case invalidPairing(ai: String, conflictsWith: String)
    case redundantSeparator(afterAI: String)

    public var description: String {
        switch self {
        case .emptyInput:
            return "The element string is empty."
        case .unknownAI(let ai, let position):
            return "Unknown Application Identifier '\(ai)' at position \(position)."
        case .notAnAI(let text, let position):
            return "Expected an Application Identifier at position \(position), found '\(text)'."
        case .unterminatedBracket(let position):
            return "Unterminated '(' in the bracketed element string at position \(position)."
        case .emptyValue(let ai):
            return "AI (\(ai)) has no data."
        case .dataTooShort(let ai, let minimum, let actual):
            return "AI (\(ai)) needs at least \(minimum) characters, got \(actual). "
                + "If the previous field is variable length, an FNC1 separator may be missing."
        case .dataTooLong(let ai, let maximum, let actual):
            return "AI (\(ai)) accepts at most \(maximum) characters, got \(actual). "
                + "If another AI follows this one, an FNC1 separator may be missing."
        case .invalidCharacter(let ai, let character, let characterSet):
            return "AI (\(ai)) contains '\(character)', which is not in the \(characterSet.formatSymbol) character set."
        case .contentRejected(let ai, let value, let failure):
            return "AI (\(ai)) value '\(value)' failed the \(failure.linter) check: \(failure.reason)."
        case .repeatedAI(let ai):
            return "AI (\(ai)) appears more than once."
        case .missingMandatoryAssociation(let ai, let requires):
            let groups = requires.map { $0.joined(separator: " + ") }.joined(separator: ", or ")
            return "AI (\(ai)) requires \(groups) to also be present."
        case .invalidPairing(let ai, let conflict):
            return "AI (\(ai)) must not be used together with AI (\(conflict))."
        case .redundantSeparator(let ai):
            return "AI (\(ai)) has a pre-defined length, so the FNC1 separator after it is not permitted."
        }
    }
}

/// A parsed, validated GS1 element string.
public struct GS1ElementString: Sendable {

    public let elements: [GS1Element]
    /// Non-fatal observations made while parsing.
    public let warnings: [String]

    public init(elements: [GS1Element], warnings: [String] = []) {
        self.elements = elements
        self.warnings = warnings
    }

    public subscript(ai: String) -> String? {
        elements.first { $0.ai == ai }?.value
    }

    /// `"(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER"`
    public var hri: String {
        elements.map { $0.hri }.joined()
    }

    /// Elements reordered so that pre-defined length AIs come first, which is
    /// the GS1 recommendation: it removes FNC1 separators and usually shrinks
    /// the symbol. The relative order within each group is preserved.
    public var optimizedElements: [GS1Element] {
        elements.filter { !$0.requiresSeparator } + elements.filter { $0.requiresSeparator }
    }

    /// The concatenated data, with `separator` between elements that need one.
    /// Defaults to the ASCII group separator that a scanner reports.
    public func encoded(separator: Character = gs1GroupSeparator,
                        optimizeOrder: Bool = true) -> String {
        let ordered = optimizeOrder ? optimizedElements : elements
        var out = ""
        for (index, element) in ordered.enumerated() {
            out += element.ai + element.value
            let isLast = index == ordered.count - 1
            if element.requiresSeparator && !isLast {
                out.append(separator)
            }
        }
        return out
    }

    /// Encoder input: a leading FNC1 marks the symbol as GS1 DataMatrix, and
    /// FNC1 also acts as the separator after variable-length fields.
    public func encodationTokens(optimizeOrder: Bool = true) -> [EncodationToken] {
        let ordered = optimizeOrder ? optimizedElements : elements
        var tokens: [EncodationToken] = [.fnc1]
        for (index, element) in ordered.enumerated() {
            for scalar in Array((element.ai + element.value).unicodeScalars) {
                tokens.append(.byte(UInt8(scalar.value & 0xFF)))
            }
            let isLast = index == ordered.count - 1
            if element.requiresSeparator && !isLast {
                tokens.append(.fnc1)
            }
        }
        return tokens
    }
}

// MARK: - Parsing

public extension GS1ElementString {

    /// Parses either a raw element string (`"0100300005123996..."`, with or
    /// without FNC1/GS separators, optionally prefixed by the `]d2` symbology
    /// identifier) or the bracketed human readable form
    /// (`"(01)00300005123996(17)260331"`).
    static func parse(_ input: String,
                      options: GS1ValidationOptions = .strict) throws -> GS1ElementString {
        var text = input
        // Strip the symbology identifier a scanner may prepend.
        for prefix in ["]d2", "]C1", "]e0", "]Q3"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        guard !text.isEmpty else { throw GS1Error.emptyInput }

        let raw = text.first == "("
            ? try splitBracketed(text)
            : try splitRaw(text, options: options)

        return try validate(raw.pairs, warnings: raw.warnings, options: options)
    }

    /// Builds an element string from AI/value pairs.
    static func make(_ pairs: [(String, String)],
                     options: GS1ValidationOptions = .strict) throws -> GS1ElementString {
        try validate(pairs.map { (ai: $0.0, value: $0.1) }, warnings: [], options: options)
    }

    // MARK: Splitting

    typealias RawElement = (ai: String, value: String)

    /// `"(01)0034...(10)LOT"` -> [("01", "0034..."), ("10", "LOT")]
    static func splitBracketed(_ text: String) throws -> (pairs: [RawElement], warnings: [String]) {
        var pairs: [RawElement] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            guard characters[index] == "(" else {
                throw GS1Error.notAnAI(String(characters[index]), position: index)
            }
            guard let close = characters[index...].firstIndex(of: ")") else {
                throw GS1Error.unterminatedBracket(position: index)
            }
            let ai = String(characters[(index + 1)..<close])
            var end = close + 1
            while end < characters.count && characters[end] != "(" { end += 1 }
            var value = String(characters[(close + 1)..<end])
            // Tolerate a separator that a decoder left in the data.
            if value.last == gs1GroupSeparator { value.removeLast() }
            pairs.append((ai: ai, value: value))
            index = end
        }
        return (pairs, [])
    }

    /// Splits a concatenated element string, using the syntax dictionary to
    /// know how much data each AI takes.
    static func splitRaw(_ text: String,
                         options: GS1ValidationOptions) throws -> (pairs: [RawElement], warnings: [String]) {
        var pairs: [RawElement] = []
        var warnings: [String] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            if characters[index] == gs1GroupSeparator {
                warnings.append("Ignored an unexpected FNC1 separator at position \(index).")
                index += 1
                continue
            }

            // Find the AI: the GS1 AI set is prefix-free, so the shortest match wins.
            var ai: String? = nil
            for length in 2...4 where index + length <= characters.count {
                let candidate = String(characters[index..<(index + length)])
                if GS1SyntaxDictionary.definition(for: candidate) != nil {
                    ai = candidate
                    break
                }
            }

            guard let ai else {
                let sample = String(characters[index..<min(index + 4, characters.count)])
                if options.allowUnknownAIs, sample.count >= 2, sample.prefix(2).allSatisfy({ $0.isNumber }) {
                    // Unknown AI: assume 2 digits and variable length data.
                    let unknownAI = String(sample.prefix(2))
                    var end = index + 2
                    while end < characters.count && characters[end] != gs1GroupSeparator { end += 1 }
                    pairs.append((ai: unknownAI, value: String(characters[(index + 2)..<end])))
                    warnings.append("AI (\(unknownAI)) is not in the syntax dictionary; data was not validated.")
                    index = end < characters.count ? end + 1 : end
                    continue
                }
                throw GS1Error.unknownAI(sample, position: index)
            }

            let definition = GS1SyntaxDictionary.definition(for: ai)!
            var cursor = index + ai.count

            let value: String
            if definition.predefinedLength {
                let length = definition.maximumDataLength
                guard cursor + length <= characters.count else {
                    throw GS1Error.dataTooShort(ai: ai,
                                                minimum: length,
                                                actual: characters.count - cursor)
                }
                value = String(characters[cursor..<(cursor + length)])
                cursor += length
                if cursor < characters.count && characters[cursor] == gs1GroupSeparator {
                    if options.rejectRedundantSeparators {
                        throw GS1Error.redundantSeparator(afterAI: ai)
                    }
                    warnings.append("AI (\(ai)) has a pre-defined length; the FNC1 separator after it is redundant.")
                    cursor += 1
                }
            } else {
                var end = cursor
                while end < characters.count && characters[end] != gs1GroupSeparator { end += 1 }
                value = String(characters[cursor..<end])
                cursor = end < characters.count ? end + 1 : end
            }

            pairs.append((ai: ai, value: value))
            index = cursor
        }

        guard !pairs.isEmpty else { throw GS1Error.emptyInput }
        return (pairs, warnings)
    }

    // MARK: Validation

    static func validate(_ pairs: [RawElement],
                         warnings: [String],
                         options: GS1ValidationOptions) throws -> GS1ElementString {
        var elements: [GS1Element] = []
        var seen: Set<String> = []
        var allWarnings = warnings

        for pair in pairs {
            guard let definition = GS1SyntaxDictionary.definition(for: pair.ai) else {
                guard options.allowUnknownAIs else {
                    throw GS1Error.unknownAI(pair.ai, position: 0)
                }
                let placeholder = GS1ApplicationIdentifier(
                    ai: pair.ai,
                    title: "UNKNOWN",
                    components: [GS1AIComponent(characterSet: .cset82,
                                                minimumLength: 1,
                                                maximumLength: 90,
                                                isOptional: false,
                                                linters: [])],
                    predefinedLength: false,
                    digitalLinkAttribute: false,
                    requires: [],
                    excludes: [],
                    digitalLinkKeyQualifiers: nil)
                elements.append(GS1Element(ai: pair.ai, value: pair.value, definition: placeholder))
                allWarnings.append("AI (\(pair.ai)) is not in the syntax dictionary; data was not validated.")
                continue
            }

            if options.rejectRepeatedAIs {
                guard seen.insert(pair.ai).inserted else { throw GS1Error.repeatedAI(pair.ai) }
            }

            try validateDataField(pair.value, against: definition, options: options)
            elements.append(GS1Element(ai: pair.ai, value: pair.value, definition: definition))
        }

        guard !elements.isEmpty else { throw GS1Error.emptyInput }

        let present = elements.map { $0.ai }
        for element in elements {
            if options.enforceMandatoryAssociations, !element.definition.requires.isEmpty {
                let satisfied = element.definition.requires.contains { group in
                    group.allSatisfy { pattern in
                        present.contains { candidate in
                            candidate != element.ai
                                && GS1ApplicationIdentifier.matches(candidate, pattern: pattern)
                        }
                    }
                }
                guard satisfied else {
                    throw GS1Error.missingMandatoryAssociation(ai: element.ai,
                                                               requires: element.definition.requires)
                }
            }

            if options.enforceInvalidPairings {
                for pattern in element.definition.excludes {
                    if let conflict = present.first(where: { candidate in
                        candidate != element.ai
                            && GS1ApplicationIdentifier.matches(candidate, pattern: pattern)
                    }) {
                        throw GS1Error.invalidPairing(ai: element.ai, conflictsWith: conflict)
                    }
                }
            }
        }

        return GS1ElementString(elements: elements, warnings: allWarnings)
    }

    /// Consumes the data field component by component, checking length,
    /// character set and content.
    static func validateDataField(_ value: String,
                                  against definition: GS1ApplicationIdentifier,
                                  options: GS1ValidationOptions) throws {
        guard !value.isEmpty else { throw GS1Error.emptyValue(ai: definition.ai) }

        var remaining = Substring(value)
        for component in definition.components {
            if remaining.isEmpty {
                if component.isOptional { break }
                throw GS1Error.dataTooShort(ai: definition.ai,
                                            minimum: definition.minimumDataLength,
                                            actual: value.count)
            }

            let take = component.isFixedLength ? component.maximumLength : remaining.count
            guard remaining.count >= take else {
                throw GS1Error.dataTooShort(ai: definition.ai,
                                            minimum: definition.minimumDataLength,
                                            actual: value.count)
            }
            let chunk = String(remaining.prefix(take))
            guard chunk.count <= component.maximumLength else {
                throw GS1Error.dataTooLong(ai: definition.ai,
                                           maximum: definition.maximumDataLength,
                                           actual: value.count)
            }
            if let bad = component.characterSet.firstInvalidCharacter(in: chunk) {
                throw GS1Error.invalidCharacter(ai: definition.ai,
                                                character: bad,
                                                characterSet: component.characterSet)
            }
            if options.runLinters,
               let failure = GS1Linters.run(component.linters,
                                            on: chunk,
                                            additional: options.additionalLinters) {
                throw GS1Error.contentRejected(ai: definition.ai, value: chunk, failure: failure)
            }
            remaining = remaining.dropFirst(take)
        }

        guard remaining.isEmpty else {
            throw GS1Error.dataTooLong(ai: definition.ai,
                                       maximum: definition.maximumDataLength,
                                       actual: value.count)
        }
    }
}
