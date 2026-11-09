// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit

/// An extension's popup page, in a small titled window that first opens beside
/// the sidebar button that opened it (arc-extension-experience D6). It's a
/// child window rather than an NSPopover, whose material tints the page it
/// hosts (Crest found on macOS 27). A click elsewhere, Esc, its close button,
/// or the browser window moving dismisses it.
final class ExtensionPopupWindow: NSWindow {
  static let gap: CGFloat = 6
  static let screenMargin: CGFloat = 8

  private weak var parentWindowRef: NSWindow?
  /// The button, in the parent window's coordinates.
  private let anchor: NSRect
  private var onDismiss: (() -> Void)?
  private var monitor: Any?

  init(page: NSView, size: NSSize, name: String, parent: NSWindow, anchor: NSRect, onDismiss: @escaping () -> Void) {
    self.parentWindowRef = parent
    self.anchor = anchor
    self.onDismiss = onDismiss
    super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.transient, .ignoresCycle]
    // Only VoiceOver and the window list read the name.
    title = name
    titleVisibility = .hidden
    let container = NSView(frame: NSRect(origin: .zero, size: size))
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
    placeBesideAnchor()
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

  /// The close button: the same as any other way the user closes it.
  override func performClose(_ sender: Any?) {
    dismiss()
  }

  /// The page resized itself: the window keeps its top-leading corner, which
  /// may not be beside the button any more if the user dragged it.
  func resize(to size: NSSize) {
    let outer = frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    let frame = NSRect(x: frame.minX, y: frame.maxY - outer.height, width: outer.width, height: outer.height)
    setFrame(onScreen(frame), display: true)
  }

  /// Puts the popup beside the button.
  private func placeBesideAnchor() {
    guard let parent = parentWindowRef else { return }
    let button = parent.convertToScreen(anchor)
    let size = frame.size
    let frame = NSRect(x: button.maxX + Self.gap, y: button.maxY - size.height, width: size.width, height: size.height)
    setFrame(onScreen(frame), display: true)
  }

  private func onScreen(_ frame: NSRect) -> NSRect {
    let visible = (screen ?? parentWindowRef?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
    var frame = frame
    frame.origin.x = min(max(frame.minX, visible.minX + Self.screenMargin), visible.maxX - Self.screenMargin - frame.width)
    frame.origin.y = min(max(frame.minY, visible.minY + Self.screenMargin), visible.maxY - Self.screenMargin - frame.height)
    return frame
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
    contentView?.subviews.forEach { $0.removeFromSuperview() }
    contentView = NSView()
    close()
    let callback = onDismiss
    onDismiss = nil
    if notify {
      callback?()
    }
  }
}
