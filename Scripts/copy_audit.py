#!/usr/bin/env python3
"""Copy audit (brief Part 6.1). Scans the string literals of the app (and the engine's player-facing text) for the hard copy rules:
  - no exclamation mark in a string (7)
  - no string starting with `Note that`, `Please`, `Remember` or `You can` (5)
  - no button titled `OK`, `Yes` or `Confirm` on its own (3)
  - no `Are you sure?` dialog text (6.4)
  - no `Nothing is lost` sentence (6.4)
  - no unit-less long text at the point of action: a Button/Toggle/Stepper label over 90 characters (1) is a warning only.
Exits 1 on any hard failure. Warnings never fail.

  python3 Scripts/copy_audit.py            # whole app and engine
  python3 Scripts/copy_audit.py --changed  # only files changed against native-swiftui (strings you touched)
  python3 Scripts/copy_audit.py -v         # list every hit, not only the first 10 per rule
"""
import os, re, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DIRS = [os.path.join(ROOT, "native/App/Ledger"), os.path.join(ROOT, "native/Engine/Sources")]
VERBOSE = "-v" in sys.argv

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
INTERP = re.compile(r'\\\((?:[^()]|\([^()]*\))*\)')
EXCL = re.compile(r'\w!(\s|$)')
BAD_START = re.compile(r'^\s*(Note that|Please|Remember|You can)\b')
BAD_BUTTON = re.compile(r'\b(Button|QuietButton|PrimaryButton|OutlineButton)\(\s*"(OK|Yes|Confirm)"')
BAD_TITLE = re.compile(r'\b(title|label|confirmTitle|confirmLabel|actionTitle)\s*:\s*"(OK|Yes|Confirm)"')
LONG_BUTTON = re.compile(r'\b(Button|Toggle)\(\s*"((?:[^"\\\n]|\\.)*)"')


def files():
    only = None
    if "--changed" in sys.argv:
        out = subprocess.run(["git", "-C", ROOT, "diff", "--name-only", "native-swiftui"], capture_output=True, text=True).stdout
        only = {os.path.join(ROOT, p) for p in out.split()}
    for d in DIRS:
        for base, _, names in os.walk(d):
            for n in names:
                p = os.path.join(base, n)
                if n.endswith(".swift") and (only is None or os.path.abspath(p) in {os.path.abspath(x) for x in only}):
                    yield p


def main():
    hard, warn = {}, {}
    for path in files():
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            for no, line in enumerate(f, 1):
                s = line.strip()
                if s.startswith("//") or s.startswith("///"):
                    continue
                code = line.split(" // ")[0]
                for m in LITERAL.finditer(code):
                    text = INTERP.sub("", m.group(1))
                    if EXCL.search(text):
                        hard.setdefault("exclamation mark", []).append((rel, no, text))
                    if BAD_START.match(text):
                        hard.setdefault("starts with Note that / Please / Remember / You can", []).append((rel, no, text))
                    if "Are you sure?" in text:
                        hard.setdefault("Are you sure?", []).append((rel, no, text))
                    if "Nothing is lost" in text:
                        hard.setdefault("Nothing is lost", []).append((rel, no, text))
                if BAD_BUTTON.search(code) or BAD_TITLE.search(code):
                    hard.setdefault("button OK / Yes / Confirm", []).append((rel, no, s[:90]))
                for m in LONG_BUTTON.finditer(code):
                    text = INTERP.sub("", m.group(2))
                    if len(text) > 90:
                        warn.setdefault("action label over 90 characters", []).append((rel, no, text))
    for title, group in (("FAIL", hard), ("warn", warn)):
        for rule, hits in sorted(group.items()):
            print(f"{title}: {rule}: {len(hits)}")
            for rel, no, text in hits if VERBOSE else hits[:10]:
                print(f"    {rel}:{no}: {text[:100]}")
    if not hard and not warn:
        print("copy audit: clean")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
