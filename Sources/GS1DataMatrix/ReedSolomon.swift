//
//  ReedSolomon.swift
//  Reed-Solomon error correction over GF(256) as specified for ECC200
//  (ISO/IEC 16022 Annex E).
//
//  Field polynomial: x^8 + x^5 + x^3 + x^2 + 1  (0x12D)
//  Generator polynomial roots: alpha^1 ... alpha^n
//

/// Galois field GF(256) arithmetic used by ECC200.
enum GF256 {

    /// (log, antilog) tables built once for the ECC200 field polynomial.
    static let tables: (log: [Int], alog: [Int]) = {
        var log = [Int](repeating: 0, count: 256)
        var alog = [Int](repeating: 0, count: 255)
        var p = 1
        for i in 0..<255 {
            alog[i] = p
            log[p] = i
            p <<= 1
            if p >= 256 { p ^= 0x12D }
        }
        return (log, alog)
    }()

    @inline(__always)
    static func multiply(_ a: Int, _ b: Int) -> Int {
        if a == 0 || b == 0 { return 0 }
        let t = tables
        return t.alog[(t.log[a] + t.log[b]) % 255]
    }

    @inline(__always)
    static func alpha(_ exponent: Int) -> Int {
        return tables.alog[exponent % 255]
    }
}

enum ReedSolomon {

    /// Every error-codeword count that appears in the ECC200 symbol table.
    static let usedLengths: [Int] = [5, 7, 10, 11, 12, 14, 18, 20, 24, 28, 36, 42, 48, 56, 62, 68]

    /// Immutable, lazily initialised cache of the generator polynomials that
    /// ECC200 actually uses. Being a `let`, it is safe to share across threads.
    private static let generators: [Int: [Int]] = {
        var table: [Int: [Int]] = [:]
        for n in usedLengths {
            table[n] = buildGenerator(n)
        }
        return table
    }()

    /// Builds the generator polynomial of degree `n`:
    ///     g(x) = (x - a^1)(x - a^2) ... (x - a^n)
    /// Coefficients are returned highest power first, so `g[0] == 1`.
    static func buildGenerator(_ n: Int) -> [Int] {
        precondition(n > 0, "generator degree must be positive")
        var g: [Int] = [1]
        for i in 1...n {
            g.append(0)
            let a = GF256.alpha(i)
            var k = g.count - 1
            while k > 0 {
                g[k] = g[k] ^ GF256.multiply(a, g[k - 1])
                k -= 1
            }
        }
        return g
    }

    static func generatorPolynomial(_ n: Int) -> [Int] {
        if let cached = generators[n] { return cached }
        return buildGenerator(n)
    }

    /// Computes `count` error-correction codewords for `data`.
    static func errorCorrection(for data: [Int], count: Int) -> [Int] {
        precondition(count > 0, "error correction codeword count must be positive")
        let g = generatorPolynomial(count)
        var remainder = [Int](repeating: 0, count: count)

        for value in data {
            let factor = value ^ remainder[0]
            if count > 1 {
                for i in 0..<(count - 1) {
                    remainder[i] = remainder[i + 1] ^ GF256.multiply(factor, g[i + 1])
                }
            }
            remainder[count - 1] = GF256.multiply(factor, g[count])
        }
        return remainder
    }

    /// Syndromes of a received block (data followed by its check codewords).
    /// All-zero means the block is self-consistent; used by the encoder's
    /// optional self-check.
    static func syndromes(of block: [Int], count: Int) -> [Int] {
        var result = [Int](repeating: 0, count: count)
        for i in 0..<count {
            var acc = 0
            let a = GF256.alpha(i + 1)
            for value in block {
                acc = GF256.multiply(acc, a) ^ value
            }
            result[i] = acc
        }
        return result
    }
}
