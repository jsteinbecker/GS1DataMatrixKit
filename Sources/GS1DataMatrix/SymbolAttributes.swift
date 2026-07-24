//
//  SymbolAttributes.swift
//  The ECC200 symbol attribute table (ISO/IEC 16022 Table 7 and Table 9).
//

/// Which symbol shapes the encoder may choose from.
public enum SymbolShape: Sendable, Equatable {
    /// Square symbols only (10x10 ... 144x144). The GS1 General Specifications
    /// require square symbols for most application areas, so this is the default.
    case square
    /// Rectangular symbols only (8x18 ... 16x48).
    case rectangle
    /// Smallest symbol of either shape.
    case any
}

/// One row of the ECC200 symbol attribute table.
public struct SymbolAttributes: Sendable, Equatable {

    /// Total symbol height in modules, including finder pattern and clock track.
    public let rows: Int
    /// Total symbol width in modules, including finder pattern and clock track.
    public let columns: Int
    /// Height in modules of a single data region (finder pattern excluded).
    public let regionRows: Int
    /// Width in modules of a single data region (finder pattern excluded).
    public let regionColumns: Int
    /// Number of data regions stacked vertically.
    public let regionsDown: Int
    /// Number of data regions placed horizontally.
    public let regionsAcross: Int
    /// Number of data codewords the symbol can carry.
    public let dataCodewords: Int
    /// Number of error-correction codewords per Reed-Solomon block.
    public let errorCodewordsPerBlock: Int
    /// Number of interleaved Reed-Solomon blocks.
    public let blocks: Int

    public init(rows: Int, columns: Int,
                regionRows: Int, regionColumns: Int,
                regionsDown: Int, regionsAcross: Int,
                dataCodewords: Int, errorCodewordsPerBlock: Int, blocks: Int) {
        self.rows = rows
        self.columns = columns
        self.regionRows = regionRows
        self.regionColumns = regionColumns
        self.regionsDown = regionsDown
        self.regionsAcross = regionsAcross
        self.dataCodewords = dataCodewords
        self.errorCodewordsPerBlock = errorCodewordsPerBlock
        self.blocks = blocks
    }

    public var isSquare: Bool { rows == columns }

    /// Total error-correction codewords across all blocks.
    public var errorCodewords: Int { errorCodewordsPerBlock * blocks }

    /// Total codewords carried by the mapping matrix.
    public var totalCodewords: Int { dataCodewords + errorCodewords }

    /// Height of the mapping matrix (all data regions, finder patterns removed).
    public var mappingRows: Int { regionRows * regionsDown }
    /// Width of the mapping matrix (all data regions, finder patterns removed).
    public var mappingColumns: Int { regionColumns * regionsAcross }

    /// Human friendly size, e.g. `"16x48"`.
    public var name: String { "\(rows)x\(columns)" }

    /// Number of data codewords in Reed-Solomon block `index`.
    /// Blocks are filled round-robin, which produces the 156/155 split that
    /// ISO/IEC 16022 specifies for the 144x144 symbol.
    public func dataCodewords(inBlock index: Int) -> Int {
        let base = dataCodewords / blocks
        return index < (dataCodewords % blocks) ? base + 1 : base
    }
}

public extension SymbolAttributes {

