//
//  DataMatrixEncoder.swift
//  ECC200 symbol construction: encodation -> padding -> Reed-Solomon ->
//  placement -> finder pattern.
//

public struct DataMatrixSymbol: Sendable {
    /// The finished module grid, without quiet zone.
    public let matrix: BitMatrix
    /// Which row of the ECC200 symbol attribute table was used.
    public let attributes: SymbolAttributes
    /// Data codewords, after padding.
    public let dataCodewords: [Int]
    /// Error-correction codewords, in interleaved symbol order.
    public let errorCodewords: [Int]
    /// Data codewords before padding was applied.
    public let payloadCodewordCount: Int

    public var rows: Int { matrix.rows }
    public var columns: Int { matrix.columns }
}

public enum DataMatrixError: Error, Equatable, CustomStringConvertible {
    /// The payload does not fit in any ECC200 symbol of the requested shape.
    case dataTooLarge(codewords: Int, shape: SymbolShape)
    /// A fixed symbol size was requested that cannot hold the payload.
    case doesNotFitRequestedSize(codewords: Int, capacity: Int, size: String)
    /// An unknown symbol size name was requested.
    case unknownSymbolSize(String)
    /// The payload was empty.
    case emptyPayload
    /// Internal consistency check failed (should never happen).
    case selfCheckFailed(String)

    public var description: String {
        switch self {
        case .dataTooLarge(let codewords, let shape):
            return "Payload needs \(codewords) codewords, which exceeds the largest \(shape) ECC200 symbol."
        case .doesNotFitRequestedSize(let codewords, let capacity, let size):
            return "Payload needs \(codewords) codewords but symbol \(size) holds only \(capacity)."
        case .unknownSymbolSize(let name):
            return "Unknown ECC200 symbol size '\(name)'."
        case .emptyPayload:
            return "Nothing to encode."
        case .selfCheckFailed(let detail):
            return "Encoder self-check failed: \(detail)"
        }
    }
}

public enum DataMatrixEncoder {

    /// Encodes tokens into a finished ECC200 symbol.
    ///
    /// - Parameters:
    ///   - tokens: payload, with `.fnc1` where an FNC1 character is required.
    ///   - shape: which family of symbol sizes may be chosen.
    ///   - fixedSize: force an exact size such as `"22x22"`; `nil` picks the
    ///     smallest symbol that fits.
    ///   - minimumRows/minimumColumns: floor on the automatically chosen size.
    ///   - verify: run a Reed-Solomon syndrome check and read the placement
    ///     back before returning. Cheap, and catches any corruption.
    public static func encode(tokens: [EncodationToken],
                              shape: SymbolShape = .square,
                              fixedSize: String? = nil,
                              minimumRows: Int = 0,
                              minimumColumns: Int = 0,
                              verify: Bool = true) throws -> DataMatrixSymbol {
        guard !tokens.isEmpty else { throw DataMatrixError.emptyPayload }

        let payload = ASCIIEncodation.encode(tokens)

        let attributes: SymbolAttributes
        if let fixedSize {
            guard let requested = SymbolAttributes.named(fixedSize) else {
                throw DataMatrixError.unknownSymbolSize(fixedSize)
            }
            guard requested.dataCodewords >= payload.count else {
                throw DataMatrixError.doesNotFitRequestedSize(codewords: payload.count,
                                                              capacity: requested.dataCodewords,
                                                              size: requested.name)
            }
            attributes = requested
        } else {
            guard let chosen = SymbolAttributes.smallest(fitting: payload.count,
                                                         shape: shape,
                                                         minimumRows: minimumRows,
                                                         minimumColumns: minimumColumns) else {
                throw DataMatrixError.dataTooLarge(codewords: payload.count, shape: shape)
            }
            attributes = chosen
        }

        let data = ASCIIEncodation.pad(payload, to: attributes.dataCodewords)
        let ecc = interleavedErrorCorrection(for: data, attributes: attributes)
        let matrix = buildMatrix(codewords: data + ecc, attributes: attributes)

        let symbol = DataMatrixSymbol(matrix: matrix,
                                      attributes: attributes,
                                      dataCodewords: data,
                                      errorCodewords: ecc,
                                      payloadCodewordCount: payload.count)

        if verify {
            try selfCheck(symbol)
        }
        return symbol
    }

    // MARK: - Reed-Solomon with block interleaving

    /// Splits the data into `attributes.blocks` interleaved blocks, computes
    /// the check codewords for each, then re-interleaves them.
    static func interleavedErrorCorrection(for data: [Int],
                                           attributes: SymbolAttributes) -> [Int] {
        let blockCount = attributes.blocks
        let eccPerBlock = attributes.errorCodewordsPerBlock

        var blocks = [[Int]](repeating: [], count: blockCount)
        for (index, value) in data.enumerated() {
            blocks[index % blockCount].append(value)
        }

        var eccBlocks: [[Int]] = []
        eccBlocks.reserveCapacity(blockCount)
        for block in blocks {
            eccBlocks.append(ReedSolomon.errorCorrection(for: block, count: eccPerBlock))
        }

        var interleaved = [Int](repeating: 0, count: eccPerBlock * blockCount)
        for position in 0..<eccPerBlock {
            for block in 0..<blockCount {
                interleaved[position * blockCount + block] = eccBlocks[block][position]
            }
        }
        return interleaved
    }

