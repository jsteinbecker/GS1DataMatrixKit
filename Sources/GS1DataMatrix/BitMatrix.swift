//
//  BitMatrix.swift
//  A simple dark/light module grid, plus text renderings for debugging.
//

/// A rectangular grid of modules. `true` means a dark module.
public struct BitMatrix: Equatable, Sendable {

    public let rows: Int
    public let columns: Int
    public private(set) var modules: [Bool]

    public init(rows: Int, columns: Int) {
        precondition(rows > 0 && columns > 0)
        self.rows = rows
        self.columns = columns
        self.modules = [Bool](repeating: false, count: rows * columns)
    }

    public init(rows: Int, columns: Int, modules: [Bool]) {
        precondition(modules.count == rows * columns)
        self.rows = rows
        self.columns = columns
        self.modules = modules
    }

    public subscript(row: Int, column: Int) -> Bool {
        get { modules[row * columns + column] }
        set { modules[row * columns + column] = newValue }
    }

    /// Number of dark modules.
    public var darkCount: Int { modules.reduce(0) { $0 + ($1 ? 1 : 0) } }

    /// Two characters per module so the aspect ratio looks right in a terminal.
    public func asciiArt(dark: String = "██", light: String = "  ", quietZone: Int = 1) -> String {
        var lines: [String] = []
        let width = columns + 2 * quietZone
        let blank = String(repeating: light, count: width)
        for _ in 0..<quietZone { lines.append(blank) }
        for r in 0..<rows {
            var line = String(repeating: light, count: quietZone)
            for c in 0..<columns {
                line += self[r, c] ? dark : light
            }
            line += String(repeating: light, count: quietZone)
            lines.append(line)
        }
        for _ in 0..<quietZone { lines.append(blank) }
        return lines.joined(separator: "\n")
    }

    /// Portable bitmap (P1) representation, handy for piping into image tools.
    public func pbm(quietZone: Int = 1) -> String {
        let width = columns + 2 * quietZone
        let height = rows + 2 * quietZone
        var out = "P1\n\(width) \(height)\n"
        for r in 0..<height {
            var line = ""
            for c in 0..<width {
                let inside = r >= quietZone && r < quietZone + rows
                    && c >= quietZone && c < quietZone + columns
                let dark = inside && self[r - quietZone, c - quietZone]
                line += dark ? "1" : "0"
                if c < width - 1 { line += " " }
            }
            out += line + "\n"
        }
        return out
    }
}
