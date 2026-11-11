// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// windows <owner name or pid>
// Lists an app's normal windows, on screen or not: window ID, frame in
// screen points (top-left origin), whether it's on screen, and title, for
// screencapture -l and -R. A process ID picks one copy of an app.
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 2 else {
  print("usage: windows <owner name, e.g. Arc or Clair, or a process ID>")
  exit(2)
}
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let pid = Int(args[1])
for window in list
where (pid.map { (window[kCGWindowOwnerPID as String] as? Int) == $0 }
  ?? ((window[kCGWindowOwnerName as String] as? String) == args[1]))
  && (window[kCGWindowLayer as String] as? Int) == 0
{
  let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
  let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) == true
  print(
    window[kCGWindowNumber as String] ?? "?",
    "\(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)),\(Int(bounds["Width"] ?? 0)),\(Int(bounds["Height"] ?? 0))",
    onScreen ? "on screen" : "off screen",
    window[kCGWindowName as String] as? String ?? "")
}
