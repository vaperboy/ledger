#!/usr/bin/env python3
"""One-off migration: replace identifiers taken from Norwegian words (company forms ENK/AS, permit ids such as mva, skjenk ...)
with neutral English ones in the data files. The mapping is also used by the save importer (SaveSystem/LegacyIds.swift) so saves
from the HTML game keep working. Run once; it is idempotent."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent / "Engine/Sources"
DOCS = {
 "org": "registration", "mva": "vat", "mva_na": "vat_not_applicable", "hms": "workplace_safety", "acctr": "accountant_agreement", "gdpr": "data_protection",
 "mattil": "food_registration", "haccp": "food_safety_plan", "skjenk": "alcohol_serving", "salg": "alcohol_retail", "tobak": "tobacco_sales",
 "ysk": "driver_certificate", "buslic": "bus_licence", "tgodk": "building_contractor", "elvirk": "electrical_contractor", "vvs": "plumbing_approval",
 "bygg": "building_permit", "regplan": "zoning_plan", "rev": "accounting_approval", "megler": "estate_agency", "helse": "health_authorisation",
 "hpr": "clinic_approval", "trafikk": "driving_school", "forsik": "insurance_licence", "aif": "fund_manager", "aml": "aml_programme",
 "brygg": "brewery_licence", "vinm": "alcohol_wholesale", "aqua": "aquaculture_licence", "fishq": "fish_health", "skog": "forestry_plan",
 "landb": "farm_registration", "fabrik": "environmental_permit", "ce": "product_certification", "nve": "power_licence", "nveLite": "solar_notification",
 "grid": "grid_connection", "oilsafe": "oil_safety", "aoc": "air_operator", "skip": "ship_registration", "vinn": "used_goods", "garanti": "warranty_policy",
 "eh": "ecommerce_terms", "child": "police_certificate", "ped": "pet_registration", "drone": "drone_registration", "forb": "liability_insurance",
 "vik": "fire_safety", "kunnsk": "competence_certificate", "stat": "lease_agreement", "mfinans": "credit_notification", "renhold": "cleaning_approval",
 "bemanning": "staffing_registration", "torg": "street_trading", "safety": "site_safety", "verk": "workshop_approval", "lift": "ski_lift_approval",
 "zone": "slope_zoning", "xray": "xray_registration", "vakt": "security_licence", "ins_skade": "ins_property", "ins_bil": "ins_motor", "ins_hjem": "ins_home",
 "ins_reise": "ins_travel", "ins_naring": "ins_business", "fran": "franchise_disclosure", "fran_op": "franchise_agreement", "forreg": "foreign_entity",
 "chain": "chain_registration", "goods": "goods_transport", "event": "event_permit", "oil": "oil_licence", "casino": "casino_licence", "bank": "banking_licence",
 "lawyer": "lawyer_licence", "taxi": "taxi_licence",
}
INS = {"skade": "property", "bil": "motor", "hjem": "home", "reise": "travel", "naring": "business"}
FORMS = {"ENK": "soleTrader", "AS": "limited", "ENKs": "soleTraderShort", "ASs": "limitedShort"}
def rn(x): return DOCS.get(x, x)

def doc_list(l): return [rn(x) for x in l]

# tables.json
p = root / "Businesses/Resources/tables.json"; t = json.load(open(p))
t["DOCS"] = {rn(k): v for k, v in t["DOCS"].items()}
t["INS_PRODS"] = {INS.get(k, k): [v[0], {**v[1], "doc": rn(v[1].get("doc", ""))}] for k, v in t["INS_PRODS"].items()}
if "organisation number" in t["DOCS"]["registration"][5]: t["DOCS"]["registration"][5] = "Gives you the company registration number."
json.dump(t, open(p, "w"), separators=(",", ":"), ensure_ascii=False)

# trades.json
p = root / "Businesses/Resources/trades.json"; t = json.load(open(p))
for k, v in t["trades"].items():
    v["docs"] = doc_list(v.get("docs", []))
    if "needAS" in v: v["needLimited"] = v.pop("needAS")
    for kn in v.get("knobs", []):
        for o in kn.get("opts", []):
            fx = o.get("fx") or {}
            if "req" in fx: fx["req"] = doc_list(fx["req"])
    if v.get("dq"): v["dq"] = {rn(a): b for a, b in v["dq"].items()}
json.dump(t, open(p, "w"), separators=(",", ":"), ensure_ascii=False)

# countries.json
p = root / "Countries/Resources/countries.json"; c = json.load(open(p))
for x in c:
    d = x.get("documents") or {}
    if "overrides" in d: d["overrides"] = {rn(a): b for a, b in d["overrides"].items()}
    if "notNeeded" in d: d["notNeeded"] = doc_list(d["notNeeded"])
    if "fees" in d: d["fees"] = {rn(a): b for a, b in d["fees"].items()}
    if "freeForSoleTraders" in d: d["freeForSoleTraders"] = doc_list(d["freeForSoleTraders"])
    f = x["companies"]["forms"]; x["companies"]["forms"] = {FORMS.get(a, a): b for a, b in f.items()}
json.dump(c, open(p, "w"), separators=(",", ":"), ensure_ascii=False)
print("done")
