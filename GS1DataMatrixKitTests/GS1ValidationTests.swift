import XCTest
@testable import GS1DataMatrixKit

final class GS1ValidationTests: XCTestCase {

    /// GTIN-14 with a correct check digit (the payload 0030000512399 checks to 6).
    let gtin = "00300005123996"
    let example = "0100300005123996" + "17260331" + "10EXAMPLELOTNUMBER"

    // MARK: - Check digits

    func testMod10CheckDigit() {
        XCTAssertEqual(GS1CheckDigit.mod10(forPayload: "0030000512399"), 6)
        XCTAssertEqual(GS1CheckDigit.mod10(forPayload: "10614141123456789"), 7)
        XCTAssertEqual(GS1CheckDigit.mod10(forPayload: "629104150021"), 3)   // GTIN-13
        XCTAssertTrue(GS1CheckDigit.isValidMod10("00300005123996"))
        XCTAssertFalse(GS1CheckDigit.isValidMod10("00300005123997"))
        XCTAssertEqual(GS1CheckDigit.appendingMod10("0030000512399"), "00300005123996")
        XCTAssertNil(GS1CheckDigit.mod10(forPayload: "12345X"))
    }

    /// The worked example from the GS1 General Specifications, section 7.9.5.
    func testCheckCharacterPairForGMN() {
        XCTAssertEqual(GS1CheckDigit.checkCharacterPair(forPayload: "1987654Ad4X4bL5ttr2310c"), "2K")
        XCTAssertTrue(GS1CheckDigit.isValidCheckCharacterPair("1987654Ad4X4bL5ttr2310c2K"))
        XCTAssertFalse(GS1CheckDigit.isValidCheckCharacterPair("1987654Ad4X4bL5ttr2310c2L"))
    }

    // MARK: - Syntax dictionary

    func testEmbeddedDictionaryParses() {
        XCTAssertGreaterThan(GS1SyntaxDictionary.allAIs.count, 200)

        let gtinAI = GS1SyntaxDictionary.definition(for: "01")
        XCTAssertNotNil(gtinAI)
        XCTAssertTrue(gtinAI!.predefinedLength)
        XCTAssertEqual(gtinAI!.components.count, 1)
        XCTAssertEqual(gtinAI!.components[0].characterSet, .numeric)
        XCTAssertEqual(gtinAI!.components[0].maximumLength, 14)
        XCTAssertTrue(gtinAI!.components[0].linters.contains("csum"))
        XCTAssertEqual(gtinAI!.title, "GTIN")

        let lot = GS1SyntaxDictionary.definition(for: "10")!
        XCTAssertFalse(lot.predefinedLength)
        XCTAssertEqual(lot.components[0].minimumLength, 1)
        XCTAssertEqual(lot.components[0].maximumLength, 20)
        XCTAssertEqual(lot.components[0].characterSet, .cset82)
    }

    func testDictionaryRangesExpand() {
        XCTAssertNotNil(GS1SyntaxDictionary.definition(for: "3100"))
        XCTAssertNotNil(GS1SyntaxDictionary.definition(for: "3105"))
        XCTAssertNil(GS1SyntaxDictionary.definition(for: "3106"))
        XCTAssertNotNil(GS1SyntaxDictionary.definition(for: "91"))
        XCTAssertNotNil(GS1SyntaxDictionary.definition(for: "99"))
        XCTAssertNil(GS1SyntaxDictionary.definition(for: "9"))
    }

    func testPredefinedLengthPrefixes() {
        let prefixes = GS1SyntaxDictionary.predefinedLengthPrefixes
        for expected in ["00", "01", "02", "11", "17", "20", "31", "36", "41"] {
            XCTAssertTrue(prefixes.contains(expected), "\(expected) should be pre-defined length")
        }
        for unexpected in ["10", "21", "37", "90"] {
            XCTAssertFalse(prefixes.contains(unexpected), "\(unexpected) is variable length")
        }
    }

