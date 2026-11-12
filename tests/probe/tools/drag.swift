// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// drag <x1> <y1> <x2> <y2>
//
// Drags with the mouse's own events, in screen points (as `probe.sh send tree`
// prints frames), at a hand's speed: press, hold, move in steps, hold, let go.
// For SwiftUI drag gestures in Clair, which the probe's XCUITest `drag`
// doesn't reach. It moves the real pointer, and the shell it runs from needs
// permission to post events (Privacy & Security > Accessibility). Bring the
// app forward first (`probe.sh send activate`). Arc ignores these events.

import CoreGraphics
import Foundation

let numbers = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard numbers.count == 4 else {
  FileHandle.standardError.write("usage: drag <x1> <y1> <x2> <y2>\n".data(using: .utf8)!)
  exit(2)
}
guard CGPreflightPostEventAccess() else {
  FileHandle.standardError.write("drag: this shell may not post events (Privacy & Security > Accessibility)\n".data(using: .utf8)!)
  exit(1)
}
let from = CGPoint(x: numbers[0], y: numbers[1])
let to = CGPoint(x: numbers[2], y: numbers[3])

func post(_ type: CGEventType, _ point: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
}

post(.mouseMoved, from)
usleep(200_000)
post(.leftMouseDown, from)
usleep(300_000)
let steps = 30
for step in 1...steps {
  let t = Double(step) / Double(steps)
  post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
  usleep(16_000)
}
usleep(300_000)
post(.leftMouseUp, to)
