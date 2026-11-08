// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import AppKit
import Observation
import SwiftUI

/// Arc's popup in the card's top-trailing corner (design D18): "Copied
/// Current URL" with a share button, and the full-screen notice. It springs
/// in from its top centre and shrinks back there.
struct Notice: Equatable, Identifiable {
  let id = UUID()
  var text: String
  /// The URL the share button shares, or nil for no share button.
  var shareURL: URL?
  var identifier: String
}

/// What the popup shows, and whether it's in (for its animation).
@MainActor
@Observable
final class NoticeState {
  private(set) var notice: Notice?
  private(set) var isShown = false
  @ObservationIgnored private var hiding: Task<Void, Never>?

  /// Arc keeps "Copied Current URL" up for about 5 s.
  static let copiedDuration: Duration = .seconds(5)
  /// Arc's: in with a slight overshoot in about 0.2 s, out in about 0.17 s.
  static let showAnimation = Animation.spring(response: 0.28, dampingFraction: 0.72)
  static let hideAnimation = Animation.easeIn(duration: 0.17)

  /// Shows `notice`, replacing any other, and hides it after `duration`, or
  /// keeps it until `hide()` when `duration` is nil.
  func show(_ notice: Notice, for duration: Duration?) {
    hiding?.cancel()
    hiding = nil
    if self.notice != nil, isShown {
      self.notice = notice
    } else {
      self.notice = notice
      isShown = false
      // Let the window draw it small first, then spring in.
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(30))
        guard let self, self.notice?.id == notice.id else { return }
        withAnimation(Self.showAnimation) { self.isShown = true }
      }
    }
    if let duration {
      hiding = Task { [weak self] in
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled, let self, self.notice?.id == notice.id else { return }
        self.hide()
      }
    }
  }

  /// Shrinks the popup away, then removes it.
  func hide() {
    hiding?.cancel()
    hiding = nil
    guard let notice else { return }
    withAnimation(Self.hideAnimation) { isShown = false }
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard let self, self.notice?.id == notice.id, !self.isShown else { return }
      self.notice = nil
    }
  }
}

/// The popup, measured from Arc: 46 pt high with a 12 pt corner radius, the
/// text 14 pt semibold 13 pt in, and a 31 pt share button 8 pt from the end.
/// Arc tints it with the Space's colour; Clair with the accent colour.
struct NoticePopupView: View {
  let state: NoticeState
  var share: ((URL) -> Void)?

  /// Room around the popup for its shadow.
  static let margin: CGFloat = 12

  var body: some View {
    if let notice = state.notice {
      HStack(spacing: 13) {
        message(notice.text)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(notice.text.replacingOccurrences(of: "|", with: ""))
          .accessibilityIdentifier(notice.identifier)
        if let url = notice.shareURL {
          shareButton(url)
        }
      }
      .padding(.leading, 13)
      .padding(.trailing, notice.shareURL == nil ? 13 : 8)
      .frame(height: 46)
      .background { background }
      .scaleEffect(state.isShown ? 1 : 0.1, anchor: .top)
      .opacity(state.isShown ? 1 : 0)
      .padding(Self.margin)
      .fixedSize()
      .accessibilityElement(children: .contain)
    }
  }

  /// The text, with keys Chromium marks as "|Esc|" drawn as key caps.
  private func message(_ text: String) -> some View {
    let parts = text.components(separatedBy: "|")
    return HStack(spacing: 4) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index % 2 == 1 {
          KeyCap(key: part)
        } else if !part.trimmingCharacters(in: .whitespaces).isEmpty {
          Text(part.trimmingCharacters(in: .whitespaces))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      }
    }
  }

  private var background: some View {
    let accent = Color.accentColor
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    let top = OverlayStyle.background.mix(with: accent, by: 0.18)
    let bottom = OverlayStyle.background.mix(with: accent, by: 0.26)
    return shape
      .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
      .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
  }

  private func shareButton(_ url: URL) -> some View {
    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    let fill = OverlayStyle.background.mix(with: Color.accentColor, by: 0.08)
    return Button {
      share?(url)
    } label: {
      // The arrow makes the glyph look low when it's centred; Arc sets it
      // about 1 pt above the middle of the key's face.
      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 14, weight: .medium))
        .offset(y: -1)
        .frame(width: 31, height: 29)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
        // A key cap's depth below the face, as Arc draws the button.
        .background(shape.fill(Color.primary.opacity(0.16)).offset(y: 2))
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .tooltip("Share")
    .accessibilityLabel("Share")
  }
}
