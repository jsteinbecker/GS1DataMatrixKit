# GS1DataMatrixKit

A self-contained GS1 DataMatrix (ECC200) generator in Swift. No third-party
dependencies, and no Foundation — the library target uses only the Swift
standard library, so it builds anywhere Swift does (iOS, macOS, Linux, Vapor,
embedded-ish server contexts, WASM).

Takes a GS1 element string, validates it against the GS1 General
Specifications, and emits a vector symbol.

```swift
import GS1DataMatrixKit

let label = try GS1DataMatrix.encode("(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER")

print(label.size)   // "22x22"
print(label.hri)    // "(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER"
let svg = label.svg()
```

---

## What it does

**Validation** — before anything is encoded, the element string is parsed and
checked against the GS1 Barcode Syntax Dictionary, which is embedded verbatim
in `GS1SyntaxDictionaryData.swift` (541 AIs):

- AI recognition and field splitting, with or without FNC1/GS separators
- pre-defined vs. variable length AIs, so separators are required exactly where
  GS1 requires them
- component-level length and character-set rules (`N`, CSET 82, CSET 39,
  base64url)
- mod-10 check digits: GTIN, SSCC, GLN, GSIN, GSRN, GRAI, GDTI, GCN, ITIP
- the mod-1021 check **character pair** for GMN and MUDI (AI 8013, 8014)
- date and time validity (`yymmd0`, `yymmdd`, `yyyymmdd`, `hhmi`, `hh`, `mi`, `ss`)
- structural content rules: `pieceoftotal`, `latitude`/`longitude`, `iban`
  (mod-97), `posinseqslash`, `winding`, `yesno`, `zero`/`nonzero`,
  `nozeroprefix`, `hasnondigit`, percent-encoding, ISO code shapes
- mandatory AI associations (`req=`) and invalid pairings (`ex=`), including
  wildcard patterns like `31nn`
- repeated-AI detection

**Encoding** — full ISO/IEC 16022 ECC200:

- ASCII encodation with digit-pair compaction, FNC1 (codeword 232) in the first
  position to flag GS1 mode, and the 253-state pad randomiser
- all 24 square sizes (10×10 … 144×144) and all 6 rectangular sizes
  (8×18 … 16×48), including the interleaved Reed-Solomon blocks of the large
  symbols and the 156/155 block split of 144×144
- Reed-Solomon over GF(256) with the 0x12D field polynomial
- Annex F symbol character placement with all four corner cases
- finder pattern and clock track per data region
- an optional self-check that reads the finished symbol back out of the module
  grid and confirms every Reed-Solomon block has zero syndromes (on by default)

**Output** — `BitMatrix` plus renderers:

- SVG, one module per viewBox unit so it scales losslessly; dark modules are
  merged into horizontal runs in a single `<path>`
- ASCII art and PBM for debugging and piping into image tools

---

## Install

```swift
.package(url: "…/GS1DataMatrixKit.git", from: "1.0.0")
```

Or drop `Sources/GS1DataMatrix/` into an existing target.

---

## Using it

### Input formats

All three are accepted:

```swift
try GS1DataMatrix.encode("0100300005123996" + "17260331" + "10EXAMPLELOTNUMBER")
try GS1DataMatrix.encode("(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER")
try GS1DataMatrix.encode([("01", "00300005123996"), ("17", "260331"), ("10", "EXAMPLELOTNUMBER")])
```

A leading symbology identifier (`]d2`) is stripped, and `\u{1D}` group
separators from a scanner are understood.

### Options

```swift
var options = GS1DataMatrix.Options()
options.shape = .square              // .square (default), .rectangle, .any
options.fixedSize = "32x32"          // force an exact size
options.minimumRows = 20             // or just set a floor
options.optimizeElementOrder = true  // pre-defined length AIs first: fewer separators
options.verify = true                // read the symbol back and check syndromes
options.validation = .strict         // or .lenient

let label = try GS1DataMatrix.encode(input, options: options)
```

### SVG

```swift
let svg = label.svg(options: SVGOptions(
    quietZone: 1,                                  // GS1 minimum for DataMatrix
    sizing: .moduleSize(4, unit: "px"),            // or .total(...) / .responsive
    foreground: "#000000",
    background: "#FFFFFF"                          // nil for transparent
))
```

`.responsive` omits `width`/`height` entirely, which is what you usually want
when embedding the symbol in HTML or scaling it to a print area.

### Validation without encoding

```swift
let parsed = try GS1DataMatrix.validate(scannedString)
for element in parsed.elements {
    print(element.ai, element.title, element.value)
}
```

### Errors

Every failure is a typed error with a printable explanation:

```swift
do {
    _ = try GS1DataMatrix.encode("01003000051239971726033110EXAMPLELOTNUMBER")
} catch let error as GS1Error {
    print(error)
    // AI (01) value '00300005123997' failed the csum check:
    // check digit is 7 but should be 6.
}
```

> Note on the example in the original request: `00300005123997` has an
> incorrect check digit. `0030000512399` computes to **6**, so the GTIN is
> `00300005123996`. That is exactly the kind of thing this package is meant to
> catch before a label reaches a printer.

