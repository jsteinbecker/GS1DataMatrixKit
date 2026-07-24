//
//  Encodation.swift
//  ECC200 ASCII encodation (ISO/IEC 16022 clause 5.2.3).
//
//  ASCII is the default encodation scheme and is what GS1 Application
//  Identifier data uses in practice: digit pairs compact two digits into one
//  codeword, which is already optimal for the numeric-heavy element strings
//  that GS1 defines.
//

/// A single unit of data handed to the ECC200 encoder.
public enum EncodationToken: Equatable, Sendable {
    /// The FNC1 non-data character. Codeword 232.
    /// In the first position it flags the symbol as GS1 DataMatrix; elsewhere
    /// it acts as the field separator between variable-length elements.
    case fnc1
    /// One byte of payload.
    case byte(UInt8)
}

enum ASCIIEncodation {

    static let fnc1Codeword = 232
    static let padCodeword = 129
    static let upperShiftCodeword = 235

    @inline(__always)
    private static func isDigit(_ token: EncodationToken) -> Bool {
        if case .byte(let b) = token { return b >= 0x30 && b <= 0x39 }
        return false
    }

    @inline(__always)
    private static func digitValue(_ token: EncodationToken) -> Int {
        if case .byte(let b) = token { return Int(b) - 0x30 }
        return 0
    }

    /// Encodes tokens into ECC200 data codewords using the ASCII scheme.
    static func encode(_ tokens: [EncodationToken]) -> [Int] {
        var codewords: [Int] = []
        codewords.reserveCapacity(tokens.count)

        var i = 0
        while i < tokens.count {
            // Rule: two consecutive digits compact into a single codeword.
            if i + 1 < tokens.count, isDigit(tokens[i]), isDigit(tokens[i + 1]) {
                let value = digitValue(tokens[i]) * 10 + digitValue(tokens[i + 1])
                codewords.append(130 + value)
                i += 2
                continue
            }

            switch tokens[i] {
            case .fnc1:
                codewords.append(fnc1Codeword)
            case .byte(let b):
                if b < 128 {
                    codewords.append(Int(b) + 1)
                } else {
                    // Extended ASCII: upper shift, then the low seven bits.
                    codewords.append(upperShiftCodeword)
                    codewords.append(Int(b) - 128 + 1)
                }
            }
            i += 1
        }
        return codewords
    }

    /// Pads a codeword stream out to the symbol's data capacity.
    ///
    /// The first pad is codeword 129; every later pad is randomised with the
    /// "253-state" algorithm of ISO/IEC 16022 clause 5.2.3 so that padding
    /// cannot create patterns resembling the finder.
    static func pad(_ codewords: [Int], to capacity: Int) -> [Int] {
        guard codewords.count < capacity else { return codewords }
        var result = codewords
        result.append(padCodeword)

        while result.count < capacity {
            // `position` is the 1-based position of the pad codeword.
            let position = result.count + 1
            let pseudoRandom = ((149 * position) % 253) + 1
            let value = padCodeword + pseudoRandom
            result.append(value <= 254 ? value : value - 254)
        }
        return result
    }
}