    func testOptionalComponentsAndMultiComponentAIs() {
        let gdti = GS1SyntaxDictionary.definition(for: "253")!
        XCTAssertEqual(gdti.components.count, 2)
        XCTAssertFalse(gdti.components[0].isOptional)
        XCTAssertTrue(gdti.components[1].isOptional)
        XCTAssertEqual(gdti.minimumDataLength, 13)
        XCTAssertEqual(gdti.maximumDataLength, 30)

        let itip = GS1SyntaxDictionary.definition(for: "8006")!
        XCTAssertEqual(itip.components.count, 2)
        XCTAssertTrue(itip.components[1].linters.contains("pieceoftotal"))
    }

    // MARK: - Parsing

    func testParsesConcatenatedAndBracketedFormsIdentically() throws {
        let raw = try GS1ElementString.parse(example)
        let bracketed = try GS1ElementString.parse("(01)\(gtin)(17)260331(10)EXAMPLELOTNUMBER")
        XCTAssertEqual(raw.elements, bracketed.elements)
        XCTAssertEqual(raw.elements.map { $0.ai }, ["01", "17", "10"])
        XCTAssertEqual(raw["01"], gtin)
        XCTAssertEqual(raw["10"], "EXAMPLELOTNUMBER")
        XCTAssertEqual(raw.hri, "(01)\(gtin)(17)260331(10)EXAMPLELOTNUMBER")
    }

    func testStripsSymbologyIdentifier() throws {
        let parsed = try GS1ElementString.parse("]d201\(gtin)17260331")
        XCTAssertEqual(parsed.elements.count, 2)
    }

    func testSeparatorHandling() throws {
        let input = "01\(gtin)10LOT\u{1D}21SER"
        let parsed = try GS1ElementString.parse(input)
        XCTAssertEqual(parsed.elements.map { $0.ai }, ["01", "10", "21"])
        XCTAssertEqual(parsed["10"], "LOT")
        XCTAssertEqual(parsed["21"], "SER")

        // Round trip: only the variable length field that is followed by
        // another element keeps its separator.
        XCTAssertEqual(parsed.encoded(), input)
    }

    func testElementOrderOptimisationRemovesSeparators() throws {
        // Batch first, then two pre-defined length elements.
        let parsed = try GS1ElementString.parse("10LOT99\u{1D}01\(gtin)17260331")
        XCTAssertEqual(parsed.elements.map { $0.ai }, ["10", "01", "17"])
        XCTAssertEqual(parsed.optimizedElements.map { $0.ai }, ["01", "17", "10"])
        XCTAssertEqual(parsed.encoded(optimizeOrder: true), "01\(gtin)1726033110LOT99")
        XCTAssertFalse(parsed.encoded(optimizeOrder: true).contains(gs1GroupSeparator))
    }

    func testRedundantSeparatorIsAWarningOrAnError() throws {
        let input = "01\(gtin)\u{1D}17260331"
        let tolerant = try GS1ElementString.parse(input)
        XCTAssertEqual(tolerant.elements.count, 2)
        XCTAssertEqual(tolerant.warnings.count, 1)

        var strict = GS1ValidationOptions.strict
        strict.rejectRedundantSeparators = true
        XCTAssertThrowsError(try GS1ElementString.parse(input, options: strict))
    }

    func testUnknownAIIsRejected() {
        XCTAssertThrowsError(try GS1ElementString.parse("05123456")) { error in
            guard case GS1Error.unknownAI = error else {
                return XCTFail("expected unknownAI, got \(error)")
            }
        }
    }

    // MARK: - Validation

    func testTheCheckDigitOfTheRequestExampleIsWrong() {
        // 01003000051239971726033110EXAMPLELOTNUMBER: the GTIN ends in 7 but
        // 0030000512399 checks to 6.
        XCTAssertThrowsError(
            try GS1DataMatrix.validate("01003000051239971726033110EXAMPLELOTNUMBER")
        ) { error in
            guard case GS1Error.contentRejected(let ai, _, let failure) = error else {
                return XCTFail("expected contentRejected, got \(error)")
            }
            XCTAssertEqual(ai, "01")
            XCTAssertEqual(failure.linter, "csum")
        }
    }

