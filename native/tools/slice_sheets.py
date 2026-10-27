#!/usr/bin/env python3
"""Slice the supplied art sheets into single cells (pixel analysis, no hard-coded coordinates).

Usage: python3 native/tools/slice_sheets.py [sheet ...]   (premises luxury cars logos trophies)
Writes native/App/Ledger/Resources/art/cells/<sheet>/<name>.jpg and cells/<sheet>/manifest.json.
Captions are typed below (read from the sheet images); the pictures are found by looking for the
pixels that differ from the page background, then trimming a few pixels of frame.
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Ledger", "Resources", "art"))


def load(name):
    return Image.open(os.path.join(ROOT, name + "-sheet.jpg")).convert("RGB")


def bg_mask(img, thr):
    a = np.asarray(img).astype(int)
    corner = np.concatenate([a[:6, :6].reshape(-1, 3), a[:6, -6:].reshape(-1, 3), a[-6:, :6].reshape(-1, 3), a[-6:, -6:].reshape(-1, 3)])
    bg = np.median(corner, axis=0)
    return np.abs(a - bg).sum(axis=2) > thr


def runs(profile, thr, minlen, gap=2):
    """Index ranges [a,b) where profile > thr, bridging gaps up to `gap`, at least minlen long."""
    on = profile > thr
    out, start, last = [], None, None
    for i, v in enumerate(on):
        if v:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            if last - start + 1 >= minlen:
                out.append((start, last + 1))
            start = None
    if start is not None and last - start + 1 >= minlen:
        out.append((start, last + 1))
    return out


def grid(img, thr=60, rthr=0.5, cthr=0.5, minh=40, minw=40, region=None, gap=3):
    """Rows then columns of picture rectangles (x0, y0, x1, y1)."""
    m = bg_mask(img, thr)
    x0, y0, x1, y1 = region or (0, 0, m.shape[1], m.shape[0])
    sub = m[y0:y1, x0:x1]
    rows = runs(sub.mean(axis=1), rthr, minh, gap)
    # columns are shared by all rows: measure them on the union of the row bands
    band = np.concatenate([sub[ra:rb] for ra, rb in rows], axis=0)
    cols = runs(band.mean(axis=0), cthr, minw, gap)
    cells = [[(x0 + ca, y0 + ra, x0 + cb, y0 + rb) for (ca, cb) in cols] for (ra, rb) in rows]
    return cells


def save(img, box, path, size, trim=3, quality=82):
    c = img.crop((box[0] + trim, box[1] + trim, box[2] - trim, box[3] - trim))
    w, h = size
    tw, th = c.size
    if tw * h > th * w:  # too wide: centre-crop to the target aspect
        nw = int(th * w / h)
        c = c.crop(((tw - nw) // 2, 0, (tw - nw) // 2 + nw, th))
    else:
        nh = int(tw * h / w)
        c = c.crop((0, (th - nh) // 2, tw, (th - nh) // 2 + nh))
    c = c.resize((w, h), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    c.save(path, "JPEG", quality=quality, optimize=True, progressive=True)


def out_dir(sheet):
    return os.path.join(ROOT, "cells", sheet)


def write_manifest(sheet, entries):
    with open(os.path.join(out_dir(sheet), "manifest.json"), "w") as f:
        json.dump({"sheet": sheet, "cells": entries}, f, indent=1, ensure_ascii=False)
    print(sheet, len(entries), "cells")


# ---------------------------------------------------------------- premises
PREM_KINDS = ["home", "office", "shop", "kitchen", "industrial", "warehouse", "hotel", "clinic", "yard", "gym", "slope"]
PREM_BANDS = ["small", "medium", "large", "xlarge"]
PREM_LABELS = ["Home or Home Office", "Office", "Shop", "Kitchen, Restaurant or Cafe", "Workshop or Factory",
               "Warehouse or Depot", "Hotel", "Clinic", "Yard or Site", "Gym or Studio", "Slope or Outdoor Venue"]


def premises():
    img = load("premises")
    g = grid(img, thr=70, rthr=0.3, cthr=0.5, minh=80, minw=100,
             region=(int(img.width * 0.08), int(img.height * 0.05), img.width, img.height))
    g = [r for r in g if len(r) == 4]
    assert len(g) == 11, len(g)
    entries = {}
    for ri, row in enumerate(g):
        for ci, box in enumerate(row):
            cid = f"{PREM_KINDS[ri]}-{PREM_BANDS[ci]}"
            save(img, box, os.path.join(out_dir("premises"), cid + ".jpg"), (640, 360), trim=4, quality=78)
            entries[cid] = {"file": f"premises/{cid}.jpg", "row": ri, "col": ci, "caption": PREM_LABELS[ri] + " / " + PREM_BANDS[ci]}
    write_manifest("premises", entries)


# ---------------------------------------------------------------- luxury
LUX = [
    ("watches", ["Chrono Heritage", "Deep-Sea Mariner", "Aura Tourbillon", "Eclipse GMT", "Regal Gold", "Avant-Garde Concept"]),
    ("jewellery", ["Cascade Diamond Necklace", "Imperial Sapphire Drop", "Aurelia Cuff", "Elysian Emerald Ring", "Majestic Pearl Choker", "Solitaire Platinum Band"]),
    ("art", ["Abstract Fusion", "Sovereign Dynasty Vase", "Siren Sculpture", "Pre-War Heritage Mascot", "Ancient Relic Artifact", "Bespoke Glass installation"]),
    ("yachtjet", ["Grand Horizon Mega Yacht (80m+)", "Zephyr Sport Yacht (30m)", "Aura Sailing Yacht", "Stratosphere Private Jet (Ultra-Long)", "Ascent Heavy Jet", "Vanguard Mid-Size Jet"]),
    ("homes", ["Light business Jet", "Pacific Waterfront Villa", "Grand Urban Townhouse", "Alpine Chalet", "Regal Country Estate", "Solitude Island Estate"]),
]


def luxury():
    img = load("luxury")
    g = grid(img, thr=70, rthr=0.25, cthr=0.5, minh=100, minw=100, region=(0, int(img.height * 0.08), img.width, img.height))
    g = [r for r in g if len(r) == 6]
    assert len(g) == 5, [len(r) for r in g]
    entries = {}
    for ri, row in enumerate(g):
        grp, caps = LUX[ri]
        for ci, box in enumerate(row):
            cid = f"{grp}-{ci + 1}"
            save(img, box, os.path.join(out_dir("luxury"), cid + ".jpg"), (512, 384), trim=3, quality=80)
            entries[cid] = {"file": f"luxury/{cid}.jpg", "row": ri, "col": ci, "group": grp, "caption": caps[ci]}
    write_manifest("luxury", entries)


# ---------------------------------------------------------------- cars
CARS = [["Velocita", "Stradale", "Grandiosa"], ["Presidio", "Elysium", "Apex"], ["Eon", "Aero", "Volt"], ["Majesty", "Vanguard", "Regent"],
        ["GT-Ryu", "Kage", "Shinobi"], ["Trojan", "Odyssey", "Titan"], ["Siren", "Odin", "Asgard"], ["Meridian", "Riviera", "Sirocco"]]


def cars():
    img = load("cars")
    g = grid(img, thr=90, rthr=0.35, cthr=0.5, minh=60, minw=100, region=(int(img.width * 0.15), 0, img.width, img.height))
    g = [r for r in g if len(r) == 3]
    assert len(g) == 8, [len(r) for r in g]
    entries = {}
    for ri, row in enumerate(g):
        for ci, box in enumerate(row):
            cid = f"b{ri + 1}-{ci + 1}"
            save(img, box, os.path.join(out_dir("cars"), cid + ".jpg"), (512, 250), trim=4, quality=80)
            entries[cid] = {"file": f"cars/{cid}.jpg", "row": ri, "col": ci, "caption": CARS[ri][ci]}
    write_manifest("cars", entries)


# ---------------------------------------------------------------- logos
def logos():
    img = load("logos")
    g = grid(img, thr=22, rthr=0.5, cthr=0.5, minh=40, minw=40,
             region=(int(img.width * 0.03), int(img.height * 0.06), img.width, img.height), gap=2)
    g = [r for r in g if len(r) >= 10]
    entries, n = {}, 0
    for ri, row in enumerate(g):
        for ci, box in enumerate(row):
            n += 1
            cid = f"l{n:03d}"
            save(img, box, os.path.join(out_dir("logos"), cid + ".jpg"), (192, 192), trim=2, quality=80)
            entries[cid] = {"file": f"logos/{cid}.jpg", "row": ri, "col": ci, "caption": ""}
    write_manifest("logos", entries)


# ---------------------------------------------------------------- trophies
TROPHIES = ["Golden Globe", "Rising Star", "Glass Obelisk", "Winged Triumph", "Ornate Keys", "Ceremonial Gavel",
            "First Million", "Exchange Bell", "Key to the City", "Ten Year Shield", "Top Ten Plaque", "Global Scale",
            "Aviation/Builders", "Industrial Gear", "Maritime Anchor", "Culinary Prize", "Tech Achievement", "Health & Care",
            "Five-Star Plaque", "Standard Approval", "Safety Shield", "Official Certificate", "Green Ecology", "Excellence Medal",
            "Asset Reserve", "Market Bull", "Heritage Cup", "Crystal Diamond", "Crest of Honor", "Value Token",
            "Honor Ribbon", "Exemplar Silver", "Civic Merit", "Unique Crest", "Victors Medal", "Civic Collar"]


def trophies():
    img = load("trophies")
    # a tile is a dark picture above a pale caption band; the picture is the dark part
    dark = np.asarray(img.convert("L")).astype(int) < 90
    differs = bg_mask(img, 80)
    rows = [r for r in runs(dark[:, int(img.width * 0.02):].mean(axis=1), 0.35, 30, 2) if r[1] - r[0] > 150]
    assert len(rows) == 6, rows
    entries, i = {}, 0
    for ri, (ra, rb) in enumerate(rows):
        cols = runs(differs[ra:rb].mean(axis=0), 0.25, 100, 2)
        assert len(cols) == 6, cols
        for ci, (ca, cb) in enumerate(cols):
            cid = f"t{i + 1:02d}"
            save(img, (ca, ra, cb, rb), os.path.join(out_dir("trophies"), cid + ".jpg"), (384, 384), trim=3, quality=82)
            entries[cid] = {"file": f"trophies/{cid}.jpg", "row": ri, "col": ci, "caption": TROPHIES[i]}
            i += 1
    write_manifest("trophies", entries)


if __name__ == "__main__":
    for s in sys.argv[1:] or ["premises", "luxury", "cars", "logos", "trophies"]:
        globals()[s]()
