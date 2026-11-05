#!/usr/bin/env python3
"""Event audit for the events rebalance. Prints, per prefix group: count, tone %, events with zero options
(information-only events are listed apart), blocking events. Exits 1 if any quota is not met.

  python3 Scripts/event_audit.py
"""
import json, os, sys, collections

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RES = os.path.join(ROOT, "native/Engine/Sources/Events/Resources")

# Read-only Inbox rows: stay auto, no options. Any good auto event is information-only too.
INFO = {"g_review", "g_award", "v_critic", "v_bigwin", "c_market", "d_market", "pr_subsidy", "rival_call", "probe", "g_heat"}
# The other auto events of the original file: each must now have exactly two options.
CONVERTED = ["g_theft", "g_it", "g_audit", "g_inspect", "v_health", "r_stockout", "r_adCost", "r_carrier", "p_matprice",
             "pr_flour", "pr_wood", "pr_weather", "l_fuel", "l_app", "l_toll", "l_freight", "rn_reg", "f_storm", "f_run",
             "f_default", "e_price", "e_tax", "e_dry", "e_curtail", "e_dryHole", "e_geo", "g_power", "g_roadwork"]
MAX_BLOCKING = 8
fails = []


def pct(n, t):
    return 100.0 * n / t if t else 0.0


def is_info(e):
    return e["id"] in INFO or (e.get("auto") and e.get("tone") == "good")


def tone_quota(name, c, total):
    for tone, target in (("bad", 45), ("n", 25), ("good", 30)):
        if abs(pct(c[tone], total) - target) > 3:
            fails.append(f"{name}: {tone} is {pct(c[tone], total):.1f}% (target {target}% +-3)")


events = json.load(open(os.path.join(RES, "events.json")))["events"]
groups = collections.defaultdict(list)
for k, e in events.items():
    e = dict(e, id=k)
    groups[k.split("_")[0]].append(e)

print(f"{'group':8}{'count':>6}{'bad%':>7}{'n%':>7}{'good%':>7}{'noopt':>7}{'info':>6}{'block':>6}")
tot = collections.Counter()
for g in sorted(groups, key=lambda x: (x != "g", x)):
    L = groups[g]
    c = collections.Counter(e.get("tone") or "none" for e in L)
    noopt = sum(1 for e in L if not e.get("opts") and not is_info(e))
    info = sum(1 for e in L if is_info(e))
    blk = sum(1 for e in L if e.get("blocking"))
    print(f"{g:8}{len(L):>6}{pct(c['bad'], len(L)):>7.1f}{pct(c['n'], len(L)):>7.1f}{pct(c['good'], len(L)):>7.1f}{noopt:>7}{info:>6}{blk:>6}")
    tot.update(c)
    if c["none"]:
        fails.append(f"{g}: {c['none']} untagged event(s)")
    if noopt:
        fails.append(f"{g}: {noopt} non-info event(s) without options")
    if g == "g":
        tone_quota("g", c, len(L))
    else:
        if pct(c["good"], len(L)) < 25:
            fails.append(f"{g}: good is {pct(c['good'], len(L)):.1f}% (need >= 25%)")
        if len(L) < 4 and c["good"] * 2 < c["bad"]:
            fails.append(f"{g}: fewer than 1 good per 2 bad")
for k in CONVERTED:
    if k in events and len(events[k].get("opts", [])) != 2:
        fails.append(f"{k}: needs exactly two options")
    if k in events and events[k].get("auto"):
        fails.append(f"{k}: still auto")
for k in INFO:
    if k in events and (events[k].get("opts") or not (events[k].get("auto") or k in ("rival_call", "probe"))):
        fails.append(f"{k}: information events keep auto and no options")

blocking = [k for k, e in events.items() if e.get("blocking")]
qual = sorted((k for k, e in events.items() if e.get("exp") == 1 and e.get("cat") in ("liab", "cyber")), key=lambda k: -events[k]["w"])
print(f"events total {len(events)}: bad {tot['bad']}, n {tot['n']}, good {tot['good']}; blocking {len(blocking)} {blocking}")
if len(blocking) > MAX_BLOCKING:
    fails.append(f"more than {MAX_BLOCKING} blocking events")
if set(blocking) != set(qual[:MAX_BLOCKING]):
    fails.append(f"blocking set {sorted(blocking)} differs from rule {sorted(qual[:MAX_BLOCKING])}")

# Country events (news items applied to every company of the country; they have no options, so they are information-only).
ce = json.load(open(os.path.join(RES, "country_events.json")))["events"]
c = collections.Counter(e.get("tone") or "none" for e in ce)
print(f"country  {len(ce):>5}{pct(c['bad'], len(ce)):>7.1f}{pct(c['n'], len(ce)):>7.1f}{pct(c['good'], len(ce)):>7.1f}   (news only: no options by design)")
if c["none"]:
    fails.append(f"country: {c['none']} untagged event(s)")
else:
    tone_quota("country", c, len(ce))

if fails:
    print("\nFAILED:")
    for f in fails:
        print(" -", f)
    sys.exit(1)
print("\nOK")
