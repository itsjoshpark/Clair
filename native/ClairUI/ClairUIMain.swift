// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import Foundation

/// ClairUI.framework's principal class (`NSPrincipalClass`): the entry point
/// Chromium calls once it has built the main menu (`ClairHost.h`).
@objc(ClairUIMain)
final class ClairUIMain: NSObject, ClairUIEntryPoint {
  static func start(host: any ClairHost) {
    NativeLayer.start(host: host)
  }
}
