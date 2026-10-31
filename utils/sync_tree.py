#!/usr/bin/env python3
# Copyright 2026 The Clair Authors
# You can use, redistribute, and/or modify this source code under
# the terms of the GPL-3.0 license that can be found in the LICENSE file.
"""In-place updates of a prepared Chromium tree (change 1 design D11).

build.sh keeps a pristine APFS clone of the tree as it is before Clair's
patches (the base), applies Clair's layer to a fresh clone of the base, and
then copies into the build tree only the files whose contents changed. Files
that end up the same keep their modification times, so ninja rebuilds only
what the change affects.

  sync_tree.py clone SRC DST
      Clone the directory SRC to DST with clonefile(2). Fails on volumes
      without clones.
  sync_tree.py record --stamp FILE [--patches DIR] TREE
      Print the paths under TREE modified after FILE, plus every path named in
      the patches of DIR/series: the files a layer applied after FILE touched.
      The top-level out/ directory is ignored.
  sync_tree.py sync NEXT DEST LIST...
      For each path in the LIST files, make DEST match NEXT: copy changed
      files, remove files NEXT lacks, and leave identical files untouched.
"""

import argparse
import ctypes
import os
import re
import shutil
import stat
import sys
from pathlib import Path

_CLONE_NOFOLLOW = 0x0001
_IGNORED_TOP = {'out', '.clair_prepared'}
_PATCH_PATH = re.compile(r'^(?:---|\+\+\+) [ab]/([^\t\n]+)')


def _fail(message):
    print(f'sync_tree: {message}', file=sys.stderr)
    sys.exit(1)


def _check_relative(path):
    parts = Path(path).parts
    if not parts or Path(path).is_absolute() or '..' in parts or '\n' in path:
        _fail(f'unsafe path in list: {path!r}')


def clone(src, dst):
    """Clones a directory tree with clonefile(2)."""
    if os.path.lexists(dst):
        _fail(f'{dst} already exists')
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.clonefile(os.fsencode(src), os.fsencode(dst), ctypes.c_uint32(_CLONE_NOFOLLOW)) != 0:
        _fail(f'cannot clone {src}: {os.strerror(ctypes.get_errno())}')


def _patch_paths(patches_dir):
    series = patches_dir / 'series'
    for line in series.read_text(encoding='utf-8').splitlines():
        name = line.split('#', 1)[0].strip()
        if not name:
            continue
        with open(patches_dir / name, encoding='utf-8', errors='surrogateescape') as patch:
            for patch_line in patch:
                match = _PATCH_PATH.match(patch_line)
                if match:
                    yield match.group(1).strip()


def record(tree, stamp, patches_dir):
    """Prints the files a layer touched: newer than the stamp, or patched."""
    since = os.lstat(stamp).st_mtime_ns
    paths = set()
    for root, dirs, files in os.walk(tree):
        rel_root = os.path.relpath(root, tree)
        if rel_root == '.':
            dirs[:] = [name for name in dirs if name not in _IGNORED_TOP]
            files = [name for name in files if name not in _IGNORED_TOP]
        # os.walk lists symlinks to directories under dirs; record them too.
        names = list(files) + [name for name in dirs if os.path.islink(os.path.join(root, name))]
        for name in names:
            if os.lstat(os.path.join(root, name)).st_mtime_ns > since:
                paths.add(os.path.normpath(os.path.join(rel_root, name)))
    if patches_dir is not None:
        paths.update(_patch_paths(patches_dir))
    for path in sorted(paths):
        _check_relative(path)
        print(path)


def _same_file(a, b):
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, 'rb') as file_a, open(b, 'rb') as file_b:
        while True:
            chunk_a = file_a.read(1 << 20)
            if chunk_a != file_b.read(1 << 20):
                return False
            if not chunk_a:
                return True


def _check_inside(dest_tree, target):
    """Refuses to write through a symlinked directory that leaves the tree."""
    root = os.path.realpath(dest_tree)
    parent = os.path.realpath(os.path.dirname(target))
    if parent != root and not parent.startswith(root + os.sep):
        _fail(f'{target} is outside {dest_tree}')


def _remove(path):
    if os.path.isdir(path) and not os.path.islink(path):
        _fail(f'expected a file, found a directory: {path}')
    os.unlink(path)


def sync(next_tree, dest_tree, lists):
    """Makes each listed path in dest_tree match next_tree."""
    paths = set()
    for list_file in lists:
        for line in Path(list_file).read_text(encoding='utf-8').splitlines():
            if line:
                _check_relative(line)
                paths.add(line)
    copied = removed = same = 0
    for path in sorted(paths):
        source = os.path.join(next_tree, path)
        target = os.path.join(dest_tree, path)
        _check_inside(dest_tree, target)
        if not os.path.lexists(source):
            if os.path.lexists(target):
                _remove(target)
                removed += 1
            continue
        mode = os.lstat(source).st_mode
        if stat.S_ISDIR(mode):
            continue
        if stat.S_ISLNK(mode):
            link = os.readlink(source)
            if os.path.islink(target) and os.readlink(target) == link:
                same += 1
                continue
            if os.path.lexists(target):
                _remove(target)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            os.symlink(link, target)
            copied += 1
            continue
        if os.path.isfile(target) and not os.path.islink(target) and _same_file(source, target):
            if stat.S_IMODE(os.stat(target).st_mode) != stat.S_IMODE(mode):
                shutil.copymode(source, target)
            same += 1
            continue
        if os.path.lexists(target):
            _remove(target)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        # A plain copy gives the file a new modification time, so ninja
        # rebuilds what depends on it.
        shutil.copyfile(source, target)
        shutil.copymode(source, target)
        copied += 1
    print(f'sync_tree: {copied} copied, {removed} removed, {same} unchanged')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    clone_parser = commands.add_parser('clone')
    clone_parser.add_argument('src', type=Path)
    clone_parser.add_argument('dst', type=Path)
    record_parser = commands.add_parser('record')
    record_parser.add_argument('--stamp', type=Path, required=True)
    record_parser.add_argument('--patches', type=Path)
    record_parser.add_argument('tree', type=Path)
    sync_parser = commands.add_parser('sync')
    sync_parser.add_argument('next', type=Path)
    sync_parser.add_argument('dest', type=Path)
    sync_parser.add_argument('lists', type=Path, nargs='+')
    args = parser.parse_args()
    if args.command == 'clone':
        clone(args.src, args.dst)
    elif args.command == 'record':
        record(args.tree, args.stamp, args.patches)
    else:
        sync(args.next, args.dest, args.lists)


if __name__ == '__main__':
    main()
