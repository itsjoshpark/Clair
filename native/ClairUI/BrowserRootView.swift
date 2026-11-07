// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import SwiftUI

/// The native window's content view (design D4): one translucent material
/// behind everything, the sidebar at the leading edge, and the card with the
/// page. Laid out in AppKit, so a resize lays out the page directly.
final class BrowserRootView: NSView {
  let background = NSVisualEffectView()
  let card = PageCardView()
  let sidebar: NSView
  private let model: BrowserWindowModel

  init(model: BrowserWindowModel, sidebar: NSView) {
    self.model = model
    self.sidebar = sidebar
    super.init(frame: .zero)
    background.material = .sidebar
    background.blendingMode = .behindWindow
    background.state = .followsWindowActiveState
    addSubview(background)
    addSubview(sidebar)
    addSubview(card)
    sidebar.setAccessibilityIdentifier("clair.sidebar")
    observeModel()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override var isFlipped: Bool { true }

  /// Lays out again whenever what the layout reads changes.
  private func observeModel() {
    withObservationTracking {
      _ = model.sidebar
      _ = model.isPageFullscreen
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.needsLayout = true
        self?.observeModel()
      }
    }
  }

  var currentLayout: WindowLayout {
    WindowLayout(size: bounds.size, sidebar: model.sidebar, isPageFullscreen: model.isPageFullscreen)
  }

  override func layout() {
    super.layout()
    background.frame = bounds
    let layout = currentLayout
    sidebar.frame = layout.sidebar
    sidebar.isHidden = model.sidebar.isHidden || model.isPageFullscreen
    card.frame = layout.card
    card.isBare = model.isPageFullscreen
  }
}
