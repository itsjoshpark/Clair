// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef UI_VIEWS_COCOA_CLAIR_NATIVE_PARENT_H_
#define UI_VIEWS_COCOA_CLAIR_NATIVE_PARENT_H_

#include "ui/gfx/native_ui_types.h"

namespace views {

class Widget;

// Clair's native browser window (replace-browser-window design D9) is an
// NSWindow that no Views widget owns. A widget parented to one of its views,
// such as a permission prompt, page info or a dialog, would otherwise be a
// free top-level window that the browser window can cover and that doesn't
// move with it. While the widget shows, this keeps it a child window of the
// browser window. It does nothing for any other parent, so Chromium's own
// windows behave as before.
void ClairAttachToNativeParent(Widget* widget, gfx::NativeView parent);

}  // namespace views

#endif  // UI_VIEWS_COCOA_CLAIR_NATIVE_PARENT_H_
