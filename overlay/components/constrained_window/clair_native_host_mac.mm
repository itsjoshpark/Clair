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

namespace constrained_window {

bool IsNativeHostView(gfx::NativeView parent_view) {
  NSView* view = parent_view.GetNativeNSView();
  return view.window && !views::Widget::GetWidgetForNativeView(parent_view);
}

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
  // Views keeps the dialog a child window of the browser window
  // (ui/views/cocoa/clair_native_parent.mm).
  widget->SetBounds(*bounds);
  return true;
}

}  // namespace constrained_window
