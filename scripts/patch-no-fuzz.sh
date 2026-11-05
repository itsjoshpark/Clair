#!/bin/bash
# The patch tool for Clair's series: patch without fuzz. build.sh names it in
# PATCH_BIN, the only way to change how ungoogled-chromium's patches.py runs
# patch.
#
# By default patch ignores up to two context lines at each end of a hunk, so a
# patch can apply silently after the code around it has changed. Taking a new
# ungoogled-chromium tag must stop on that instead, and name the patch.

exec patch --fuzz=0 "$@"
