// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef COMPONENTS_CONSTRAINED_WINDOW_CLAIR_NATIVE_HOST_MAC_H_
#define COMPONENTS_CONSTRAINED_WINDOW_CLAIR_NATIVE_HOST_MAC_H_

#include <optional>

#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace views {
class Widget;
}

namespace web_modal {
class ModalDialogHost;
}

namespace constrained_window {

// Clair's native browser window (replace-browser-window design D9) hosts
// tab-modal dialogs in an NSView that no Views widget owns, so Chromium can't
// position them and leaves them as free top-level windows in the middle of the
// screen. These place such a dialog at the host's GetDialogPosition(), in
// screen coordinates, and keep it a child window of the host's window, so it
// sits over the page and moves with the window.

// The dialog's screen bounds, or nothing when the host view isn't in a window.
std::optional<gfx::Rect> NativeHostDialogBounds(
    web_modal::ModalDialogHost* dialog_host,
    const gfx::Size& size);

// Sets `widget`'s bounds as NativeHostDialogBounds() says and makes it a child
// window of the host's window. Returns false, doing nothing, when the host view
// isn't in a window.
bool PlaceDialogOverNativeHost(views::Widget* widget,
                               web_modal::ModalDialogHost* dialog_host,
                               const gfx::Size& size);

}  // namespace constrained_window

#endif  // COMPONENTS_CONSTRAINED_WINDOW_CLAIR_NATIVE_HOST_MAC_H_
