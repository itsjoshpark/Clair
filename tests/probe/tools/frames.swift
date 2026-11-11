// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// frames <movie> <out dir> [step s] [from s] [to s] [max width px]
// Saves a recording's frames as f<ms>.png, every `step` seconds (default
// 1/60) from `from` to `to` (default the whole movie). Frames come out at
// the movie's size, 2 px per point on a Retina display, unless `max width`
// is smaller.
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
  print("usage: frames <movie> <out dir> [step] [from] [to] [max width]")
  exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let out = args[2]
let step = args.count > 3 ? Double(args[3])! : 1.0 / 60
let from = args.count > 4 ? Double(args[4])! : 0
let duration = CMTimeGetSeconds(try await asset.load(.duration))
let to = args.count > 5 ? min(Double(args[5])!, duration) : duration
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
if args.count > 6 { generator.maximumSize = CGSize(width: Double(args[6])!, height: 0) }
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
var time = from
while time <= to {
  if let (image, _) = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!
      .write(to: URL(fileURLWithPath: String(format: "%@/f%05.0f.png", out, time * 1000)))
  }
  time += step
}
