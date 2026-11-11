// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// measure <subcommand> …
// Pixel measurements of screenshots and recorded frames, in pixels from the
// top-left corner. A <test> picks pixels:
//   white    every channel at least 250
//   blue     blue at least 20 above red (a coloured page, washed or not)
//   accent   blue at least 90 above red (an accent-coloured glyph)
//   dark     luminance below 100
//
//   pixel <png> <x> <y>                    the pixel's r g b a
//   bbox  <png> <test> [x y w h]           the bounding box of matching pixels
//   line  <png> row|col <n> <from> <to>    each pixel's r g b along a row or
//                                          column, from `from` to `to`
//   runs  <png> row|col <n> <test> [min]   runs of matching pixels along a row
//                                          or column, at least `min` long
//   track <dir> <test> [x y w h] [min]     per frame: the bounding box of the
//                                          rows whose longest run is at least
//                                          `min` (default 1) long; prints
//                                          only changes
//   lum   <dir> <x> <y> <w> <h>            per frame: the darkest luminance in
//                                          the rectangle; prints only changes
//   match <dir> <a.png> <b.png> <x> <y> <w> <h>
//                                          per frame: where the rectangle sits
//                                          between the same rectangle in a
//                                          (0) and b (1), e.g. reload and stop;
//                                          prints only changes
import AppKit

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(2)
}

/// An image's pixels as 8-bit RGBA, read once into memory: per-pixel
/// NSBitmapImageRep calls take minutes over a recording's frames.
struct Image {
  let width: Int
  let height: Int
  private let bytes: [UInt8]

  init(_ path: String) {
    guard let source = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fail("measure: can't read \(path)") }
    width = source.width
    height = source.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
          bytesPerRow: source.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
      return true
    }
    if !drawn { fail("measure: can't decode \(path)") }
    self.bytes = bytes
  }

  func rgba(_ x: Int, _ y: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3])]
  }

  /// Whether the pixel passes `test`, without building an array.
  func passes(_ x: Int, _ y: Int, _ test: Test) -> Bool {
    let i = (y * width + x) * 4
    return test(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
  }

  func luminance(_ x: Int, _ y: Int) -> Int {
    let i = (y * width + x) * 4
    return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
  }
}

/// Takes red, green, blue and alpha.
typealias Test = (Int, Int, Int, Int) -> Bool

func test(_ name: String) -> Test {
  switch name {
  case "white": return { r, g, b, _ in r >= 250 && g >= 250 && b >= 250 }
  case "blue": return { r, _, b, a in b - r > 20 && a > 200 }
  case "accent": return { r, _, b, a in b - r > 90 && a > 200 }
  case "dark": return { r, g, b, _ in (r + g + b) / 3 < 100 }
  default: fail("measure: unknown test \(name): white, blue, accent or dark")
  }
}

func int(_ text: String) -> Int {
  guard let value = Int(text) else { fail("measure: \(text) isn't a whole number") }
  return value
}

/// x y w h from `args[at...]`, clipped to the image, or the whole image.
func rect(_ args: [String], at index: Int, in image: Image) -> (Int, Int, Int, Int) {
  guard args.count >= index + 4 else { return (0, 0, image.width, image.height) }
  let x = max(0, int(args[index])), y = max(0, int(args[index + 1]))
  return (x, y, min(int(args[index + 2]), image.width - x), min(int(args[index + 3]), image.height - y))
}

func frames(_ dir: String) -> [String] {
  let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
  let pngs = names.filter { $0.hasSuffix(".png") }.sorted()
  if pngs.isEmpty { fail("measure: no frames in \(dir)") }
  return pngs.map { dir + "/" + $0 }
}

