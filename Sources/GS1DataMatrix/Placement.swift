//
//  Placement.swift
//  ECC200 symbol character placement (ISO/IEC 16022 Annex F).
//
//  The placement operates on the "mapping matrix": all data regions joined
//  together with the finder pattern and clock track removed. Each codeword is
//  laid out as an L-shaped "utah" of eight modules, walking diagonally up-right
//  and down-left, with four special corner cases.
//

/// Where a given mapping-matrix module gets its value from.
enum PlacementCell: Equatable {
    /// Bit `bit` (0 = most significant) of data codeword `codeword` (0-based).
    case bit(codeword: Int, bit: Int)
    /// The fixed dark module of the 2x2 bottom-right corner that exists in
    /// symbols whose mapping matrix is not a whole number of codewords.
    case forcedDark
    /// The fixed light modules of that same corner.
    case forcedLight
}

struct PlacementMap {
    let rows: Int
    let columns: Int
    /// Row-major, `rows * columns` entries.
    let cells: [PlacementCell]

    subscript(row: Int, column: Int) -> PlacementCell {
        cells[row * columns + column]
    }
}

enum Placement {

    /// Builds the placement map for a mapping matrix of `rows` x `columns`.
    static func map(rows: Int, columns: Int) -> PlacementMap {
        var cells = [PlacementCell?](repeating: nil, count: rows * columns)

        /// ISO/IEC 16022 Annex F "module" helper: wraps out-of-range
        /// coordinates back into the matrix.
        func module(_ row: Int, _ column: Int, _ codeword: Int, _ bit: Int) {
            var r = row
            var c = column
            if r < 0 {
                r += rows
                c += 4 - ((rows + 4) % 8)
            }
            if c < 0 {
                c += columns
                r += 4 - ((columns + 4) % 8)
            }
            // Symbols 144x144 and larger can address a row beyond the matrix.
            if r >= rows {
                r -= rows
            }
            cells[r * columns + c] = .bit(codeword: codeword, bit: bit)
        }

        /// Annex F "utah": the standard 3x3-minus-one shape for one codeword.
        func utah(_ row: Int, _ column: Int, _ codeword: Int) {
            module(row - 2, column - 2, codeword, 0)
            module(row - 2, column - 1, codeword, 1)
            module(row - 1, column - 2, codeword, 2)
            module(row - 1, column - 1, codeword, 3)
            module(row - 1, column,     codeword, 4)
            module(row,     column - 2, codeword, 5)
            module(row,     column - 1, codeword, 6)
            module(row,     column,     codeword, 7)
        }

        func corner1(_ codeword: Int) {
            module(rows - 1, 0, codeword, 0)
            module(rows - 1, 1, codeword, 1)
            module(rows - 1, 2, codeword, 2)
            module(0, columns - 2, codeword, 3)
            module(0, columns - 1, codeword, 4)
            module(1, columns - 1, codeword, 5)
            module(2, columns - 1, codeword, 6)
            module(3, columns - 1, codeword, 7)
        }

        func corner2(_ codeword: Int) {
            module(rows - 3, 0, codeword, 0)
            module(rows - 2, 0, codeword, 1)
            module(rows - 1, 0, codeword, 2)
            module(0, columns - 4, codeword, 3)
            module(0, columns - 3, codeword, 4)
            module(0, columns - 2, codeword, 5)
            module(0, columns - 1, codeword, 6)
            module(1, columns - 1, codeword, 7)
        }

        func corner3(_ codeword: Int) {
            module(rows - 3, 0, codeword, 0)
            module(rows - 2, 0, codeword, 1)
            module(rows - 1, 0, codeword, 2)
            module(0, columns - 2, codeword, 3)
            module(0, columns - 1, codeword, 4)
            module(1, columns - 1, codeword, 5)
            module(2, columns - 1, codeword, 6)
            module(3, columns - 1, codeword, 7)
        }

        func corner4(_ codeword: Int) {
            module(rows - 1, 0, codeword, 0)
            module(rows - 1, columns - 1, codeword, 1)
            module(0, columns - 3, codeword, 2)
            module(0, columns - 2, codeword, 3)
            module(0, columns - 1, codeword, 4)
            module(1, columns - 3, codeword, 5)
            module(1, columns - 2, codeword, 6)
            module(1, columns - 1, codeword, 7)
        }

        @inline(__always)
        func isEmpty(_ row: Int, _ column: Int) -> Bool {
            cells[row * columns + column] == nil
        }

        var codeword = 0
        var row = 4
        var column = 0

        repeat {
            // Corner cases, checked before each diagonal sweep.
            if row == rows && column == 0 {
                corner1(codeword); codeword += 1
            }
            if row == rows - 2 && column == 0 && (columns % 4) != 0 {
                corner2(codeword); codeword += 1
            }
            if row == rows - 2 && column == 0 && (columns % 8) == 4 {
                corner3(codeword); codeword += 1
            }
            if row == rows + 4 && column == 2 && (columns % 8) == 0 {
                corner4(codeword); codeword += 1
            }

            // Sweep up and to the right.
            repeat {
                if row < rows && column >= 0 && isEmpty(row, column) {
                    utah(row, column, codeword); codeword += 1
                }
                row -= 2
                column += 2
            } while row >= 0 && column < columns
            row += 1
            column += 3

            // Sweep down and to the left.
            repeat {
                if row >= 0 && column < columns && isEmpty(row, column) {
                    utah(row, column, codeword); codeword += 1
                }
                row += 2
                column -= 2
            } while row < rows && column >= 0
            row += 3
            column += 1
        } while row < rows || column < columns

        // Symbols whose mapping matrix is 4 modules larger than a whole number
        // of codewords finish with a fixed 2x2 pattern in the bottom right.
        if cells[rows * columns - 1] == nil {
            cells[rows * columns - 1] = .forcedDark
            cells[rows * columns - 2] = .forcedLight
            cells[(rows - 1) * columns - 1] = .forcedLight
            cells[(rows - 1) * columns - 2] = .forcedDark
        }

        let resolved = cells.map { $0 ?? .forcedLight }
        return PlacementMap(rows: rows, columns: columns, cells: resolved)
    }

    /// Number of codewords a mapping matrix of this size carries.
    static func codewordCapacity(rows: Int, columns: Int) -> Int {
        (rows * columns) / 8
    }
}