    /// The 24 square ECC200 symbol sizes.
    static let squares: [SymbolAttributes] = [
        SymbolAttributes(rows: 10, columns: 10, regionRows: 8, regionColumns: 8,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 3, errorCodewordsPerBlock: 5, blocks: 1),
        SymbolAttributes(rows: 12, columns: 12, regionRows: 10, regionColumns: 10,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 5, errorCodewordsPerBlock: 7, blocks: 1),
        SymbolAttributes(rows: 14, columns: 14, regionRows: 12, regionColumns: 12,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 8, errorCodewordsPerBlock: 10, blocks: 1),
        SymbolAttributes(rows: 16, columns: 16, regionRows: 14, regionColumns: 14,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 12, errorCodewordsPerBlock: 12, blocks: 1),
        SymbolAttributes(rows: 18, columns: 18, regionRows: 16, regionColumns: 16,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 18, errorCodewordsPerBlock: 14, blocks: 1),
        SymbolAttributes(rows: 20, columns: 20, regionRows: 18, regionColumns: 18,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 22, errorCodewordsPerBlock: 18, blocks: 1),
        SymbolAttributes(rows: 22, columns: 22, regionRows: 20, regionColumns: 20,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 30, errorCodewordsPerBlock: 20, blocks: 1),
        SymbolAttributes(rows: 24, columns: 24, regionRows: 22, regionColumns: 22,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 36, errorCodewordsPerBlock: 24, blocks: 1),
        SymbolAttributes(rows: 26, columns: 26, regionRows: 24, regionColumns: 24,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 44, errorCodewordsPerBlock: 28, blocks: 1),
        SymbolAttributes(rows: 32, columns: 32, regionRows: 14, regionColumns: 14,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 62, errorCodewordsPerBlock: 36, blocks: 1),
        SymbolAttributes(rows: 36, columns: 36, regionRows: 16, regionColumns: 16,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 86, errorCodewordsPerBlock: 42, blocks: 1),
        SymbolAttributes(rows: 40, columns: 40, regionRows: 18, regionColumns: 18,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 114, errorCodewordsPerBlock: 48, blocks: 1),
        SymbolAttributes(rows: 44, columns: 44, regionRows: 20, regionColumns: 20,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 144, errorCodewordsPerBlock: 56, blocks: 1),
        SymbolAttributes(rows: 48, columns: 48, regionRows: 22, regionColumns: 22,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 174, errorCodewordsPerBlock: 68, blocks: 1),
        SymbolAttributes(rows: 52, columns: 52, regionRows: 24, regionColumns: 24,
                         regionsDown: 2, regionsAcross: 2,
                         dataCodewords: 204, errorCodewordsPerBlock: 42, blocks: 2),
        SymbolAttributes(rows: 64, columns: 64, regionRows: 14, regionColumns: 14,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 280, errorCodewordsPerBlock: 56, blocks: 2),
        SymbolAttributes(rows: 72, columns: 72, regionRows: 16, regionColumns: 16,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 368, errorCodewordsPerBlock: 36, blocks: 4),
        SymbolAttributes(rows: 80, columns: 80, regionRows: 18, regionColumns: 18,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 456, errorCodewordsPerBlock: 48, blocks: 4),
        SymbolAttributes(rows: 88, columns: 88, regionRows: 20, regionColumns: 20,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 576, errorCodewordsPerBlock: 56, blocks: 4),
        SymbolAttributes(rows: 96, columns: 96, regionRows: 22, regionColumns: 22,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 696, errorCodewordsPerBlock: 68, blocks: 4),
        SymbolAttributes(rows: 104, columns: 104, regionRows: 24, regionColumns: 24,
                         regionsDown: 4, regionsAcross: 4,
                         dataCodewords: 816, errorCodewordsPerBlock: 56, blocks: 6),
        SymbolAttributes(rows: 120, columns: 120, regionRows: 18, regionColumns: 18,
                         regionsDown: 6, regionsAcross: 6,
                         dataCodewords: 1050, errorCodewordsPerBlock: 68, blocks: 6),
        SymbolAttributes(rows: 132, columns: 132, regionRows: 20, regionColumns: 20,
                         regionsDown: 6, regionsAcross: 6,
                         dataCodewords: 1304, errorCodewordsPerBlock: 62, blocks: 8),
        SymbolAttributes(rows: 144, columns: 144, regionRows: 22, regionColumns: 22,
                         regionsDown: 6, regionsAcross: 6,
                         dataCodewords: 1558, errorCodewordsPerBlock: 62, blocks: 10),
    ]

    /// The 6 rectangular ECC200 symbol sizes.
    static let rectangles: [SymbolAttributes] = [
        SymbolAttributes(rows: 8, columns: 18, regionRows: 6, regionColumns: 16,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 5, errorCodewordsPerBlock: 7, blocks: 1),
        SymbolAttributes(rows: 8, columns: 32, regionRows: 6, regionColumns: 14,
                         regionsDown: 1, regionsAcross: 2,
                         dataCodewords: 10, errorCodewordsPerBlock: 11, blocks: 1),
        SymbolAttributes(rows: 12, columns: 26, regionRows: 10, regionColumns: 24,
                         regionsDown: 1, regionsAcross: 1,
                         dataCodewords: 16, errorCodewordsPerBlock: 14, blocks: 1),
        SymbolAttributes(rows: 12, columns: 36, regionRows: 10, regionColumns: 16,
                         regionsDown: 1, regionsAcross: 2,
                         dataCodewords: 22, errorCodewordsPerBlock: 18, blocks: 1),
        SymbolAttributes(rows: 16, columns: 36, regionRows: 14, regionColumns: 16,
                         regionsDown: 1, regionsAcross: 2,
                         dataCodewords: 32, errorCodewordsPerBlock: 24, blocks: 1),
        SymbolAttributes(rows: 16, columns: 48, regionRows: 14, regionColumns: 22,
                         regionsDown: 1, regionsAcross: 2,
                         dataCodewords: 49, errorCodewordsPerBlock: 28, blocks: 1),
    ]

    /// All 30 ECC200 symbol sizes, ordered by data capacity. The comparison is
    /// a total order, so symbol selection is deterministic even where a square
    /// and a rectangle hold the same number of codewords.
    static let all: [SymbolAttributes] = (squares + rectangles)
        .sorted { lhs, rhs in
            if lhs.dataCodewords != rhs.dataCodewords { return lhs.dataCodewords < rhs.dataCodewords }
            let lhsArea = lhs.rows * lhs.columns
            let rhsArea = rhs.rows * rhs.columns
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            return lhs.rows < rhs.rows
        }

    /// Smallest symbol of the requested `shape` that holds `codewordCount`
    /// data codewords, honouring an optional minimum size.
    static func smallest(fitting codewordCount: Int,
                         shape: SymbolShape,
                         minimumRows: Int = 0,
                         minimumColumns: Int = 0) -> SymbolAttributes? {
        // `all` is already in a deterministic capacity order.
        return all.first { candidate in
            let shapeMatches: Bool
            switch shape {
            case .square: shapeMatches = candidate.isSquare
            case .rectangle: shapeMatches = !candidate.isSquare
            case .any: shapeMatches = true
            }
            return shapeMatches
                && candidate.dataCodewords >= codewordCount
                && candidate.rows >= minimumRows
                && candidate.columns >= minimumColumns
        }
    }

    /// Looks up an exact symbol size, e.g. `SymbolAttributes.named("22x22")`.
    static func named(_ name: String) -> SymbolAttributes? {
        return all.first { $0.name == name }
    }
}
