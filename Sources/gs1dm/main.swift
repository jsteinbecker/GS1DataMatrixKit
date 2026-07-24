//
//  gs1dm
//  Command line front end for GS1DataMatrixKit.
//
//  Examples:
//    gs1dm "(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER" > label.svg
//    gs1dm --format ascii "0100300005123996172603311 0EXAMPLE"
//    gs1dm --format hri --lenient "]d201003000051239961726033110ABC"
//

import GS1DataMatrixKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let usage = """
gs1dm - GS1 DataMatrix (ECC200) generator

USAGE
  gs1dm [options] <element-string>

  The element string may be concatenated ("0100300005123996...") with or
  without FNC1/GS separators, or bracketed ("(01)00300005123996(17)260331").

OPTIONS
  --format <svg|ascii|pbm|hri|codewords|info>   output format (default: svg)
  --module-size <n>        SVG size of one module in px (default: 4)
  --quiet-zone <n>         quiet zone in modules (default: 1)
  --shape <square|rectangle|any>                (default: square)
  --size <RxC>             force an exact symbol size, e.g. 22x22
  --min-size <RxC>         minimum symbol size
  --fg <colour>            dark module colour (default: #000000)
  --bg <colour|none>       background colour (default: #FFFFFF)
  --separator <char>       treat this character as FNC1 in the input
  --no-optimize            keep the element order as given
  --lenient                structure checks only: no check digits or AI rules
  --allow-unknown-ai       do not fail on AIs outside the syntax dictionary
  --list-ais               print the Application Identifier table and exit
  -h, --help               show this help
"""

func fail(_ message: String) -> Never {
    FileHandleStandardError.write("gs1dm: " + message + "\n")
    exit(1)
}

/// Minimal stderr writer so the tool does not need Foundation.
enum FileHandleStandardError {
    static func write(_ text: String) {
        for byte in Array(text.utf8) {
            _ = fputc(Int32(byte), stderr)
        }
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(arguments.isEmpty ? 1 : 0)
}

if arguments.contains("--list-ais") {
    for ai in GS1SyntaxDictionary.allAIs {
        guard let definition = GS1SyntaxDictionary.definition(for: ai) else { continue }
        let flag = definition.predefinedLength ? "*" : " "
        print("(\(ai))\(flag)\t\(definition.formatSpecification)\t\(definition.title)")
    }
    exit(0)
}

var format = "svg"
var moduleSize = 4.0
var quietZone = 1
var shape = SymbolShape.square
var fixedSize: String? = nil
var minimumRows = 0
var minimumColumns = 0
var foreground = "#000000"
var background: String? = "#FFFFFF"
var separator: Character? = nil
var optimize = true
var validation = GS1ValidationOptions.strict
var input: String? = nil

func value(after index: inout Int, name: String) -> String {
    index += 1
    guard index < arguments.count else { fail("missing value for \(name)") }
    return arguments[index]
}

func parseSize(_ text: String, name: String) -> (rows: Int, columns: Int) {
    let parts = text.lowercased().split(separator: "x")
    guard parts.count == 2, let rows = Int(parts[0]), let columns = Int(parts[1]) else {
        fail("\(name) must look like 22x22")
    }
    return (rows, columns)
}

var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--format": format = value(after: &index, name: "--format")
    case "--module-size":
        let text = value(after: &index, name: "--module-size")
        guard let parsed = Double(text), parsed > 0 else { fail("--module-size must be a positive number") }
        moduleSize = parsed
    case "--quiet-zone":
        let text = value(after: &index, name: "--quiet-zone")
        guard let parsed = Int(text), parsed >= 0 else { fail("--quiet-zone must be zero or more") }
        quietZone = parsed
    case "--shape":
        switch value(after: &index, name: "--shape") {
        case "square": shape = .square
        case "rectangle", "rect": shape = .rectangle
        case "any": shape = .any
        default: fail("--shape must be square, rectangle or any")
        }
    case "--size": fixedSize = value(after: &index, name: "--size")
    case "--min-size":
        let size = parseSize(value(after: &index, name: "--min-size"), name: "--min-size")
        minimumRows = size.rows
        minimumColumns = size.columns
    case "--fg": foreground = value(after: &index, name: "--fg")
    case "--bg":
        let text = value(after: &index, name: "--bg")
        background = (text == "none") ? nil : text
    case "--separator":
        let text = value(after: &index, name: "--separator")
        guard text.count == 1 else { fail("--separator takes a single character") }
        separator = text.first
    case "--no-optimize": optimize = false
    case "--lenient": validation = .lenient
    case "--allow-unknown-ai": validation.allowUnknownAIs = true
    default:
        guard !argument.hasPrefix("--") else { fail("unknown option \(argument)") }
        guard input == nil else { fail("unexpected extra argument '\(argument)'") }
        input = argument
    }
    index += 1
}

guard var elementString = input else { fail("no element string given") }
if let separator {
    elementString = String(elementString.map { $0 == separator ? gs1GroupSeparator : $0 })
}

let options = GS1DataMatrix.Options(validation: validation,
                                    shape: shape,
                                    fixedSize: fixedSize,
                                    minimumRows: minimumRows,
                                    minimumColumns: minimumColumns,
                                    optimizeElementOrder: optimize)

do {
    if format == "hri" {
        let parsed = try GS1DataMatrix.validate(elementString, options: validation)
        for warning in parsed.warnings { FileHandleStandardError.write("warning: " + warning + "\n") }
        print(parsed.hri)
        exit(0)
    }

    let encoded = try GS1DataMatrix.encode(elementString, options: options)
    for warning in encoded.warnings { FileHandleStandardError.write("warning: " + warning + "\n") }

    switch format {
    case "svg":
        let svgOptions = SVGOptions(quietZone: quietZone,
                                    sizing: .moduleSize(moduleSize, unit: "px"),
                                    foreground: foreground,
                                    background: background)
        print(encoded.svg(options: svgOptions), terminator: "")
    case "ascii":
        print(encoded.matrix.asciiArt(quietZone: quietZone))
    case "pbm":
        print(encoded.matrix.pbm(quietZone: quietZone), terminator: "")
    case "codewords":
        print("data: " + encoded.symbol.dataCodewords.map(String.init).joined(separator: " "))
        print("ecc:  " + encoded.symbol.errorCodewords.map(String.init).joined(separator: " "))
    case "info":
        print("HRI:        \(encoded.hri)")
        print("Size:       \(encoded.size) modules")
        print("Capacity:   \(encoded.symbol.payloadCodewordCount)/\(encoded.symbol.attributes.dataCodewords) data codewords")
        print("Error corr: \(encoded.symbol.attributes.errorCodewords) codewords in \(encoded.symbol.attributes.blocks) block(s)")
        for element in encoded.elementString.elements {
            print("  (\(element.ai)) \(element.definition.title.isEmpty ? "-" : element.definition.title): \(element.value)")
        }
    default:
        fail("unknown format '\(format)'")
    }
} catch let error as GS1Error {
    fail(error.description)
} catch let error as DataMatrixError {
    fail(error.description)
} catch {
    fail("\(error)")
}