---

## Command line

```
swift run gs1dm "(01)00300005123996(17)260331(10)EXAMPLELOTNUMBER" > label.svg
swift run gs1dm --format ascii "(01)00300005123996(21)SERIAL123"
swift run gs1dm --format info  "(01)00300005123996(10)LOT"
swift run gs1dm --list-ais
```

```
--format <svg|ascii|pbm|hri|codewords|info>   output format (default: svg)
--module-size <n>     SVG size of one module in px (default: 4)
--quiet-zone <n>      quiet zone in modules (default: 1)
--shape <square|rectangle|any>
--size <RxC>          force an exact symbol size, e.g. 22x22
--min-size <RxC>      minimum symbol size
--fg / --bg <colour>  colours; --bg none for transparent
--separator <char>    treat this character as FNC1 in the input
--no-optimize         keep the element order as given
--lenient             structure checks only
--allow-unknown-ai    do not fail on AIs outside the syntax dictionary
```

---

## Conformance and verification

The encoder was checked module-for-module against an independent ECC200
implementation across **all 30 symbol sizes** — 448 square and 138 rectangular
cases covering exact-fit payloads, padded payloads, digits, alphanumerics and
extended ASCII. The two agree everywhere except where the other implementation
computes the pad randomiser as `(130 + (149·P mod 253)) mod 254`, which turns a
legitimate pad value of 254 into 0. ISO/IEC 16022 clause 5.2.3 (and ZXing)
specify `tempVariable ≤ 254 ? tempVariable : tempVariable − 254`, which is what
this package does.

The test suite additionally proves, for every symbol size, that:

- the attribute table is internally consistent (region geometry reproduces the
  symbol size; mapping-matrix bits equal codeword bits, ± the 4-module corner)
- placement is a bijection — every bit of every codeword lands in exactly one
  module, nothing is written twice
- a full encode/decode round trip through the module grid leaves all
  Reed-Solomon syndromes at zero

Check digit algorithms are tested against the worked examples in the GS1
General Specifications, including the GMN check character pair example
`1987654Ad4X4bL5ttr2310c` → `2K`.

### Known limitations

- **Encodation is ASCII only.** That is fully conformant and optimal for
  numeric GS1 data (two digits per codeword), but a long alphabetic lot or
  serial would be a few codewords smaller under C40/Text encodation. Adding a
  C40/Text mode with the Annex P lookahead would be the next optimisation.
- **Five linters are no-ops**: `gcppos1`, `gcppos2`, `packagetype`,
  `couponcode`, `couponposoffer`. They need the GS1 Company Prefix list and
  code lists that are not part of the syntax dictionary. Supply your own via
  `GS1ValidationOptions.additionalLinters`. A test asserts that every linter
  referenced by the table is either implemented or explicitly listed here, so
  this list cannot silently drift.
- **ISO 3166 / 4217 codes are checked for shape, not membership** (three
  digits, not `000`). Plug in a real code list the same way if you need it.
- **February is allowed 29 days** in `YYMMDD` fields, because the century is
  not knowable from two-digit years alone.
- A variable-length field that is not followed by an FNC1 separator swallows
  everything to the end of the string. That is inherent to the format, not a
  parser bug; `optimizeElementOrder` avoids creating such strings.
- GS1 Digital Link URIs are parsed for metadata only (`dlpkey` attributes are
  retained) but are not accepted as input.

### Updating the AI table

`GS1SyntaxDictionaryData.swift` holds the GS1 Barcode Syntax Dictionary in its
original line format. To update, replace the string with the data lines of a
newer release from <https://github.com/gs1/gs1-syntax-dictionary>; comments and
blank lines are ignored, so the file can be pasted in unmodified.

---

## Layout

```
Sources/GS1DataMatrix/
  GS1DataMatrix.swift             top-level API
  GS1ElementString.swift          parsing, validation, FNC1 placement
  GS1ApplicationIdentifier.swift  AI model + syntax dictionary line parser
  GS1SyntaxDictionaryData.swift   the embedded GS1 table
  GS1Linters.swift                content validation routines
  GS1CheckDigit.swift             mod 10 and the mod 1021 check character pair
  GS1CharacterSets.swift          CSET 82 / 39 / 64
  DataMatrixEncoder.swift         ECC200 symbol construction + self check
  Encodation.swift                ASCII encodation and padding
  ReedSolomon.swift               GF(256) arithmetic and error correction
  Placement.swift                 ISO 16022 Annex F placement
  SymbolAttributes.swift          the 30 ECC200 symbol sizes
  BitMatrix.swift                 module grid, ASCII art, PBM
  SVGRenderer.swift               vector output
Sources/gs1dm/main.swift          command line tool
Tests/GS1DataMatrixKitTests/      XCTest suite
```

## Licence

The embedded GS1 Barcode Syntax Dictionary is © BWIPP project, Zint Project and
GS1 AISBL, under the Apache License 2.0. The Swift code is yours to license as
you see fit.
