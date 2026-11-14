#!/usr/bin/env python3
"""Makes administrator, beta or gift codes for the redeem field and prints them; nothing is written to disk.

    python3 supabase/tools/make_codes.py beta 20
    python3 supabase/tools/make_codes.py admin 1
    python3 supabase/tools/make_codes.py gift 1 --gold 500 --items face.10,gold.backdrop.crystalcave --boxes cabinet:2
    python3 supabase/tools/make_codes.py gift 5 --gold 100 --uses 1000 --expiry 2026-12-31

A gift needs at least one of --gold, --items (comma-separated cosmetic ids) or --boxes (kind:count,kind:count).
--uses is how many accounts may use each code (default 1; each account can use a code once). --expiry is the last
day the code works (UTC); without it the code never expires. The server checks items and boxes against its catalogue
and refuses Battle Pass items when the SQL runs.

Prints (a) the plain codes, to hand out, and (b) one SQL statement that stores only their salted hashes
(run it in the Supabase SQL editor). Keep the plain codes out of the repo, chats and tickets.
A code looks like LEDGER-XXXX-XXXX-XXXX: 12 characters from 31 letters and digits (no 0, 1, I, L or O), about 59 bits.
The server hashes sha256(salt + ":" + code), with the code upper-cased and stripped to letters and digits.
"""
import datetime
import hashlib
import json
import re
import secrets
import sys

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def make_code():
    groups = ["".join(secrets.choice(ALPHABET) for _ in range(4)) for _ in range(3)]
    return "LEDGER-" + "-".join(groups)


def normalise(code):
    return re.sub(r"[^A-Za-z0-9]", "", code).upper()


def entry(code):
    salt = secrets.token_hex(16)
    digest = hashlib.sha256((salt + ":" + normalise(code)).encode()).hexdigest()
    return salt + ":" + digest


def gift_args(argv):
    """Parses the options after 'gift COUNT'; returns (gold, items, boxes, uses, expiry) or exits with a message."""
    opts = {"--gold": "0", "--items": "", "--boxes": "", "--uses": "1", "--expiry": ""}
    i = 0
    while i < len(argv):
        if argv[i] not in opts or i + 1 >= len(argv):
            sys.exit("unknown or incomplete option: " + argv[i])
        opts[argv[i]] = argv[i + 1]
        i += 2
    if not opts["--gold"].isdigit() or int(opts["--gold"]) > 1000000:
        sys.exit("--gold must be a whole number up to 1000000")
    if not opts["--uses"].isdigit() or not 1 <= int(opts["--uses"]) <= 1000000:
        sys.exit("--uses must be a whole number from 1 to 1000000")
    items = [x for x in opts["--items"].split(",") if x]
    if len(set(items)) != len(items) or any(not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", x) for x in items):
        sys.exit("--items: comma-separated cosmetic ids, no repeats")
    boxes = {}
    for part in [x for x in opts["--boxes"].split(",") if x]:
        kind, _, n = part.partition(":")
        if not re.fullmatch(r"[A-Za-z0-9]{1,30}", kind) or not n.isdigit() or not 1 <= int(n) <= 100 or kind in boxes:
            sys.exit("--boxes: kind:count pairs, count 1 to 100, no repeats (for example cabinet:2)")
        boxes[kind] = int(n)
    expiry = opts["--expiry"]
    if expiry:
        try:
            datetime.date.fromisoformat(expiry)
        except ValueError:
            sys.exit("--expiry must look like 2026-12-31")
    gold = int(opts["--gold"])
    if gold == 0 and not items and not boxes:
        sys.exit("a gift needs --gold, --items or --boxes")
    return gold, items, boxes, int(opts["--uses"]), expiry


def sql_text(v):
    return "'" + v.replace("'", "''") + "'"


def main():
    args = sys.argv[1:]
    if len(args) < 2 or args[0] not in ("admin", "beta", "gift") or not args[1].isdigit() or not 1 <= int(args[1]) <= 5000:
        sys.exit("usage: make_codes.py admin|beta COUNT | gift COUNT [--gold N] [--items a,b] [--boxes kind:n] [--uses N] [--expiry YYYY-MM-DD]  (COUNT 1 to 5000)")
    kind, count = args[0], int(args[1])
    if kind != "gift" and len(args) != 2:
        sys.exit("usage: make_codes.py admin|beta COUNT")
    gift = gift_args(args[2:]) if kind == "gift" else None
    codes = set()
    while len(codes) < count:
        codes.add(make_code())
    codes = sorted(codes)
    print("-- (a) plain codes: hand these out, do not commit them")
    for c in codes:
        print(c)
    print()
    print("-- (b) SQL: stores only the salted hashes")
    entries = ",\n  ".join("'" + entry(c) + "'" for c in codes)
    if gift is None:
        print("select private.add_codes('" + kind + "', array[\n  " + entries + "\n]);")
        return
    gold, items, boxes, uses, expiry = gift
    items_sql = "array[" + ", ".join(sql_text(x) for x in items) + "]::text[]" if items else "'{}'::text[]"
    boxes_sql = sql_text(json.dumps(boxes, sort_keys=True)) + "::jsonb"
    expiry_sql = sql_text(expiry) + "::date" if expiry else "null::date"
    print("select private.add_gift_codes(array[\n  " + entries + "\n], " + ", ".join([str(gold), items_sql, boxes_sql, str(uses), expiry_sql]) + ");")


if __name__ == "__main__":
    main()
