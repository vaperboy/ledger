#!/usr/bin/env python3
"""Makes administrator or beta codes for the redeem field and prints them; nothing is written to disk.

    python3 supabase/tools/make_codes.py beta 20
    python3 supabase/tools/make_codes.py admin 1

Prints (a) the plain codes, to hand out, and (b) one SQL statement that stores only their salted hashes
(run it in the Supabase SQL editor). Keep the plain codes out of the repo, chats and tickets.
A code looks like LEDGER-XXXX-XXXX-XXXX: 12 characters from 31 letters and digits (no 0, 1, I, L or O), about 59 bits.
The server hashes sha256(salt + ":" + code), with the code upper-cased and stripped to letters and digits.
"""
import hashlib
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


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("admin", "beta") or not sys.argv[2].isdigit() or not 1 <= int(sys.argv[2]) <= 5000:
        sys.exit("usage: make_codes.py admin|beta COUNT (1 to 5000)")
    kind, count = sys.argv[1], int(sys.argv[2])
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
    print("select private.add_codes('" + kind + "', array[\n  " + entries + "\n]);")


if __name__ == "__main__":
    main()
