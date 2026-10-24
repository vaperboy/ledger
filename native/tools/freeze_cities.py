#!/usr/bin/env python3
"""Writes every country's cities out fully (id, name, pop, rent, wage, dem, price) in countries.json, using the same formulas the
engine used to derive them at load time (Country.init). After this no country needs the formulas, and every country's cities
can be tuned by hand. Idempotent: countries whose cities are already objects with "citiesFinal" are left alone."""
import json, math, pathlib
p = pathlib.Path(__file__).resolve().parent.parent / "Engine/Sources/Countries/Resources/countries.json"
c = json.load(open(p))
f = lambda v: math.floor(v + 0.5)
r2 = lambda v: f(v * 100) / 100
BASE = dict(median=56000, price=137, rent=2500, spend=330000)       # the price-level baseline the trades are written at
R20 = dict(cost=110, wage=97)
for x in c:
    if x.get("citiesFinal"): continue
    fx = x["fx"]; B = lambda v: v * fx
    e = x["economy"]
    ratio = e["priceIndex"] / BASE["price"]
    pl = r2(ratio)
    mkt = r2(math.sqrt(B(e["spendPerPerson"]) / BASE["spend"] / ratio))
    rentL = r2(B(e["officeRent"]) / BASE["rent"])
    wageL = r2(B(e["medianWage"]) / BASE["median"])
    out = []
    for ct in x["cities"]:
        if isinstance(ct, dict):
            out.append({"id": ct["id"], "name": ct["name"], "pop": ct["pop"], "rent": ct["rent"], "wage": ct["wage"], "dem": ct["dem"], "price": ct["price"]})
            continue
        pop = ct[2]
        dem = min(2.4, max(0.35, 0.42 + 0.55 * math.log10(pop / 20))) * mkt
        out.append({"id": ct[0], "name": ct[1], "pop": pop, "rent": r2(rentL * ct[3]), "wage": r2(wageL * ct[4]), "dem": r2(dem), "price": r2(pl * (0.9 + 0.1 * ct[3]))})
    ei = x.get("economyIndex")
    if ei and not all(isinstance(ct, dict) for ct in x["cities"]):
        newPL = r2(ei["costIndex"] / R20["cost"]); newWage = r2(ei["wageIndex"] / R20["wage"])
        oldPL = pl or 1; oldWage = wageL or 1; oldMkt = mkt or 1
        for ct in out:
            ct["wage"] = r2(ct["wage"] / oldWage * newWage); ct["price"] = r2(ct["price"] / oldPL * newPL); ct["dem"] = r2(ct["dem"] / oldMkt)
    x["cities"] = out
    x["citiesFinal"] = True
json.dump(c, open(p, "w"), separators=(",", ":"), ensure_ascii=False)
print("frozen", len(c))
