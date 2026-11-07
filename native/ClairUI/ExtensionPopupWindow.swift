// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// An extension's popup page, attached to the sidebar button that opened it
/// (design D7). It's a borderless child window rather than an NSPopover,
/// whose material tints the page it hosts (Crest found on macOS 27). Like a
/// popover, a click elsewhere, Esc, or the window moving dismisses it.
final class ExtensionPopupWindow: NSWindow {
  static let cornerRadius: CGFloat = 10
  static let gap: CGFloat = 6
  static let screenMargin: CGFloat = 8

  private weak var parentWindowRef: NSWindow?
  /// The button, in the parent window's coordinates.
  private let anchor: NSRect
  private var onDismiss: (() -> Void)?
  private var monitor: Any?

  init(page: NSView, size: NSSize, parent: NSWindow, anchor: NSRect, onDismiss: @escaping () -> Void) {
    self.parentWindowRef = parent
    self.anchor = anchor
    self.onDismiss = onDismiss
    super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none
    collectionBehavior = [.transient, .ignoresCycle]
    // Nothing of Clair's is drawn behind the page, so what the renderer paints
    // is what shows; the container only rounds the corners.
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    container.wantsLayer = true
    container.layer?.cornerRadius = Self.cornerRadius
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.autoresizesSubviews = true
    page.frame = container.bounds
    page.autoresizingMask = [.width, .height]
    container.addSubview(page)
    contentView = container
    setAccessibilityIdentifier("clair.extensionPopup")
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func present() {
    guard let parent = parentWindowRef else { return }
    position(size: frame.size)
    parent.addChildWindow(self, ordered: .above)
    makeKeyAndOrderFront(nil)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown {
        if event.keyCode == 53 {  // Esc
          self.dismiss()
          return nil
        }
        return event
      }
      if event.window === self {
        return event
      }
      // A click on the button that opened the popup only closes it.
      let onButton =
        event.window === self.parentWindowRef && event.type == .leftMouseDown
        && self.anchor.insetBy(dx: -2, dy: -2).contains(event.locationInWindow)
      self.dismiss()
      return onButton ? nil : event
    }
  }

  func resize(to size: NSSize) {
    position(size: size)
  }

  /// Puts the popup beside the button, kept on screen.
  private func position(size: NSSize) {
    guard let parent = parentWindowRef else { return }
    let button = parent.convertToScreen(anchor)
    let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
    var frame = NSRect(
      x: button.maxX + Self.gap, y: button.maxY - size.height, width: size.width, height: size.height)
    frame.origin.x = min(max(frame.minX, visible.minX + Self.screenMargin), visible.maxX - Self.screenMargin - size.width)
    frame.origin.y = min(max(frame.minY, visible.minY + Self.screenMargin), visible.maxY - Self.screenMargin - size.height)
    setFrame(frame, display: true)
  }

  /// Closes the popup; `notify` tells Chromium the user closed it.
  func dismiss(notify: Bool = true) {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    parent?.removeChildWindow(self)
    orderOut(nil)
    // The page belongs to Chromium; let go of it.
    contentView?.subviews.first?.subviews.forEach { $0.removeFromSuperview() }
    contentView = NSView()
    close()
    let callback = onDismiss
    onDismiss = nil
    if notify {
      callback?()
    }
  }
}