func label(_ path: String) -> String {
  URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

func box(_ b: (Int, Int, Int, Int)) -> String {
  b.2 < 0 ? "none" : "\(b.0) \(b.1) \(b.2 - b.0 + 1) \(b.3 - b.1 + 1)"
}

/// The bounding box of the rows whose longest matching run is at least `min`.
func bbox(_ image: Image, _ match: Test, _ r: (Int, Int, Int, Int), min: Int = 1) -> (Int, Int, Int, Int) {
  var b = (Int.max, Int.max, -1, -1)
  for y in r.1..<(r.1 + r.3) {
    var start = -1, best = (0, -1)
    for x in r.0...(r.0 + r.2) {
      let on = x < r.0 + r.2 && image.passes(x, y, match)
      if on {
        if start < 0 { start = x }
      } else if start >= 0 {
        if x - start > best.1 - best.0 + 1 { best = (start, x - 1) }
        start = -1
      }
    }
    if best.1 >= best.0, best.1 - best.0 + 1 >= min {
      b = (Swift.min(b.0, best.0), Swift.min(b.1, y), max(b.2, best.1), max(b.3, y))
    }
  }
  return b
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  fail("usage: measure pixel|bbox|runs|track|lum|match … (see the comment at the top of measure.swift)")
}

switch command {
case "pixel" where args.count == 4:
  let p = Image(args[1]).rgba(int(args[2]), int(args[3]))
  print(p.map(String.init).joined(separator: " "))

case "bbox" where args.count >= 3:
  let image = Image(args[1])
  print(box(bbox(image, test(args[2]), rect(args, at: 3, in: image))))

case "line" where args.count == 6:
  let image = Image(args[1])
  let alongRow = args[2] == "row"
  guard alongRow || args[2] == "col" else { fail("measure line: row or col") }
  let n = int(args[3]), from = int(args[4]), to = int(args[5])
  for i in stride(from: from, through: to, by: from <= to ? 1 : -1) {
    let p = alongRow ? image.rgba(i, n) : image.rgba(n, i)
    print(i, p[0], p[1], p[2])
  }

case "runs" where args.count >= 5:
  let image = Image(args[1])
  let alongRow = args[2] == "row"
  guard alongRow || args[2] == "col" else { fail("measure runs: row or col") }
  let n = int(args[3]), match = test(args[4]), minimum = args.count > 5 ? int(args[5]) : 1
  let length = alongRow ? image.width : image.height
  var runs: [String] = [], start = -1
  for i in 0...length {
    let on = i < length && (alongRow ? image.passes(i, n, match) : image.passes(n, i, match))
    if on {
      if start < 0 { start = i }
    } else if start >= 0 {
      if i - start >= minimum { runs.append("\(start)-\(i - 1)") }
      start = -1
    }
  }
  print(runs.isEmpty ? "none" : runs.joined(separator: " "))

case "track" where args.count >= 3:
  let match = test(args[2])
  var previous = ""
  for path in frames(args[1]) {
    let image = Image(path)
    let r = rect(args, at: 3, in: image)
    let minimum = args.count == 8 ? int(args[7]) : (args.count == 4 ? int(args[3]) : 1)
    let line = box(bbox(image, match, r, min: minimum))
    if line != previous { print(label(path), line) }
    previous = line
  }

case "lum" where args.count == 6:
  var previous = ""
  for path in frames(args[1]) {
    let image = Image(path)
    let r = rect(args, at: 2, in: image)
    var darkest = 255
    for y in r.1..<(r.1 + r.3) { for x in r.0..<(r.0 + r.2) { darkest = min(darkest, image.luminance(x, y)) } }
    let line = String(darkest)
    if line != previous { print(label(path), line) }
    previous = line
  }

case "match" where args.count == 8:
  let a = Image(args[2]), b = Image(args[3])
  let r = rect(args, at: 4, in: a)
  func pixels(_ image: Image) -> [Double] {
    var values: [Double] = []
    for y in r.1..<(r.1 + r.3) { for x in r.0..<(r.0 + r.2) { values.append(Double(image.luminance(x, y))) } }
    return values
  }
  let from = pixels(a), to = pixels(b)
  var previous = ""
  for path in frames(args[1]) {
    let values = pixels(Image(path))
    var along = 0.0, length = 0.0
    for i in values.indices {
      let d = to[i] - from[i]
      along += (values[i] - from[i]) * d
      length += d * d
    }
    let line = length > 0 ? String(format: "%.2f", along / length) : "same"
    if line != previous { print(label(path), line) }
    previous = line
  }

default:
  fail("measure: bad arguments for \(command) (see the comment at the top of measure.swift)")
}