    func testDateValidation() throws {
        XCTAssertNoThrow(try GS1ElementString.parse("01\(gtin)17260331"))
        XCTAssertNoThrow(try GS1ElementString.parse("01\(gtin)17260300"))  // day 00 allowed
        XCTAssertThrowsError(try GS1ElementString.parse("01\(gtin)17261332"))
        XCTAssertThrowsError(try GS1ElementString.parse("01\(gtin)17260231"))
        XCTAssertThrowsError(try GS1ElementString.parse("01\(gtin)11260000")) // month 00
    }

    func testEveryLinterInTheTableIsAccountedFor() {
        var referenced = Set<String>()
        for ai in GS1SyntaxDictionary.allAIs {
            guard let definition = GS1SyntaxDictionary.definition(for: ai) else { continue }
            for component in definition.components {
                referenced.formUnion(component.linters)
            }
        }
        let known = Set(GS1Linters.builtin.keys).union(GS1Linters.unimplemented)
        XCTAssertTrue(referenced.subtracting(known).isEmpty,
                      "unhandled linters: \(referenced.subtracting(known).sorted())")
        XCTAssertFalse(referenced.isEmpty)
    }

    func testCharacterSetValidation() {
        XCTAssertThrowsError(try GS1ElementString.parse("(01)0030000512399A")) { error in
            guard case GS1Error.invalidCharacter(_, let character, let set) = error else {
                return XCTFail("expected invalidCharacter, got \(error)")
            }
            XCTAssertEqual(character, "A")
            XCTAssertEqual(set, .numeric)
        }
        // "?" is in CSET 82, "{" is not.
        XCTAssertNoThrow(try GS1ElementString.parse("(01)\(gtin)(10)LOT?1"))
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(10)LOT{1}"))
    }

