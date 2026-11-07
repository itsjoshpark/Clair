// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "components/constrained_window/clair_native_host_mac.h"

#import <AppKit/AppKit.h>

#include "components/web_modal/modal_dialog_host.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"

namespace constrained_window {

namespace {

constexpr char kAttacherKey[] = "ClairNativeHostAttacher";

// Makes the dialog a child window of the host's window whenever it's shown.
// Ordering a child window out removes it from its parent, and adding a hidden
// window as a child would order it in, so this attaches on each show. Deletes
// itself with the widget.
class NativeHostAttacher : public views::WidgetObserver {
 public:
  NativeHostAttacher(views::Widget* widget, NSWindow* parent)
      : parent_(parent) {
    widget->AddObserver(this);
    widget->SetNativeWindowProperty(kAttacherKey, this);
  }

  void set_parent(NSWindow* parent) { parent_ = parent; }

  void Attach(views::Widget* widget) {
    NSWindow* dialog = widget->GetNativeWindow().GetNativeNSWindow();
    NSWindow* parent = parent_;
    if (!dialog || !parent || !dialog.visible ||
        dialog.parentWindow == parent) {
      return;
    }
    // A parentless Views dialog floats at the modal panel level, above other
    // apps' windows; as a child it belongs to its browser window instead.
    [dialog.parentWindow removeChildWindow:dialog];
    dialog.level = parent.level;
    [parent addChildWindow:dialog ordered:NSWindowAbove];
  }

  // views::WidgetObserver:
  void OnWidgetVisibilityChanged(views::Widget* widget, bool visible) override {
    if (visible) {
      Attach(widget);
    }
  }

  void OnWidgetDestroying(views::Widget* widget) override {
    widget->RemoveObserver(this);
    widget->SetNativeWindowProperty(kAttacherKey, nullptr);
    delete this;
  }

 private:
  __weak NSWindow* parent_;
};

}  // namespace

std::optional<gfx::Rect> NativeHostDialogBounds(
    web_modal::ModalDialogHost* dialog_host,
    const gfx::Size& size) {
  NSView* view = dialog_host->GetHostView().GetNativeNSView();
  NSWindow* window = view.window;
  if (!window) {
    return std::nullopt;
  }
  // GetDialogPosition() is relative to the host view's top left corner.
  const NSRect host_in_screen =
      [window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
  const gfx::Rect host = gfx::ScreenRectFromNSRect(host_in_screen);
  gfx::Rect bounds(host.origin() + dialog_host->GetDialogPosition(size)
                                       .OffsetFromOrigin(),
                   size);
  // As Chromium does for its own windows: keep the dialog on the display.
  const gfx::Rect work_area = display::Screen::Get()
                                  ->GetDisplayNearestView(gfx::NativeView(view))
                                  .work_area();
  if (!work_area.IsEmpty() && !work_area.Contains(bounds)) {
    bounds.AdjustToFit(work_area);
  }
  return bounds;
}

bool PlaceDialogOverNativeHost(views::Widget* widget,
                               web_modal::ModalDialogHost* dialog_host,
                               const gfx::Size& size) {
  std::optional<gfx::Rect> bounds = NativeHostDialogBounds(dialog_host, size);
  if (!bounds) {
    return false;
  }
  widget->SetBounds(*bounds);
  NSWindow* parent = dialog_host->GetHostView().GetNativeNSView().window;
  auto* attacher = static_cast<NativeHostAttacher*>(
      widget->GetNativeWindowProperty(kAttacherKey));
  if (attacher) {
    attacher->set_parent(parent);
  } else {
    attacher = new NativeHostAttacher(widget, parent);
  }
  attacher->Attach(widget);
  return true;
}

}  // namespace constrained_window
