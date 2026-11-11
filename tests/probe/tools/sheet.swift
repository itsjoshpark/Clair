// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// sheet <out.png> <columns> <image>...
// Tiles images into a contact sheet, 320 px wide each, labelled with their
// file names.
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let columns = Int(args[2]), columns > 0 else {
  print("usage: sheet <out.png> <columns> <image>...")
  exit(2)
}
let files = Array(args[3...])
let images = files.compactMap { NSImage(contentsOfFile: $0) }
let width = 320.0
let height = images.first.map { width * $0.size.height / $0.size.width } ?? 240
let rows = (images.count + columns - 1) / columns
let canvas = NSImage(size: NSSize(width: width * Double(columns), height: (height + 18) * Double(rows)))
canvas.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: canvas.size).fill()
for (index, image) in images.enumerated() {
  let x = Double(index % columns) * width
  let y = canvas.size.height - Double(index / columns + 1) * (height + 18)
  image.draw(in: NSRect(x: x, y: y, width: width, height: height))
  (URL(fileURLWithPath: files[index]).deletingPathExtension().lastPathComponent as NSString)
    .draw(at: NSPoint(x: x + 4, y: y + height + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
}
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
