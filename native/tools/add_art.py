#!/usr/bin/env python3
"""Adds a picture to the game's art catalogue so it replaces the drawn emblem for one id.

Usage: add_art.py <category> <id> <image.png> [folder]
Category is one of: trade artifact theme backdrop namePlate tradePlate flair box badge advisor saveSlot gold avatar.
The id is the game id (trade id, artifact id, cosmetic or reward id, box kind, avatar id). Example: add_art.py trade cafe cafe.png
The image set `art.<category>.<id>` is written under native/App/Ledger/Assets.xcassets/Art/<folder>; no code changes are needed.
"""
import json
import os
import shutil
import sys

FOLDERS = {"trade": "Trades", "artifact": "Artifacts", "theme": "Themes", "backdrop": "Backdrops", "namePlate": "Plates", "tradePlate": "Plates",
           "flair": "Flair", "box": "Boxes", "badge": "Rewards", "advisor": "Rewards", "saveSlot": "Rewards", "gold": "Rewards", "avatar": "Avatars"}


def main(argv):
    if len(argv) < 4 or argv[1] not in FOLDERS:
        print(__doc__)
        return 1
    category, ident, image = argv[1], argv[2], argv[3]
    folder = argv[4] if len(argv) > 4 else FOLDERS[category]
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Ledger", "Assets.xcassets", "Art", folder)
    name = "art.%s.%s" % (category, ident)
    out = os.path.join(root, name + ".imageset")
    os.makedirs(out, exist_ok=True)
    ext = os.path.splitext(image)[1].lower() or ".png"
    shutil.copyfile(image, os.path.join(out, name + ext))
    contents = {"images": [{"filename": name + ext, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(out, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
