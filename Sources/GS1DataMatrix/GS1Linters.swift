//
//  GS1Linters.swift
//  Content validation routines referenced by the GS1 Barcode Syntax
//  Dictionary. Each linter checks one component of an AI's data field.
//

/// Why a linter rejected a component value.
public struct GS1LinterFailure: Equatable, Sendable {
    public let linter: String
    public let reason: String
}

public enum GS1Linters {

    /// Signature of a linter: return `nil` when the value is acceptable,
    /// otherwise a human readable reason.
    public typealias Linter = @Sendable (String) -> String?

    /// Linters defined by GS1 that this package does not implement, because
    /// they need data that is not part of the syntax dictionary (the GS1
    /// Company Prefix list, package and media type code lists, coupon
    /// structures). They are treated as no-ops. Supply your own through
    /// `GS1ValidationOptions.additionalLinters` if you need them.
    public static let unimplemented: Set<String> = [
        "gcppos1", "gcppos2", "packagetype", "couponcode", "couponposoffer",
    ]

    // MARK: - Small helpers

    @inline(__always)
    static func isDigits(_ text: some StringProtocol) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0 >= "0" && $0 <= "9" }
    }

    @inline(__always)
    static func integer(_ text: some StringProtocol) -> Int? {
        isDigits(text) ? Int(text) : nil
    }

    // MARK: - Built-in linters

    /// All implemented linters. Split into small groups so the type checker
    /// never sees one enormous dictionary literal of closures.
    static let builtin: [String: Linter] = {
        var table: [String: Linter] = [:]
        for group in [checkLinters, dateLinters, codeLinters, structureLinters] {
            table.merge(group) { current, _ in current }
        }
        return table
    }()

    static let checkLinters: [String: Linter] = [

        "csum": { value in
            if GS1CheckDigit.isValidMod10(value) { return nil }
            let payload = String(value.dropLast())
            if let expected = GS1CheckDigit.mod10(forPayload: payload) {
                return "check digit is \(value.suffix(1)) but should be \(expected)"
            }
            return "check digit cannot be computed"
        },

        "csumalpha": { value in
            if GS1CheckDigit.isValidCheckCharacterPair(value) { return nil }
            let payload = String(value.dropLast(2))
            if let expected = GS1CheckDigit.checkCharacterPair(forPayload: payload) {
                return "check character pair is \(value.suffix(2)) but should be \(expected)"
            }
            return "check character pair cannot be computed"
        },

        "iban": { value in validateIBAN(value) },
    ]

    static let dateLinters: [String: Linter] = [

        "yymmd0": { validateDate($0, allowZeroDay: true) },
        "yymmdd": { validateDate($0, allowZeroDay: false) },

        "yyyymmdd": { value in
            guard value.count == 8, isDigits(value), let year = integer(value.prefix(4)) else {
                return "not an 8 digit date"
            }
            return validateMonthDay(String(value.suffix(4)), year: year, allowZeroDay: false)
        },

        "hhmi": { value in
            guard value.count == 4,
                  let hour = integer(value.prefix(2)),
                  let minute = integer(value.suffix(2)) else { return "not a 4 digit time" }
            if hour > 23 { return "hour \(hour) is out of range" }
            if minute > 59 { return "minute \(minute) is out of range" }
            return nil
        },

        "hh": { value in
            guard value.count == 2, let hour = integer(value) else { return "not a 2 digit hour" }
            return hour <= 23 ? nil : "hour \(hour) is out of range"
        },

        "mi": { value in
            guard value.count == 2, let minute = integer(value) else { return "not a 2 digit minute" }
            return minute <= 59 ? nil : "minute \(minute) is out of range"
        },

        "ss": { value in
            guard value.count == 2, let second = integer(value) else { return "not a 2 digit second" }
            return second <= 59 ? nil : "second \(second) is out of range"
        },
    ]

    static let codeLinters: [String: Linter] = [

        "iso3166": { value in
            guard value.count == 3, let code = integer(value) else { return "not a 3 digit country code" }
            return code > 0 ? nil : "000 is not a country code"
        },

        "iso3166999": { value in
            guard value.count == 3, let code = integer(value) else { return "not a 3 digit country code" }
            return code > 0 ? nil : "000 is not a country code"
        },

        "iso3166alpha2": { value in
            let ok = value.count == 2 && value.allSatisfy { $0.isASCII && $0 >= "A" && $0 <= "Z" }
            return ok ? nil : "not a 2 letter uppercase country code"
        },

        "iso4217": { value in
            guard value.count == 3, let code = integer(value) else { return "not a 3 digit currency code" }
            return code > 0 ? nil : "000 is not a currency code"
        },

        "iso5218": { value in
            ["0", "1", "2", "9"].contains(value) ? nil : "biological sex must be 0, 1, 2 or 9"
        },

        "mediatype": { value in
            guard value.count == 2, let code = integer(value) else { return "not a 2 digit media type" }
            return code > 0 ? nil : "00 is not a media type"
        },

        "importeridx": { value in
            let allowed = "-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
            guard value.count == 1, let character = value.first, allowed.contains(character) else {
                return "not a valid importer index character"
            }
            return nil
        },
    ]

    static let structureLinters: [String: Linter] = [

        "yesno": { value in
            value == "0" || value == "1" ? nil : "must be 0 (no) or 1 (yes)"
        },

        "zero": { value in
            value.allSatisfy { $0 == "0" } ? nil : "must be zero"
        },

        "nonzero": { value in
            value.contains(where: { $0 != "0" }) ? nil : "must not be zero"
        },

        "nozeroprefix": { value in
            value.first == "0" ? "must not have a leading zero" : nil
        },

        "hasnondigit": { value in
            value.contains(where: { !($0.isASCII && $0 >= "0" && $0 <= "9") })
                ? nil
                : "must not consist only of digits"
        },

        "hyphen": { value in
            value == "-" ? nil : "must be a hyphen"
        },

        "winding": { value in
            ["0", "1", "9"].contains(value) ? nil : "winding direction must be 0, 1 or 9"
        },

        "latitude": { value in
            guard value.count == 10, let raw = integer(value) else { return "not a 10 digit latitude" }
            return raw <= 1_800_000_000 ? nil : "latitude is out of range"
        },

        "longitude": { value in
            guard value.count == 10, let raw = integer(value) else { return "not a 10 digit longitude" }
            return raw <= 3_600_000_000 ? nil : "longitude is out of range"
        },

        "pieceoftotal": { value in
            guard value.count == 4,
                  let piece = integer(value.prefix(2)),
                  let total = integer(value.suffix(2)) else { return "not 4 digits" }
            if piece == 0 { return "piece number must not be zero" }
            if total == 0 { return "total piece count must not be zero" }
            if piece > total { return "piece \(piece) exceeds total \(total)" }
            return nil
        },

        "posinseqslash": { value in
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let position = integer(parts[0]),
                  let total = integer(parts[1]) else { return "must be of the form position/total" }
            if position == 0 || total == 0 { return "position and total must not be zero" }
            if position > total { return "position \(position) exceeds total \(total)" }
            return nil
        },

        "pcenc": { value in
            let characters = Array(value)
            var index = 0
            while index < characters.count {
                if characters[index] == "%" {
                    guard index + 2 < characters.count,
                          characters[index + 1].isHexDigit,
                          characters[index + 2].isHexDigit else {
                        return "invalid percent encoding"
                    }
                    index += 3
                } else {
                    index += 1
                }
            }
            return nil
        },
    ]

    /// Runs every linter attached to a component, stopping at the first failure.
    static func run(_ linters: [String],
                    on value: String,
                    additional: [String: Linter]) -> GS1LinterFailure? {
        for name in linters {
            guard let linter = additional[name] ?? builtin[name] else { continue }
            if let reason = linter(value) {
                return GS1LinterFailure(linter: name, reason: reason)
            }
        }
        return nil
    }

    // MARK: - Date helpers

    /// YYMMDD. The century is not knowable from the data alone, so February is
    /// allowed 29 days; every other month is checked exactly.
    static func validateDate(_ value: String, allowZeroDay: Bool) -> String? {
        guard value.count == 6, isDigits(value) else { return "not a 6 digit date" }
        return validateMonthDay(String(value.dropFirst(2)), year: nil, allowZeroDay: allowZeroDay)
    }

    /// `value` is MMDD. Pass `year` when the century is known.
    static func validateMonthDay(_ value: String, year: Int?, allowZeroDay: Bool) -> String? {
        guard value.count == 4,
              let month = integer(value.prefix(2)),
              let day = integer(value.suffix(2)) else { return "not a valid MMDD" }
        guard (1...12).contains(month) else { return "month \(month) is out of range" }

        if day == 0 {
            return allowZeroDay ? nil : "day 00 is not allowed for this AI"
        }
        let lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var maximum = lengths[month - 1]
        if month == 2, let year {
            let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            maximum = leap ? 29 : 28
        }
        guard day <= maximum else { return "day \(day) is out of range for month \(month)" }
        return nil
    }

    /// ISO 13616 IBAN: rotate the first four characters to the end, map letters
    /// to two-digit numbers, then the value modulo 97 must be 1.
    static func validateIBAN(_ value: String) -> String? {
        let characters = Array(value)
        guard characters.count >= 5 else { return "IBAN is too short" }
        guard characters[0].isLetter, characters[1].isLetter,
              characters[2].isASCII, characters[2] >= "0", characters[2] <= "9",
              characters[3].isASCII, characters[3] >= "0", characters[3] <= "9" else {
            return "IBAN must start with two letters and two check digits"
        }

        let rearranged = Array(characters[4...]) + Array(characters[0..<4])
        var remainder = 0
        for character in rearranged {
            if character.isASCII, character >= "0", character <= "9" {
                remainder = (remainder * 10 + (character.wholeNumberValue ?? 0)) % 97
            } else if character.isASCII, character >= "A", character <= "Z",
                      let ascii = character.asciiValue {
                remainder = (remainder * 100 + (Int(ascii) - 55)) % 97
            } else {
                return "IBAN contains an invalid character"
            }
        }
        return remainder == 1 ? nil : "IBAN check digits are incorrect"
    }
}
