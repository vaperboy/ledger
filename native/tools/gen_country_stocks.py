#!/usr/bin/env python3
"""Gives every country its own listed companies (flavour.stocks in countries.json): local words from the country's own company-name
roots plus sector nouns in its language. Norway keeps its hand-written names (re-keyed to the neutral tickers). Idempotent."""
import json, pathlib
p = pathlib.Path(__file__).resolve().parent.parent / "Engine/Sources/Countries/Resources/countries.json"
c = json.load(open(p))
TICKERS = ["ENRG", "FOOD", "BANK", "INDU", "TELE", "MATL", "RETL", "TECH", "TRAN", "PROP"]
OLD = {"NRDK": "ENRG", "FJSF": "FOOD", "HVBK": "BANK", "STVK": "INDU", "TLNR": "TELE", "SKOG": "MATL", "RETL": "RETL", "TECH": "TECH", "SHIP": "TRAN", "EIEN": "PROP"}
EN = ["Energy", "Foods", "Bank", "Industries", "Telecom", "Materials", "Retail Group", "Software", "Transport", "Property"]
NOUNS = {
 "DE": ["Energie", "Lebensmittel", "Bank", "Industrie", "Telekom", "Rohstoffe", "Handel", "Software", "Logistik", "Immobilien"],
 "CH": ["Energie", "Lebensmittel", "Bank", "Industrie", "Telekom", "Rohstoffe", "Handel", "Software", "Logistik", "Immobilien"],
 "FR": ["Énergie", "Alimentaire", "Banque", "Industries", "Télécom", "Matériaux", "Distribution", "Logiciels", "Transport", "Immobilier"],
 "ES": ["Energía", "Alimentación", "Banco", "Industrias", "Telecom", "Materiales", "Comercio", "Software", "Transporte", "Inmobiliaria"],
 "MX": ["Energía", "Alimentos", "Banco", "Industrias", "Telecom", "Materiales", "Comercio", "Software", "Transporte", "Inmobiliaria"],
 "IT": ["Energia", "Alimentare", "Banca", "Industrie", "Telecom", "Materiali", "Distribuzione", "Software", "Trasporti", "Immobiliare"],
 "BR": ["Energia", "Alimentos", "Banco", "Indústrias", "Telecom", "Materiais", "Varejo", "Software", "Logística", "Imóveis"],
 "NL": ["Energie", "Voeding", "Bank", "Industrie", "Telecom", "Grondstoffen", "Retail", "Software", "Transport", "Vastgoed"],
 "SE": ["Energi", "Livsmedel", "Bank", "Industri", "Telekom", "Råvaror", "Handel", "Programvara", "Transport", "Fastigheter"],
 "DK": ["Energi", "Fødevarer", "Bank", "Industri", "Telekom", "Råstoffer", "Detail", "Software", "Transport", "Ejendomme"],
 "FI": ["Energia", "Elintarvike", "Pankki", "Teollisuus", "Telekom", "Raaka-aine", "Kauppa", "Ohjelmisto", "Kuljetus", "Kiinteistö"],
 "PL": ["Energia", "Spożywcze", "Bank", "Przemysł", "Telekom", "Surowce", "Handel", "Oprogramowanie", "Transport", "Nieruchomości"],
 "LT": ["Energija", "Maistas", "Bankas", "Pramonė", "Telekomas", "Žaliavos", "Prekyba", "Programinė įranga", "Transportas", "Nekilnojamasis turtas"],
}
SKIP = {"grand", "nova", "grupo", "great", "nueva", "nuevo", "gran", "grande", "belle", "atelier", "nord", "south", "northern", "southern"}
for x in c:
    old = (x.get("flavour") or {}).get("stocks")
    if x["code"] == "NO" and old:
        x["flavour"]["stocks"] = {OLD.get(k, k): v for k, v in old.items()}
        continue
    words = []
    for w in x["names"]["companyStart"]:
        w = w.strip()
        if len(w) >= 4 and w.lower() not in SKIP and w not in words: words.append(w)
    nouns = NOUNS.get(x["code"], EN)
    names = {}
    for i, t in enumerate(TICKERS):
        w = words[(i * 2) % len(words)] if len(words) > 5 else words[i % len(words)]
        names[t] = f"{w} {nouns[i]}"
    x.setdefault("flavour", {})["stocks"] = names
json.dump(c, open(p, "w"), separators=(",", ":"), ensure_ascii=False)
print({x["code"]: list(x["flavour"]["stocks"].values())[:3] for x in c if x["code"] in ("UK", "DE", "JP", "PL")})
