//
//  GS1CharacterSets.swift
//  The encodable character sets of the GS1 General Specifications
//  (figures 7.11-1 to 7.11-4).
//

public enum GS1CharacterSet: String, Sendable, Equatable {
    /// Digits only. Written `n` in the GS1 format specification.
    case numeric
    /// The 82-character alphanumeric set. Written `X`.
    case cset82
    /// The 39-character "URI safe" set used by AI 8010. Written `Y`.
    case cset39
    /// The 64-character file-safe / URI-safe base64 set used by AI 8030.
    case cset64

    /// The characters that belong to the set.
    public var characters: String {
        switch self {
        case .numeric:
            return "0123456789"
        case .cset82:
            return "!\"%&'()*+,-./0123456789:;<=>?ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
        case .cset39:
            return "#-/0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        case .cset64:
            return "-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz="
        }
    }

    /// Short symbol used in GS1 format specifications, e.g. `n13`, `X..20`.
    public var formatSymbol: String {
        switch self {
        case .numeric: return "n"
        case .cset82: return "X"
        case .cset39: return "Y"
        case .cset64: return "Z"
        }
    }

    private static let membership: [GS1CharacterSet: Set<Character>] = {
        var table: [GS1CharacterSet: Set<Character>] = [:]
        for set in [GS1CharacterSet.numeric, .cset82, .cset39, .cset64] {
            table[set] = Set(set.characters)
        }
        return table
    }()

    public func contains(_ character: Character) -> Bool {
        GS1CharacterSet.membership[self]?.contains(character) ?? false
    }

    /// Returns the first character of `text` that is not in the set.
    public func firstInvalidCharacter(in text: String) -> Character? {
        text.first { !contains($0) }
    }
}

/// The 32-character set used by the GS1 check character pair (AI 8013 GMN).
/// Excludes 0, 1, I and O to avoid transcription errors.
enum GS1CheckCharacterSet {
    static let characters = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    static func value(of character: Character) -> Int? {
        characters.firstIndex(of: character)
    }
}
