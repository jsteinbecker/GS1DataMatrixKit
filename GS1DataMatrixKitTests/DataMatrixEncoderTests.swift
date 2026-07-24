import XCTest
@testable import GS1DataMatrixKit

/// Golden values in this file were cross-checked against an independent
/// ECC200 implementation (ppf.datamatrix) across all 30 symbol sizes.
final class DataMatrixEncoderTests: XCTestCase {

    // MARK: - Symbol attribute table

    func testSymbolTableIsSelfConsistent() {
        XCTAssertEqual(SymbolAttributes.squares.count, 24)
        XCTAssertEqual(SymbolAttributes.rectangles.count, 6)

        for attributes in SymbolAttributes.all {
            // Region geometry must reproduce the overall symbol size.
            XCTAssertEqual(attributes.rows,
                           attributes.regionsDown * (attributes.regionRows + 2),
                           "row count mismatch for \(attributes.name)")
            XCTAssertEqual(attributes.columns,
                           attributes.regionsAcross * (attributes.regionColumns + 2),
                           "column count mismatch for \(attributes.name)")

            // The mapping matrix must hold exactly the declared codewords,
            // give or take the 4 modules of the fixed corner pattern.
            let bits = attributes.mappingRows * attributes.mappingColumns
            let codewordBits = attributes.totalCodewords * 8
            XCTAssertTrue(bits == codewordBits || bits == codewordBits + 4,
                          "\(attributes.name): \(bits) module bits vs \(codewordBits) codeword bits")
        }
    }

    func testBlockSplitMatchesISOForTheLargestSymbol() {
        let largest = SymbolAttributes.named("144x144")!
        XCTAssertEqual(largest.blocks, 10)
        // ISO/IEC 16022 Table 7: eight blocks of 156 and two of 155.
        let sizes = (0..<largest.blocks).map { largest.dataCodewords(inBlock: $0) }
        XCTAssertEqual(sizes, [156, 156, 156, 156, 156, 156, 156, 156, 155, 155])
        XCTAssertEqual(sizes.reduce(0, +), largest.dataCodewords)
    }

