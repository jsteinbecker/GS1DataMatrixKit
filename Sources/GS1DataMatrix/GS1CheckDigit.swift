//
//  GS1CheckDigit.swift
//  Standard check digit / check character algorithms of the GS1 General
//  Specifications (section 7.9).
//

public enum GS1CheckDigit {

    // MARK: - Modulo 10 check digit (GTIN, SSCC, GLN, GSIN, GSRN, GRAI, ...)

    /// Computes the modulo-10 check digit for a string of digits that does
    /// *not* yet include the check digit.
    ///
    /// Weights alternate 3, 1 starting from the rightmost data digit.
    public static func mod10(forPayload digits: String) -> Int? {
        var sum = 0
        var weight = 3
        for character in digits.reversed() {
            guard let value = character.wholeNumberValue, character.isASCII, value >= 0, value <= 9 else {
                return nil
            }
            sum += value * weight
            weight = (weight == 3) ? 1 : 3
        }
        return (10 - (sum % 10)) % 10
    }

    /// Validates a numeric string whose **last** digit is the check digit.
    public static func isValidMod10(_ digitsIncludingCheck: String) -> Bool {
        guard digitsIncludingCheck.count >= 2 else { return false }
        let payload = String(digitsIncludingCheck.dropLast())
        guard let expected = mod10(forPayload: payload),
              let actual = digitsIncludingCheck.last?.wholeNumberValue else { return false }
        return expected == actual
    }

    /// Appends the correct modulo-10 check digit, e.g. turns a 13-digit
    /// company/item number into a full GTIN-14.
    public static func appendingMod10(_ payload: String) -> String? {
        guard let check = mod10(forPayload: payload) else { return nil }
        return payload + String(check)
    }

    // MARK: - Modulo 1021 check character pair (GMN, AI 8013)

    /// Prime weighting factors, applied right to left across the data
    /// characters. Long enough for the 25-character GMN maximum.
    static let primes: [Int] = [
        2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53,
        59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113,
    ]

    /// Computes the two check characters for a GMN data part (the key without
    /// its check character pair).
    public static func checkCharacterPair(forPayload payload: String) -> String? {
        guard !payload.isEmpty, payload.count <= primes.count else { return nil }

        let characters = Array(payload)
        var sum = 0
        // The rightmost data character takes the smallest prime.
        for (offset, character) in characters.enumerated() {
            guard let value = cset82Value(character) else { return nil }
            let weight = primes[characters.count - 1 - offset]
            sum += value * weight
        }
        let residue = sum % 1021
        let first = GS1CheckCharacterSet.characters[residue / 32]
        let second = GS1CheckCharacterSet.characters[residue % 32]
        return String([first, second])
    }

    /// Validates a key whose last two characters are the check character pair.
    public static func isValidCheckCharacterPair(_ keyIncludingPair: String) -> Bool {
        guard keyIncludingPair.count >= 3 else { return false }
        let payload = String(keyIncludingPair.dropLast(2))
        let pair = String(keyIncludingPair.suffix(2))
        guard let expected = checkCharacterPair(forPayload: payload) else { return false }
        return expected == pair
    }

    /// Position of `character` in the 82-character set, which doubles as its
    /// numeric value for the check character pair algorithm.
    static func cset82Value(_ character: Character) -> Int? {
        cset82Index[character]
    }

    private static let cset82Index: [Character: Int] = {
        var table: [Character: Int] = [:]
        for (index, character) in GS1CharacterSet.cset82.characters.enumerated() {
            table[character] = index
        }
        return table
    }()
}
