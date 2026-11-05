#!/usr/bin/env python3
"""Merge findings-*.tsv from a play-test run into one ranked list (severity, then count) and write ranked.txt, titles.txt and runs summary.
Usage: python3 -I aggregate.py <out dir>"""
import sys, glob, os, collections

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/s/playtest"
merged = {}
for p in sorted(glob.glob(os.path.join(out, "findings-*.tsv"))):
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 6:
            continue
        sev, key, count, title, repro, file = int(f[0]), f[1], int(f[2]), f[3], f[4], f[5]
        m = merged.get(key)
        if m is None:
            merged[key] = dict(sev=sev, key=key, count=count, title=title, repro=repro, file=file)
        else:
            m["count"] += count
            m["sev"] = min(m["sev"], sev)
rows = sorted(merged.values(), key=lambda r: (r["sev"], -r["count"], r["key"]))
with open(os.path.join(out, "ranked.txt"), "w") as fh:
    for i, r in enumerate(rows, 1):
        fh.write(f"{i}. [sev{r['sev']}] x{r['count']} {r['title']}\n    key={r['key']}\n    repro: {r['repro']}\n    suspect: {r['file']}\n")
titles = collections.Counter()
for p in glob.glob(os.path.join(out, "titles-*.tsv")):
    for line in open(p, encoding="utf-8", errors="replace"):
        n, _, t = line.rstrip("\n").partition("\t")
        if n.isdigit():
            titles[t] += int(n)
with open(os.path.join(out, "titles.txt"), "w") as fh:
    for t, n in titles.most_common():
        fh.write(f"{n}\t{t}\n")
runs = 0; over = 0
for p in glob.glob(os.path.join(out, "runs-*.tsv")):
    for line in open(p, encoding="utf-8", errors="replace"):
        runs += 1
        over += "\tOVER\t" in line
print(f"{len(rows)} distinct findings, {runs} runs, {over} game-overs; see {out}/ranked.txt")
