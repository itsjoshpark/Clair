// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// crop <in.png> <out.png> <x> <y> <width> <height>
// Crops in pixels from the top-left corner. (sips --cropOffset centres the
// crop instead.)
import AppKit

let args = CommandLine.arguments
guard args.count == 7, let x = Double(args[3]), let y = Double(args[4]), let w = Double(args[5]),
  let h = Double(args[6])
else {
  print("usage: crop <in.png> <out.png> <x> <y> <width> <height>")
  exit(2)
}
let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[1])))!
guard let cropped = rep.cgImage?.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
  print("crop: the rectangle is outside the image")
  exit(1)
}
try NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])!
  .write(to: URL(fileURLWithPath: args[2]))
