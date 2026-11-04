# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""rename_fork.py - turn a Synctrain / Sushitrain checkout into a personal fork under another name.

Why: the author's README says the NAMES 'Sushitrain' / 'Synctrain' and the LOGO files are NOT under the MPL
licence (all rights reserved), and the bundle id belongs to the author's Apple team. A fork needs its own.
Reusable by design: nothing is hard-coded to one person, name or id; everything comes in as arguments.

Usage (stdlib only, Python 3.8+, no installs):
  python3 rename_fork.py REPO_DIR --name "Camera Roll Sync" --bundle-id app.example.rollsync [--git-rm] [--no-assets] [--dry-run]

What it does (each text replacement must match the expected number of places, else it stops and changes nothing):
  1. project.pbxproj: bundle ids (app + ".Share" extension), app group id, display name, app-icon name
     (-> AppIcon), and unlists the reserved icon folder SushitrainGlass.icon
  2. Info.plist background task ids, hard-coded ids in BackgroundManager.swift / App.swift / AppState.swift /
     MaintenanceManager.swift / ShareViewController.swift, share extension display name
  3. unless --no-assets: writes a plain placeholder AppIcon.appiconset and overwrites the two Logo.imageset
     pictures (the reserved logo) with a placeholder; both are generated here, nothing is downloaded
  4. with --git-rm: runs `git rm -r -q SushitrainGlass.icon Docs/logo.png` so the reserved artwork is not in the fork any more
  5. prints what is left that still says t-shaped or the name Synctrain (the copyright lines and the licence
     texts stay on purpose: the MPL requires the notices to be kept; a few help texts and macOS menu titles
     still say "Synctrain": cosmetic, not reserved logo art, change them later if you like)
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import zlib

OLD_ID = "nl.t-shaped.Sushitrain"
OLD_ID_LOWER = "nl.t-shaped.sushitrain"


def die(msg):
    print("rename_fork: " + msg, file=sys.stderr)
    sys.exit(1)


