# dmgbuild settings for Clair's DMG (style-release-dmg design D3).
#
# dmgbuild runs this file with `defines` holding package.sh's -D values, each an
# absolute path:
#   app         the signed Clair.app to put on the volume
#   icon        the volume icon: that app's own app.icns
#   background  background.tiff, with its 1x and 2x images
#   layout      layout.json, which make_background.py also reads
#
# dmgbuild reads the names below that it knows; the rest are ignored.

import json
import os


def _path(name):
    value = defines.get(name, "")  # noqa: F821 (dmgbuild provides defines)
    if not os.path.isabs(value) or not os.path.exists(value):
        raise ValueError("settings.py needs -D %s=<absolute path to an existing file>, got %r" % (name, value))
    return value


app = _path("app")
with open(_path("layout")) as _f:
    _layout = json.load(_f)
_name = os.path.basename(app.rstrip("/"))
if sorted(_layout["icons"]) != sorted([_name, "Applications"]):
    raise ValueError("layout.json must place exactly %s and Applications" % _name)

format = "ULFO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: it sets Finder info on the app bundle, which fails
# codesign --verify --strict. Finder hides ".app" by itself.
icon = _path("icon")
background = _path("background")

default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
arrange_by = None
label_pos = "bottom"
icon_size = _layout["icon_size"]
text_size = _layout["text_size"]
_window = _layout["window"]
window_rect = ((_window["x"], _window["y"]), (_window["width"], _window["height"]))
icon_locations = {name: tuple(position) for name, position in _layout["icons"].items()}
