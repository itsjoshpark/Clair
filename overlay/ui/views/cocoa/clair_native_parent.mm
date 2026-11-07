// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "ui/views/cocoa/clair_native_parent.h"

#import <AppKit/AppKit.h>

#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"

namespace views {

namespace {

// Ordering a child window out removes it from its parent, and adding a hidden
// window as a child would order it in, so the widget is attached on each
// show. Deletes itself with the widget.
class NativeParentAttacher : public WidgetObserver {
 public:
  NativeParentAttacher(Widget* widget, NSWindow* parent) : parent_(parent) {
    widget->AddObserver(this);
    Attach(widget);
  }

  void Attach(Widget* widget) {
    NSWindow* child = widget->GetNativeWindow().GetNativeNSWindow();
    NSWindow* parent = parent_;
    if (!child || !parent || !child.visible || child.parentWindow == parent) {
      return;
    }
    // A parentless window-modal dialog floats at the modal panel level, above
    // other apps' windows; as a child it belongs to its browser window.
    if (child.level == NSModalPanelWindowLevel) {
      child.level = parent.level;
    }
    [child.parentWindow removeChildWindow:child];
    [parent addChildWindow:child ordered:NSWindowAbove];
  }

  // WidgetObserver:
  void OnWidgetVisibilityChanged(Widget* widget, bool visible) override {
    if (visible) {
      Attach(widget);
    }
  }

  void OnWidgetDestroying(Widget* widget) override {
    widget->RemoveObserver(this);
    delete this;
  }

 private:
  __weak NSWindow* parent_;
};

}  // namespace

void ClairAttachToNativeParent(Widget* widget, gfx::NativeView parent) {
  NSWindow* window = parent.GetNativeNSView().window;
  static Class native_window_class = NSClassFromString(@"ClairNativeWindow");
  if (!widget || !native_window_class ||
      ![window isKindOfClass:native_window_class]) {
    return;
  }
  new NativeParentAttacher(widget, window);
}

}  // namespace views