    // MARK: - Matrix assembly

    /// Places codewords in the mapping matrix, then splits it into data regions
    /// and surrounds each with the finder pattern and clock track.
    static func buildMatrix(codewords: [Int], attributes: SymbolAttributes) -> BitMatrix {
        let map = Placement.map(rows: attributes.mappingRows,
                                columns: attributes.mappingColumns)

        var symbol = BitMatrix(rows: attributes.rows, columns: attributes.columns)

        // 1. Finder pattern and clock track, one L per data region.
        for regionRow in 0..<attributes.regionsDown {
            for regionColumn in 0..<attributes.regionsAcross {
                let top = regionRow * (attributes.regionRows + 2)
                let left = regionColumn * (attributes.regionColumns + 2)
                let bottom = top + attributes.regionRows + 1
                let right = left + attributes.regionColumns + 1

                for r in top...bottom {
                    symbol[r, left] = true                              // solid left
                    symbol[r, right] = ((bottom - r) % 2 == 0)          // clock track right
                }
                for c in left...right {
                    symbol[bottom, c] = true                            // solid bottom
                    symbol[top, c] = ((c - left) % 2 == 0)              // clock track top
                }
            }
        }

        // 2. Data modules.
        for mappingRow in 0..<attributes.mappingRows {
            let regionRow = mappingRow / attributes.regionRows
            let symbolRow = regionRow * (attributes.regionRows + 2) + 1
                + (mappingRow % attributes.regionRows)

            for mappingColumn in 0..<attributes.mappingColumns {
                let regionColumn = mappingColumn / attributes.regionColumns
                let symbolColumn = regionColumn * (attributes.regionColumns + 2) + 1
                    + (mappingColumn % attributes.regionColumns)

                switch map[mappingRow, mappingColumn] {
                case .bit(let codeword, let bit):
                    let value = codeword < codewords.count ? codewords[codeword] : 0
                    symbol[symbolRow, symbolColumn] = (value & (0x80 >> bit)) != 0
                case .forcedDark:
                    symbol[symbolRow, symbolColumn] = true
                case .forcedLight:
                    symbol[symbolRow, symbolColumn] = false
                }
            }
        }

        return symbol
    }

    // MARK: - Self check

    /// Reads the symbol back out of the module grid and confirms every
    /// Reed-Solomon block has zero syndromes. Catches placement or arithmetic
    /// corruption before a bad label ever gets printed.
    static func selfCheck(_ symbol: DataMatrixSymbol) throws {
        let attributes = symbol.attributes
        let map = Placement.map(rows: attributes.mappingRows,
                                columns: attributes.mappingColumns)
        var recovered = [Int](repeating: 0, count: attributes.totalCodewords)

        for mappingRow in 0..<attributes.mappingRows {
            let regionRow = mappingRow / attributes.regionRows
            let symbolRow = regionRow * (attributes.regionRows + 2) + 1
                + (mappingRow % attributes.regionRows)

            for mappingColumn in 0..<attributes.mappingColumns {
                let regionColumn = mappingColumn / attributes.regionColumns
                let symbolColumn = regionColumn * (attributes.regionColumns + 2) + 1
                    + (mappingColumn % attributes.regionColumns)

                if case .bit(let codeword, let bit) = map[mappingRow, mappingColumn] {
                    if symbol.matrix[symbolRow, symbolColumn] {
                        recovered[codeword] |= (0x80 >> bit)
                    }
                }
            }
        }

        let expected = symbol.dataCodewords + symbol.errorCodewords
        guard recovered == expected else {
            throw DataMatrixError.selfCheckFailed("placement did not round-trip")
        }

        // De-interleave and check syndromes block by block.
        let blockCount = attributes.blocks
        let eccPerBlock = attributes.errorCodewordsPerBlock
        for block in 0..<blockCount {
            var stream: [Int] = []
            var index = block
            while index < symbol.dataCodewords.count {
                stream.append(symbol.dataCodewords[index])
                index += blockCount
            }
            for position in 0..<eccPerBlock {
                stream.append(symbol.errorCodewords[position * blockCount + block])
            }
            let syndromes = ReedSolomon.syndromes(of: stream, count: eccPerBlock)
            guard syndromes.allSatisfy({ $0 == 0 }) else {
                throw DataMatrixError.selfCheckFailed("non-zero syndrome in block \(block)")
            }
        }
    }
}
