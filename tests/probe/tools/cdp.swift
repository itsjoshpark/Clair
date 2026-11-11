// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// cdp <port> <url part> <method> [<params json>]...
// Sends DevTools protocol commands, in order, to the first page whose URL
// contains `url part`, in a Clair started with launch-clair.sh --port, and
// prints each reply. Each command is a method followed by its params, e.g.
//   cdp 9333 colour.html Input.dispatchMouseEvent '{"type":"mousePressed",…}'
// It reaches only that copy of Clair, so it's safe while the owner's own
// Clair runs, unlike the probe. `click <x> <y> [modifiers]` stands for the
// three mouse events of a click at CSS pixels (x, y); modifiers is CDP's
// bit mask: 1 Alt, 2 Ctrl, 4 Meta (Cmd), 8 Shift.
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, let port = Int(args[0]) else {
  fail("usage: cdp <port> <url part> <method> [<params json>] | click <x> <y> [modifiers] ...")
}

// The commands: (method, params) pairs, with `click` expanded.
var commands: [(String, [String: Any])] = []
var index = 2
while index < args.count {
  let word = args[index]
  if word == "click" {
    guard index + 2 < args.count, let x = Double(args[index + 1]), let y = Double(args[index + 2]) else {
      fail("cdp: click <x> <y> [modifiers]")
    }
    var modifiers = 0
    index += 3
    if index < args.count, let value = Int(args[index]) {
      modifiers = value
      index += 1
    }
    for type in ["mouseMoved", "mousePressed", "mouseReleased"] {
      var params: [String: Any] = ["type": type, "x": x, "y": y, "modifiers": modifiers]
      if type != "mouseMoved" {
        params["button"] = "left"
        params["clickCount"] = 1
      }
      commands.append(("Input.dispatchMouseEvent", params))
    }
    continue
  }
  var params: [String: Any] = [:]
  if index + 1 < args.count, args[index + 1].hasPrefix("{") {
    guard let data = args[index + 1].data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { fail("cdp: \(args[index + 1]) isn't a JSON object") }
    params = object
    index += 1
  }
  commands.append((word, params))
  index += 1
}

// The page's WebSocket.
let list = URL(string: "http://127.0.0.1:\(port)/json/list")!
guard let data = try? Data(contentsOf: list),
  let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
else { fail("cdp: nothing answers on port \(port); launch Clair with launch-clair.sh --port \(port)") }
guard
  let target = targets.first(where: {
    ($0["type"] as? String) == "page" && (($0["url"] as? String) ?? "").contains(args[1])
  }),
  let socketURL = (target["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:))
else { fail("cdp: no page whose URL contains \(args[1])") }

let socket = URLSession.shared.webSocketTask(with: socketURL)
socket.resume()
for (id, command) in commands.enumerated() {
  let message: [String: Any] = ["id": id + 1, "method": command.0, "params": command.1]
  let text = String(data: try JSONSerialization.data(withJSONObject: message), encoding: .utf8)!
  try await socket.send(.string(text))
  // Skip events until this command's reply.
  while true {
    guard case .string(let reply) = try await socket.receive() else { continue }
    guard let object = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any],
      (object["id"] as? Int) == id + 1
    else { continue }
    print(reply)
    break
  }
}
socket.cancel(with: .normalClosure, reason: nil)