def read(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def replace_exact(text, old, new, expected, label):
    n = text.count(old)
    if n != expected:
        die("%s: expected %d x %r but found %d" % (label, expected, old, n))
    return text.replace(old, new)


# ---------- tiny PNG writer (no Pillow needed) ----------
def png_bytes(size, pixel_fn):
    """RGB, 8 bit. pixel_fn(x, y, size) -> (r, g, b)."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type 0
        for x in range(size):
            raw.extend(pixel_fn(x, y, size))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def lens_pixel(x, y, size):
    # plain blue square with a white ring and a white dot: looks like a camera lens, owned by nobody
    cx = cy = (size - 1) / 2.0
    d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / size
    if 0.28 <= d <= 0.36 or d <= 0.12:
        return (255, 255, 255)
    return (30, 64, 175)


def main():
    ap = argparse.ArgumentParser(description="Rename a Synctrain checkout into a personal fork.")
    ap.add_argument("repo", help="folder that contains Sushitrain.xcodeproj")
    ap.add_argument("--name", required=True, help="display name on the home screen, e.g. 'Camera Roll Sync'")
    ap.add_argument("--bundle-id", required=True, help="reverse-DNS bundle id, e.g. app.example.rollsync")
    ap.add_argument("--no-assets", action="store_true", help="do not write placeholder pictures")
    ap.add_argument("--git-rm", action="store_true", help="run 'git rm -r -q SushitrainGlass.icon' in the repo")
    ap.add_argument("--dry-run", action="store_true", help="check everything, write nothing")
    a = ap.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", a.bundle_id):
        die("bundle id must look like app.example.name (letters, digits, dashes, dots)")
    if a.bundle_id.lower().startswith("nl.t-shaped") or "sushitrain" in a.bundle_id.lower() or "synctrain" in a.bundle_id.lower():
        die("pick a bundle id that does not contain the author's domain or the reserved names")
    if re.search(r'["\\<>&]', a.name) or "synctrain" in a.name.lower() or "sushitrain" in a.name.lower():
        die("the display name may not contain quotes, backslashes, <, >, & or the reserved names Synctrain / Sushitrain")

    repo = os.path.abspath(a.repo)
    p = lambda *parts: os.path.join(repo, *parts)
    new_id, new_share = a.bundle_id, a.bundle_id + ".Share"
    new_group = "group." + a.bundle_id + ".sync"
    edits = {}  # path -> new text

    # 1. project file
    pbx_path = p("Sushitrain.xcodeproj", "project.pbxproj")
    t = read(pbx_path)
    t = replace_exact(t, 'PRODUCT_BUNDLE_IDENTIFIER = "%s.Share";' % OLD_ID, 'PRODUCT_BUNDLE_IDENTIFIER = "%s";' % new_share, 2, "pbxproj share id")
    t = replace_exact(t, 'PRODUCT_BUNDLE_IDENTIFIER = "%s";' % OLD_ID, 'PRODUCT_BUNDLE_IDENTIFIER = "%s";' % new_id, 2, "pbxproj app id")
    t = replace_exact(t, 'SYNCTRAIN_APP_GROUP = "group.%s.sync";' % OLD_ID_LOWER, 'SYNCTRAIN_APP_GROUP = "%s";' % new_group, 4, "pbxproj app group")
    t = replace_exact(t, '"SYNCTRAIN_APP_GROUP[sdk=macosx*]" = "$(DEVELOPMENT_TEAM).%s.sync";' % OLD_ID_LOWER,
                      '"SYNCTRAIN_APP_GROUP[sdk=macosx*]" = "$(DEVELOPMENT_TEAM).%s.sync";' % a.bundle_id, 4, "pbxproj mac app group")
    t = replace_exact(t, "INFOPLIST_KEY_CFBundleDisplayName = Synctrain;", 'INFOPLIST_KEY_CFBundleDisplayName = "%s";' % a.name, 2, "pbxproj display name")
    t = replace_exact(t, "ASSETCATALOG_COMPILER_APPICON_NAME = SushitrainGlass;", "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", 2, "pbxproj icon name")
    lines = t.split("\n")
    kept = [ln for ln in lines if "SushitrainGlass.icon" not in ln]
    if len(lines) - len(kept) != 4:
        die("pbxproj: expected 4 lines about SushitrainGlass.icon, found %d" % (len(lines) - len(kept)))
    edits[pbx_path] = "\n".join(kept)

    # 2. plain text files with hard-coded ids
    for rel, old, new, expected in [
        (("Sushitrain", "Info.plist"), OLD_ID + ".", a.bundle_id + ".", 3),
        (("Sushitrain", "BackgroundManager.swift"), OLD_ID + ".", a.bundle_id + ".", 3),
        (("Sushitrain", "BackgroundManager.swift"), OLD_ID_LOWER + ".", a.bundle_id + ".", 1),
        (("Sushitrain", "App.swift"), OLD_ID + ".", a.bundle_id + ".", 1),
        (("Sushitrain", "AppState.swift"), OLD_ID_LOWER + ".", a.bundle_id + ".", 1),
        (("Sushitrain", "MaintenanceManager.swift"), OLD_ID + ".", a.bundle_id + ".", 1),
        (("SushitrainShareExtension", "ShareViewController.swift"), OLD_ID + ".Share", new_share, 1),
    ]:
        path = p(*rel)
        text = edits.get(path) or read(path)
        edits[path] = replace_exact(text, old, new, expected, "/".join(rel))

    share_plist = p("SushitrainShareExtension", "Info.plist")
    text = read(share_plist)
    edits[share_plist] = replace_exact(text, "<key>CFBundleDisplayName</key>\n\t<string>Synctrain</string>",
                                       "<key>CFBundleDisplayName</key>\n\t<string>%s</string>" % a.name, 1, "share extension display name") \
        if "\r\n" not in text else replace_exact(text, "<key>CFBundleDisplayName</key>\r\n\t<string>Synctrain</string>",
                                                 "<key>CFBundleDisplayName</key>\r\n\t<string>%s</string>" % a.name, 1, "share extension display name")

    # 3. placeholder pictures (binary files, written after the text checks passed)
    asset_files = {}
    if not a.no_assets:
        icon_dir = p("Sushitrain", "Assets.xcassets", "AppIcon.appiconset")
        asset_files[os.path.join(icon_dir, "icon-1024.png")] = png_bytes(1024, lens_pixel)
        asset_files[os.path.join(icon_dir, "Contents.json")] = (
            '{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n      "idiom" : "universal",\n'
            '      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
        ).encode("utf-8")
        logo_dir = p("Sushitrain", "Assets.xcassets", "Logo.imageset")
        for fn in ("Logo.png", "Logo-light.png"):
            if not os.path.exists(os.path.join(logo_dir, fn)):
                die("missing %s" % os.path.join(logo_dir, fn))
            asset_files[os.path.join(logo_dir, fn)] = png_bytes(256, lens_pixel)

    if a.dry_run:
        print("dry run: %d text files and %d picture files would be written" % (len(edits), len(asset_files)))
        return 0

    for path, text in edits.items():
        write(path, text)
    for path, data in asset_files.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    print("wrote %d text files, %d picture files" % (len(edits), len(asset_files)))

    if a.git_rm:
        # the final logo files that the README lists as not licensed (the icon folder that is built, and the README picture)
        r = subprocess.run(["git", "rm", "-r", "-q", "--ignore-unmatch", "SushitrainGlass.icon", "Docs/logo.png"], cwd=repo)
        if r.returncode != 0:
            die("git rm failed (exit %d)" % r.returncode)
        print("removed the reserved logo files from the tree (git rm): SushitrainGlass.icon, Docs/logo.png (README.md now shows a broken picture: harmless)")
    else:
        print("NOTE: the reserved files SushitrainGlass.icon and Docs/logo.png are still on disk (the icon is no longer built). Use --git-rm to drop them.")

    # 5. what is left
    left = []
    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in (".git", "SushitrainCore", "build", "Build")]
        for fn in files:
            if not fn.endswith((".swift", ".plist", ".pbxproj", ".entitlements", ".yml", ".xcscheme")):
                continue
            path = os.path.join(root, fn)
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f, 1):
                    # the module / type names SushitrainCore, SushitrainFolder ... are the Go bridge: not user visible, not reserved
                    if re.search(r"t-shaped|\bSynctrain\b", line) and "Copyright" not in line:
                        left.append((os.path.relpath(path, repo), i, line.strip()[:110]))
    print("lines that still mention t-shaped or the name Synctrain (outside Go and licence texts): %d" % len(left))
    for rel, i, line in left[:60]:
        print("  %s:%d: %s" % (rel, i, line))
    return 0


if __name__ == "__main__":
    sys.exit(main())