    func testLengthValidation() {
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(10)\(String(repeating: "A", count: 21))")) { error in
            guard case GS1Error.dataTooLong = error else {
                return XCTFail("expected dataTooLong, got \(error)")
            }
        }
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(10)")) { error in
            guard case GS1Error.emptyValue = error else {
                return XCTFail("expected emptyValue, got \(error)")
            }
        }
        XCTAssertThrowsError(try GS1ElementString.parse("(01)003000051239")) { error in
            guard case GS1Error.dataTooShort = error else {
                return XCTFail("expected dataTooShort, got \(error)")
            }
        }
    }

    func testMandatoryAssociation() {
        // AI 10 may only be used alongside a product identifier.
        XCTAssertThrowsError(try GS1ElementString.parse("(10)LOT123")) { error in
            guard case GS1Error.missingMandatoryAssociation(let ai, _) = error else {
                return XCTFail("expected missingMandatoryAssociation, got \(error)")
            }
            XCTAssertEqual(ai, "10")
        }
        XCTAssertNoThrow(try GS1ElementString.parse("(01)\(gtin)(10)LOT123"))

        // (02) and (37) are mandatory partners; (00) carries the logistic unit.
        XCTAssertNoThrow(try GS1ElementString.parse("(00)106141411234567897(02)\(gtin)(37)12"))
        XCTAssertThrowsError(try GS1ElementString.parse("(00)106141411234567897(02)\(gtin)"))
    }

    func testInvalidPairing() {
        // (01) and (02) must not appear together.
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(02)\(gtin)(37)12")) { error in
            guard case GS1Error.invalidPairing = error else {
                return XCTFail("expected invalidPairing, got \(error)")
            }
        }
    }

    func testRepeatedAI() {
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(10)A(10)B")) { error in
            guard case GS1Error.repeatedAI(let ai) = error else {
                return XCTFail("expected repeatedAI, got \(error)")
            }
            XCTAssertEqual(ai, "10")
        }
    }

    func testLenientOptionsSkipContentRules() throws {
        let parsed = try GS1ElementString.parse("01003000051239971726033110LOT",
                                                options: .lenient)
        XCTAssertEqual(parsed.elements.count, 3)
        XCTAssertEqual(parsed["01"], "00300005123997")
    }

    func testMultiComponentLinters() throws {
        // AI 8006: GTIN-14 + piece number / total.
        XCTAssertNoThrow(try GS1ElementString.parse("(8006)\(gtin)0103"))
        // Piece 4 of 3 is impossible.
        XCTAssertThrowsError(try GS1ElementString.parse("(8006)\(gtin)0403"))
        // AI 422 must be a plausible country code.
        XCTAssertThrowsError(try GS1ElementString.parse("(01)\(gtin)(422)000"))
    }

    func testIBANLinter() {
        XCTAssertNil(GS1Linters.validateIBAN("GB82WEST12345698765432"))
        XCTAssertNotNil(GS1Linters.validateIBAN("GB82WEST12345698765431"))
    }

    // MARK: - End to end

    func testExampleEncodesToAKnownSymbol() throws {
        let encoded = try GS1DataMatrix.encode("(01)\(gtin)(17)260331(10)EXAMPLELOTNUMBER")

        XCTAssertEqual(encoded.size, "22x22")
        XCTAssertEqual(encoded.hri, "(01)\(gtin)(17)260331(10)EXAMPLELOTNUMBER")
        XCTAssertEqual(encoded.symbol.payloadCodewordCount, 30)

        XCTAssertEqual(encoded.symbol.dataCodewords,
                       [232, 131, 130, 160, 130, 135, 142, 169, 226, 147,
                        156, 133, 161, 140, 70, 89, 66, 78, 81, 77,
                        70, 77, 80, 85, 79, 86, 78, 67, 70, 83])
        XCTAssertEqual(encoded.symbol.errorCodewords,
                       [246, 250, 143, 232, 193, 51, 123, 57, 233, 208,
                        178, 64, 209, 146, 1, 232, 147, 104, 178, 49])
        XCTAssertEqual(encoded.matrix.darkCount, 242)

        // The symbol must start with FNC1 to be a GS1 DataMatrix.
        XCTAssertEqual(encoded.symbol.dataCodewords.first, 232)

        let svg = encoded.svg()
        XCTAssertTrue(svg.contains("viewBox=\"0 0 24 24\""))
        XCTAssertTrue(svg.contains("<desc>(01)\(gtin)(17)260331(10)EXAMPLELOTNUMBER</desc>"))
    }

    func testKnownSymbolSizes() throws {
        XCTAssertEqual(try GS1DataMatrix.encode("(01)\(gtin)").size, "16x16")
        XCTAssertEqual(try GS1DataMatrix.encode("(00)106141411234567897").size, "16x16")
        XCTAssertEqual(try GS1DataMatrix.encode("(01)\(gtin)(21)SERIAL123").size, "18x18")
    }

    func testRectangularSymbolsAreAvailable() throws {
        var options = GS1DataMatrix.Options()
        options.shape = .rectangle
        let encoded = try GS1DataMatrix.encode("(01)\(gtin)", options: options)
        XCTAssertTrue(SymbolAttributes.rectangles.contains { $0.name == encoded.size })
        XCTAssertNotEqual(encoded.symbol.attributes.rows, encoded.symbol.attributes.columns)
    }

    func testEncodingFromPairs() throws {
        let encoded = try GS1DataMatrix.encode([("01", gtin), ("17", "260331"), ("10", "EXAMPLELOTNUMBER")])
        XCTAssertEqual(encoded.size, "22x22")
    }

    func testFixedSizeAndQuietZone() throws {
        var options = GS1DataMatrix.Options()
        options.fixedSize = "32x32"
        let encoded = try GS1DataMatrix.encode("(01)\(gtin)", options: options)
        XCTAssertEqual(encoded.size, "32x32")

        let svg = encoded.svg(options: SVGOptions(quietZone: 4))
        XCTAssertTrue(svg.contains("viewBox=\"0 0 40 40\""))
    }
}
