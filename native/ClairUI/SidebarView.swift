// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

import ClairHost
import SwiftUI

/// What the sidebar asks the window to do.
@MainActor
protocol SidebarActions: AnyObject {
  func activate(tab: TabID)
  func close(tab: TabID)
  func newTab()
}

/// The sidebar (design D12). For now: the tab list, unstyled.
struct SidebarView: View {
  let model: BrowserWindowModel
  weak var actions: (any SidebarActions)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Room for the window controls.
      Color.clear.frame(height: 44)
      if model.profileKind == .incognito {
        Text("Incognito")
          .font(.headline)
          .padding(.horizontal, 12)
      }
      Button("New Tab") { actions?.newTab() }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("clair.newTabRow")
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(model.tabs, id: \.tabID) { tab in
            TabRow(tab: tab, isActive: tab.tabID == model.activeTabID)
              .contentShape(Rectangle())
              .onTapGesture { actions?.activate(tab: tab.tabID) }
          }
        }
        .padding(.horizontal, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct TabRow: View {
  let tab: any ClairTab
  let isActive: Bool

  var body: some View {
    HStack(spacing: 8) {
      if let favicon = tab.favicon {
        Image(nsImage: favicon).resizable().frame(width: 16, height: 16)
      } else {
        Image(systemName: "globe").frame(width: 16, height: 16)
      }
      Text(tab.title).lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .frame(height: 32)
    .background(isActive ? Color.primary.opacity(0.1) : Color.clear, in: .rect(cornerRadius: 8))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("clair.tabRow")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}