    func testSmallestSymbolSelection() {
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 3, shape: .square)?.name, "10x10")
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 4, shape: .square)?.name, "12x12")
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 30, shape: .square)?.name, "22x22")
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 31, shape: .square)?.name, "24x24")
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 5, shape: .rectangle)?.name, "8x18")
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 49, shape: .rectangle)?.name, "16x48")
        XCTAssertNil(SymbolAttributes.smallest(fitting: 50, shape: .rectangle))
        XCTAssertNil(SymbolAttributes.smallest(fitting: 1559, shape: .square))
        XCTAssertEqual(SymbolAttributes.smallest(fitting: 3, shape: .square,
                                                 minimumRows: 20, minimumColumns: 20)?.name, "20x20")
    }

    // MARK: - Encodation

    func testASCIIDigitPairs() {
        let tokens: [EncodationToken] = "123456".utf8.map { .byte($0) }
        // 12 -> 130+12, 34 -> 130+34, 56 -> 130+56
        XCTAssertEqual(ASCIIEncodation.encode(tokens), [142, 164, 186])
    }

    func testASCIIOddDigitAndLetters() {
        let tokens: [EncodationToken] = "12345A".utf8.map { .byte($0) }
        // 12, 34, then '5' and 'A' as single ASCII values +1
        XCTAssertEqual(ASCIIEncodation.encode(tokens), [142, 164, 54, 66])
    }

    func testFNC1AndExtendedASCII() {
        let tokens: [EncodationToken] = [.fnc1, .byte(0x41), .byte(0xE9)]
        XCTAssertEqual(ASCIIEncodation.encode(tokens), [232, 66, 235, 106])
    }

    func testPaddingUsesThe253StateRandomiser() {
        // The first pad is always 129; later pads are randomised from their
        // 1-based position in the symbol.
        XCTAssertEqual(ASCIIEncodation.pad([1, 2, 3], to: 9),
                       [1, 2, 3, 129, 115, 11, 161, 56, 206])

        // Pads at positions 25...30. Position 28 randomises to exactly 254,
        // which must stay 254 rather than wrapping to zero.
        let long = ASCIIEncodation.pad([Int](repeating: 1, count: 24), to: 30)
        XCTAssertEqual(Array(long.suffix(6)), [129, 209, 104, 254, 150, 45])
    }

    func testPaddingIsNotAppliedWhenTheSymbolIsFull() {
        XCTAssertEqual(ASCIIEncodation.pad([1, 2, 3], to: 3), [1, 2, 3])
    }

    // MARK: - Reed-Solomon

    func testGeneratorPolynomialDegreeAndLeadingCoefficient() {
        for count in ReedSolomon.usedLengths {
            let g = ReedSolomon.generatorPolynomial(count)
            XCTAssertEqual(g.count, count + 1)
            XCTAssertEqual(g[0], 1)
        }
    }

    func testGeneratorRootsAreAlphaPowers() {
        // g(alpha^i) must be zero for i = 1 ... n.
        let count = 10
        let g = ReedSolomon.generatorPolynomial(count)
        for i in 1...count {
            var accumulator = 0
            let root = GF256.alpha(i)
            for coefficient in g {
                accumulator = GF256.multiply(accumulator, root) ^ coefficient
            }
            XCTAssertEqual(accumulator, 0, "alpha^\(i) is not a root")
        }
    }

    func testErrorCorrectionForKnownBlock() {
        // Data codewords of "(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER".
        let data = [232, 131, 130, 160, 130, 135, 142, 169, 226, 147,
                    156, 133, 161, 140, 70, 89, 66, 78, 81, 77,
                    70, 77, 80, 85, 79, 86, 78, 67, 70, 83]
        let expected = [246, 250, 143, 232, 193, 51, 123, 57, 233, 208,
                        178, 64, 209, 146, 1, 232, 147, 104, 178, 49]
        XCTAssertEqual(ReedSolomon.errorCorrection(for: data, count: 20), expected)
    }

    func testSyndromesOfAValidBlockAreZero() {
        let data = Array(1...40)
        let ecc = ReedSolomon.errorCorrection(for: data, count: 24)
        XCTAssertTrue(ReedSolomon.syndromes(of: data + ecc, count: 24).allSatisfy { $0 == 0 })

        var corrupted = data
        corrupted[7] ^= 0x5A
        XCTAssertFalse(ReedSolomon.syndromes(of: corrupted + ecc, count: 24).allSatisfy { $0 == 0 })
    }

    // MARK: - Placement

    func testPlacementIsABijectionForEverySymbolSize() {
        for attributes in SymbolAttributes.all {
            let map = Placement.map(rows: attributes.mappingRows,
                                    columns: attributes.mappingColumns)
            var seen = Set<Int>()
            var forced = 0

            for cell in map.cells {
                switch cell {
                case .bit(let codeword, let bit):
                    XCTAssertTrue(codeword < attributes.totalCodewords,
                                  "\(attributes.name): codeword index \(codeword) out of range")
                    XCTAssertTrue((0...7).contains(bit))
                    XCTAssertTrue(seen.insert(codeword * 8 + bit).inserted,
                                  "\(attributes.name): bit \(bit) of codeword \(codeword) placed twice")
                case .forcedDark, .forcedLight:
                    forced += 1
                }
            }

            XCTAssertEqual(seen.count, attributes.totalCodewords * 8,
                           "\(attributes.name): not every codeword bit was placed")
            XCTAssertTrue(forced == 0 || forced == 4,
                          "\(attributes.name): unexpected fixed corner size \(forced)")
        }
    }

    // MARK: - Whole symbols

    func testFinderPatternOfTheSmallestSymbol() throws {
        let symbol = try DataMatrixEncoder.encode(tokens: "123456".utf8.map { .byte($0) })
        XCTAssertEqual(symbol.attributes.name, "10x10")

        for row in 0..<10 {
            XCTAssertTrue(symbol.matrix[row, 0], "left finder must be solid")
            XCTAssertTrue(symbol.matrix[9, row], "bottom finder must be solid")
            XCTAssertEqual(symbol.matrix[0, row], row % 2 == 0, "top clock track")
            XCTAssertEqual(symbol.matrix[row, 9], (9 - row) % 2 == 0, "right clock track")
        }
    }

    func testEveryCodewordCountRoundTripsThroughTheSelfCheck() throws {
        // The encoder's verify step reads the symbol back and checks the
        // Reed-Solomon syndromes, so this exercises placement for all sizes.
        for attributes in SymbolAttributes.all {
            let digits = String(repeating: "42", count: attributes.dataCodewords - 1)
            let tokens: [EncodationToken] = [.fnc1] + digits.utf8.map { .byte($0) }
            let symbol = try DataMatrixEncoder.encode(tokens: tokens,
                                                      shape: .any,
                                                      fixedSize: attributes.name,
                                                      verify: true)
            XCTAssertEqual(symbol.attributes.name, attributes.name)
            XCTAssertEqual(symbol.matrix.rows, attributes.rows)
            XCTAssertEqual(symbol.matrix.columns, attributes.columns)
        }
    }

    func testPayloadTooLargeIsRejected() {
        let tokens: [EncodationToken] = String(repeating: "A", count: 1600).utf8.map { .byte($0) }
        XCTAssertThrowsError(try DataMatrixEncoder.encode(tokens: tokens, shape: .square)) { error in
            guard case DataMatrixError.dataTooLarge = error else {
                return XCTFail("expected dataTooLarge, got \(error)")
            }
        }
    }

    func testFixedSizeTooSmallIsRejected() {
        let tokens: [EncodationToken] = "1234567890".utf8.map { .byte($0) }
        XCTAssertThrowsError(try DataMatrixEncoder.encode(tokens: tokens, fixedSize: "10x10"))
        XCTAssertThrowsError(try DataMatrixEncoder.encode(tokens: tokens, fixedSize: "11x11")) { error in
            guard case DataMatrixError.unknownSymbolSize = error else {
                return XCTFail("expected unknownSymbolSize, got \(error)")
            }
        }
    }

    // MARK: - SVG

    func testSVGGeometry() throws {
        let symbol = try DataMatrixEncoder.encode(tokens: "123456".utf8.map { .byte($0) })
        let svg = symbol.svg(options: SVGOptions(quietZone: 1, sizing: .moduleSize(4, unit: "px")))

        XCTAssertTrue(svg.hasPrefix("<?xml"))
        XCTAssertTrue(svg.contains("viewBox=\"0 0 12 12\""))   // 10 modules + 2 quiet
        XCTAssertTrue(svg.contains("width=\"48px\""))          // 12 * 4
        XCTAssertTrue(svg.contains("shape-rendering=\"crispEdges\""))
        XCTAssertTrue(svg.contains("<path"))
        XCTAssertTrue(svg.hasSuffix("</svg>\n"))
    }

    func testSVGRunsCoverExactlyTheDarkModules() throws {
        let symbol = try DataMatrixEncoder.encode(tokens: "GS1TESTPAYLOAD1234".utf8.map { .byte($0) })
        let path = SVGRenderer.pathData(symbol.matrix, quietZone: 1)

        // Each run contributes "h<n>" once; the run lengths must sum to the
        // number of dark modules.
        var total = 0
        for piece in path.split(separator: "M") where !piece.isEmpty {
            guard let hIndex = piece.firstIndex(of: "h") else { continue }
            let rest = piece[piece.index(after: hIndex)...]
            let digits = rest.prefix { $0.isNumber }
            total += Int(digits) ?? 0
        }
        XCTAssertEqual(total, symbol.matrix.darkCount)
    }

    func testResponsiveSVGOmitsSize() throws {
        let symbol = try DataMatrixEncoder.encode(tokens: "123456".utf8.map { .byte($0) })
        let svg = symbol.svg(options: SVGOptions(sizing: .responsive,
                                                 background: nil,
                                                 includeXMLDeclaration: false))
        XCTAssertFalse(svg.contains("width="))
        XCTAssertFalse(svg.contains("<rect"))
        XCTAssertTrue(svg.hasPrefix("<svg"))
    }
}
