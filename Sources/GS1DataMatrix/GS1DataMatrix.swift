//
//  GS1DataMatrix.swift
//  Top level API: element string in, validated GS1 DataMatrix out.
//
//  let symbol = try GS1DataMatrix.encode("0100300005123996" + "17260331" + "10EXAMPLELOTNUMBER")
//  print(symbol.svg())
//

public enum GS1DataMatrix {

    public struct Options: Sendable {

        /// How strictly the element string is checked.
        public var validation: GS1ValidationOptions
        /// Which symbol shapes may be used. GS1 application standards call for
        /// square symbols in most cases, so `.square` is the default.
        public var shape: SymbolShape
        /// Force an exact symbol size such as `"22x22"`.
        public var fixedSize: String?
        /// Floor on the automatically chosen size, in modules.
        public var minimumRows: Int
        public var minimumColumns: Int
        /// Move pre-defined length elements to the front, which removes FNC1
        /// separators and often shrinks the symbol.
        public var optimizeElementOrder: Bool
        /// Read the finished symbol back and check the Reed-Solomon syndromes.
        public var verify: Bool

        public init(validation: GS1ValidationOptions = .strict,
                    shape: SymbolShape = .square,
                    fixedSize: String? = nil,
                    minimumRows: Int = 0,
                    minimumColumns: Int = 0,
                    optimizeElementOrder: Bool = true,
                    verify: Bool = true) {
            self.validation = validation
            self.shape = shape
            self.fixedSize = fixedSize
            self.minimumRows = minimumRows
            self.minimumColumns = minimumColumns
            self.optimizeElementOrder = optimizeElementOrder
            self.verify = verify
        }

        public static let `default` = Options()
    }

    /// A validated element string together with the symbol it produced.
    public struct Encoded: Sendable {

        public let elementString: GS1ElementString
        public let symbol: DataMatrixSymbol

        /// `"(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER"`
        public var hri: String { elementString.hri }
        /// Warnings raised while parsing, if any.
        public var warnings: [String] { elementString.warnings }
        /// Symbol size, e.g. `"20x20"`.
        public var size: String { symbol.attributes.name }
        public var matrix: BitMatrix { symbol.matrix }

        public func svg(options: SVGOptions = .default) -> String {
            var options = options
            if options.title == nil { options.title = "GS1 DataMatrix" }
            if options.descriptionText == nil { options.descriptionText = hri }
            return SVGRenderer.render(symbol.matrix, options: options)
        }
    }

    /// Parses, validates and encodes an element string.
    ///
    /// Accepts the concatenated form (`"010030000512399617260331..."`, with or
    /// without FNC1 separators) or the bracketed form
    /// (`"(01)00300005123996(17)260331"`).
    @discardableResult
    public static func encode(_ input: String,
                              options: Options = .default) throws -> Encoded {
        let elementString = try GS1ElementString.parse(input, options: options.validation)
        return try encode(elementString, options: options)
    }

    /// Encodes an element string that has already been parsed or built.
    @discardableResult
    public static func encode(_ elementString: GS1ElementString,
                              options: Options = .default) throws -> Encoded {
        let tokens = elementString.encodationTokens(optimizeOrder: options.optimizeElementOrder)
        let symbol = try DataMatrixEncoder.encode(tokens: tokens,
                                                  shape: options.shape,
                                                  fixedSize: options.fixedSize,
                                                  minimumRows: options.minimumRows,
                                                  minimumColumns: options.minimumColumns,
                                                  verify: options.verify)
        return Encoded(elementString: elementString, symbol: symbol)
    }

    /// Encodes AI/value pairs directly.
    @discardableResult
    public static func encode(_ pairs: [(String, String)],
                              options: Options = .default) throws -> Encoded {
        let elementString = try GS1ElementString.make(pairs, options: options.validation)
        return try encode(elementString, options: options)
    }

    /// One-liner: element string in, SVG out.
    public static func svg(for input: String,
                           options: Options = .default,
                           svgOptions: SVGOptions = .default) throws -> String {
        try encode(input, options: options).svg(options: svgOptions)
    }

    /// Validates without producing a symbol.
    @discardableResult
    public static func validate(_ input: String,
                                options: GS1ValidationOptions = .strict) throws -> GS1ElementString {
        try GS1ElementString.parse(input, options: options)
    }
}
