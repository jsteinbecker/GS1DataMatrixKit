//
//  SVGRenderer.swift
//  Vector output. One module = one unit in the viewBox, so the symbol scales
//  losslessly; `moduleSize` only sets the nominal width/height attributes.
//

public struct SVGOptions: Sendable {

    public enum Sizing: Sendable {
        /// Emit width/height in the given unit, `moduleSize` units per module.
        case moduleSize(Double, unit: String)
        /// Emit width/height covering the whole symbol including quiet zone.
        case total(width: Double, height: Double, unit: String)
        /// Emit no width/height at all; the SVG scales to its container.
        case responsive
    }

    /// Quiet zone in modules. GS1 requires a minimum of 1 module on all sides
    /// for DataMatrix; the default follows that.
    public var quietZone: Int
    public var sizing: Sizing
    /// Colour of dark modules. Any valid SVG paint string.
    public var foreground: String
    /// Colour of the background rectangle, or `nil` for a transparent
    /// background (only do this if the substrate is known to be light).
    public var background: String?
    /// Emit one `<path>` with merged horizontal runs instead of one `<rect>`
    /// per module. Much smaller output; on by default.
    public var mergeRuns: Bool
    /// Adds `<title>`/`<desc>` metadata for accessibility and debugging.
    public var title: String?
    public var descriptionText: String?
    /// Include the XML prolog. Turn off when embedding the SVG inline in HTML.
    public var includeXMLDeclaration: Bool

    public init(quietZone: Int = 1,
                sizing: Sizing = .moduleSize(4, unit: "px"),
                foreground: String = "#000000",
                background: String? = "#FFFFFF",
                mergeRuns: Bool = true,
                title: String? = nil,
                descriptionText: String? = nil,
                includeXMLDeclaration: Bool = true) {
        self.quietZone = quietZone
        self.sizing = sizing
        self.foreground = foreground
        self.background = background
        self.mergeRuns = mergeRuns
        self.title = title
        self.descriptionText = descriptionText
        self.includeXMLDeclaration = includeXMLDeclaration
    }

    public static let `default` = SVGOptions()
}

public enum SVGRenderer {

    public static func render(_ matrix: BitMatrix, options: SVGOptions = .default) -> String {
        let quiet = max(0, options.quietZone)
        let viewWidth = matrix.columns + 2 * quiet
        let viewHeight = matrix.rows + 2 * quiet

        var attributes = "xmlns=\"http://www.w3.org/2000/svg\""
        switch options.sizing {
        case .moduleSize(let size, let unit):
            attributes += " width=\"\(format(Double(viewWidth) * size))\(unit)\""
            attributes += " height=\"\(format(Double(viewHeight) * size))\(unit)\""
        case .total(let width, let height, let unit):
            attributes += " width=\"\(format(width))\(unit)\" height=\"\(format(height))\(unit)\""
        case .responsive:
            break
        }
        attributes += " viewBox=\"0 0 \(viewWidth) \(viewHeight)\""
        attributes += " shape-rendering=\"crispEdges\""

        var out = ""
        if options.includeXMLDeclaration {
            out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        }
        out += "<svg \(attributes)>\n"

        if let title = options.title {
            out += "  <title>\(escape(title))</title>\n"
        }
        if let desc = options.descriptionText {
            out += "  <desc>\(escape(desc))</desc>\n"
        }
        if let background = options.background {
            out += "  <rect x=\"0\" y=\"0\" width=\"\(viewWidth)\" height=\"\(viewHeight)\""
            out += " fill=\"\(background)\"/>\n"
        }

        if options.mergeRuns {
            out += "  <path fill=\"\(options.foreground)\" d=\"\(pathData(matrix, quietZone: quiet))\"/>\n"
        } else {
            for row in 0..<matrix.rows {
                for column in 0..<matrix.columns where matrix[row, column] {
                    out += "  <rect x=\"\(column + quiet)\" y=\"\(row + quiet)\""
                    out += " width=\"1\" height=\"1\" fill=\"\(options.foreground)\"/>\n"
                }
            }
        }

        out += "</svg>\n"
        return out
    }

    /// Merges consecutive dark modules in a row into a single rectangle.
    static func pathData(_ matrix: BitMatrix, quietZone: Int) -> String {
        var parts: [String] = []
        for row in 0..<matrix.rows {
            var column = 0
            while column < matrix.columns {
                guard matrix[row, column] else { column += 1; continue }
                var run = 1
                while column + run < matrix.columns && matrix[row, column + run] { run += 1 }
                parts.append("M\(column + quietZone) \(row + quietZone)h\(run)v1h-\(run)z")
                column += run
            }
        }
        return parts.joined()
    }

    /// Trims a trailing ".0" so integral sizes render as "60px" not "60.0px".
    static func format(_ value: Double) -> String {
        if value == value.rounded() && value.magnitude < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }
}

public extension BitMatrix {
    /// Convenience: render this grid as SVG.
    func svg(options: SVGOptions = .default) -> String {
        SVGRenderer.render(self, options: options)
    }
}

public extension DataMatrixSymbol {
    /// Convenience: render this symbol as SVG.
    func svg(options: SVGOptions = .default) -> String {
        SVGRenderer.render(matrix, options: options)
    }
}
