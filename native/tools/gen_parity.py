#!/usr/bin/env python3
"""Generate docs/PARITY_CHECKLIST.md from the inventory of the original game (docs/data/original_inventory.json).

The inventory was dumped from the live HTML game by tools/ref/snippets/inventory.js. The *status* of each item is the
dictionary below: edit it when something gets ported. Items not listed are "not ported". Run:  python3 tools/gen_parity.py
"""
import json, pathlib, collections

root = pathlib.Path(__file__).resolve().parent.parent
inv = json.load(open(root / "docs/data/original_inventory.json"))
trades_json = json.load(open(root / "Engine/Sources/Businesses/Resources/trades.json"))
trade_items = list(trades_json["trades"].values())

# Status vocabulary
V = "Verified"      # compared with the original by a differential test (same inputs, same outputs)
S = "Statistical"   # ported and compared with the original on average results over many seeds
P = "Ported"        # ported in the engine, covered by tests that check the books, but not compared number for number
E = "Engine only"   # logic exists in the engine and is tested; no screen yet
U = "Engine + screen"  # ported and reachable in the native app (screen not run on a device yet)
N = "Not ported"

# ---- screens of the original -> native screen
screens = {
 "home": ("Home", U), "lux": ("Phone > Luxury", U), "shop": ("Company > Equipment, fleet and premises > shop", U), "title": ("StartView", U), "start": ("StartView (new game)", U), "menu": ("StartView", U),
 "bank": ("Phone > Bank", U), "invest": ("Phone > Invest", U), "tax": ("Phone > Tax", U), "news": ("Phone > News", U),
 "stats": ("Phone > Stats", U), "settings": ("Phone > Settings", U), "msgs": ("Inbox", U), "mail": ("Inbox", U),
 "co": ("Companies > company", U), "chain12": ("Company > Chain", U), "chain27": ("Company > Chain > Supply", U), "franchises": ("Group > Join a franchise", U), "brandneg": ("Group > Join a franchise > meeting", U), "frtalk56": ("Company > Chain > Franchise talk", U), "cos": ("Companies", U), "pickco": ("Companies", U), "group": ("Group", U),
 "newco": ("Phone > New company", U), "newbiz": ("Phone > New company", U), "hire": ("Company > Team", U),
 "payself": ("Company > Money", U), "mkt36": ("Company > Marketing", U), "mktdetail": ("Company > Marketing", U),
 "payroll29": ("Inbox decision (payroll approval)", U), "phonehome": ("Phone", U), "over": ("GameOverView", U),
 "weekreport": ("Home + Inbox + Activity (no single report screen yet)", N), "reports": ("Home + Inbox", N),
 "pricemoves": ("Company > Operations (price slider)", U),
 "tnd56": ("Company > Projects (tenders)", U),
 "clubs": ("Phone > New company > Football club", U), "holdings": ("Companies > Holding companies", U), "newhold": ("Phone > New company > Holding company", U),
}
screen_rows = [(s, *screens.get(s, ("", N))) for s in inv["screens"]]

# ---- company tabs of the original
tabs = {
 "ov": ("Company > Overview", U), "chainGrow": ("Company > Chain", U), "supplyChainRow": ("Company > Chain > Supply", U), "setupOv": ("Company > Setup", U), "plCard": ("Company > Money (P&L)", U), "finSummary": ("Company > Money", U),
 "ppl": ("Company > Team", U), "marketing": ("Company > Marketing", U), "mkt": ("Company > Marketing", U), "priceInfo": ("Company > Operations", U),
 "famOv": ("Company > Projects / Properties / Book (figures)", U), "famAssets": ("Company > Properties", U), "famOps": ("Company > Book (insurance products)", U),
 "doc": ("Company > Setup (documents via quick setup)", U), "eq": ("Company > Equipment, fleet and premises (Setup and Operations)", U),
 "famOv": ("Company > Plant / Fish (energy, salmon)", U), "famAssets": ("Company > Plant (turbines, fields, stakes)", U),
 "clubPeople": ("Company > Club > Staff", U), "clubSp": ("Company > Club > Sponsors", U), "clubTable": ("Company > Club > Table", U),
}
tab_rows = [(t, *tabs.get(t, ("", N))) for t in inv["companyTabs"]]

# ---- actions of the original -> engine function
actions = {
 "nextday": ("GameEngine.nextDay", U), "untilneeded": ("GameEngine.advanceUntilNeeded", U),
 "startgame": ("GameEngine.newGame", U), "newgame": ("GameEngine.newGame", U), "newgame2": ("GameEngine.newGame", U), "menunew": ("GameEngine.newGame", U),
 "loadfile": ("LegacyImporter", U), "loadpaste": ("LegacyImporter", U), "menuload": ("SaveStore.load / LegacyImporter", U), "savefile": ("SaveStore.save", U),
 "found": ("PlayerActions.startCompany", U), "ns13go": ("PlayerActions.startCompany", U), "ns13city": ("PlayerActions.startCompany(cityID:)", U), "ns13size": ("PlayerActions.startCompany(size:)", U),
 "hsearch": ("PlayerActions.searchWorkers", U), "hirego": ("PlayerActions.hire", U), "firestaff": ("PlayerActions.fire", U), "doraise": ("PlayerActions.raise", U),
 "setmkt": ("PlayerActions.setCampaign", U), "ownhrs": ("PlayerActions.setOwnerHours", U), "maint": ("PlayerActions.setMaintenance", U),
 "stockpol": ("PlayerActions.setStockPolicy", U), "setknob": ("PlayerActions.setKnob", U), "pricestep": ("PlayerActions.setPriceLevel", U),
 "cinject": ("PlayerActions.putMoneyInto", U), "cdraw": ("PlayerActions.takeMoneyOut", U), "cdiv": ("PlayerActions.payDividend", U),
 "perloango": ("PlayerActions.takeLoan(kind: cons)", U), "loango": ("PlayerActions.takeLoan", U), "repaygo": ("PlayerActions.repayLoan", U),
 "opendep": ("PlayerActions.openDeposit", U), "invsheet": ("PlayerActions.buyInvestment", U), "sellinv": ("PlayerActions.sellInvestment", U),
 "openmsg": ("Inbox", U), "msgpick": ("GameEngine.answer", U), "opendec": ("GameEngine.answer", U),
 "pr29ok": ("Payday.answer", U), "pr29mode": ("PlayerActions.setPayrollMode", E), "pr29day": ("Payday", E), "pr29run": ("Payday", E),
 "premset": ("GameEngine.takePremises", U), "premsheet": ("GameEngine.premisesListings / takePremises", U), "buyeq": ("EquipmentMarket.buyNew", U),
 "eqbrand": ("EquipmentMarket.offers", U), "eqpick": ("EquipmentMarket.offers", U), "eqmode": ("EquipmentMarket.Payment", U), "eq39buy": ("GameEngine.buyEquipmentItem", U), "eq39cls": ("Equipment shop class filter", U),
 "eqsheet": ("Company > Equipment, fleet and premises", U), "eqtab": ("Company > Equipment, fleet and premises (tabs)", U),
 "shopbuy": ("GameEngine.buyEquipmentItem / buyVehicleItem / buyUsedItem", U), "shopcls": ("Equipment shop", U), "shoppay": ("Equipment shop", U), "shopq": ("Equipment shop", U),
 "shopsel": ("Equipment shop", U), "shopt": ("Equipment shop", U), "shopvc": ("Equipment shop (vehicle make list)", U),
 "subpick": ("GameEngine.subscribeSoftware", U), "subcancel": ("GameEngine.cancelSubscription", U),
 "sellunit": ("GameEngine.sellEquipmentUnit", U), "selleq": ("GameEngine.sellAllEquipment", U), "sellveh": ("GameEngine.sellVehicle", U), "repaireq": ("GameEngine.serviceEquipment", U),
 "luxbuygo": ("GameEngine.buyLuxury", U), "luxsell": ("GameEngine.sellLuxury", U), "lxbuy": ("GameEngine.buyLuxury", U), "lxgo": ("Phone > Luxury", U),
 "lx56": ("Phone > Luxury (manage a piece)", U), "lx56use": ("GameEngine.setLuxuryUse", U), "lx56co": ("GameEngine.buyLuxury(throughCompany:)", U), "lx56cogo": ("GameEngine.buyLuxury(throughCompany:)", U),
 "est56mode": ("GameEngine.setCastleOpen", U), "est56ret": ("GameEngine.hostIslandRetreat", U), "est56off": ("GameEngine.takeWeekOffOnIsland", U),
 "applydoc": ("Documents", E), "applydoc2": ("Documents", E), "estlog": ("", N),
 "club24buy": ("GameEngine.signPlayer", U), "clubbuy": ("GameEngine.offerForClub", U), "clubclose": ("GameEngine.buyClub", U), "clubfound": ("GameEngine.foundClub", U),
 "clubfind": ("GameEngine.clubCandidates", U), "clubhire": ("GameEngine.hireCoach", U), "clubfire": ("GameEngine.dismissCoach", U), "clubspon": ("GameEngine.signSponsor", U),
 "clubtix": ("GameEngine.setClubTicketLevel", U), "clubwage": ("GameEngine.setClubWageShare", U), "clubofferx": ("GameEngine.offerForClub", U),
 "holdin": ("GameEngine.holdingInvest", U), "holdout": ("GameEngine.holdingDivest", U), "injhold": ("PlayerActions.putMoneyInto", U), "newhold": ("GameEngine.createHolding", U), "tohold": ("GameEngine.moveToHolding", U),
 "oilacq": ("GameEngine.buyOilStake", U), "oilbuy": ("GameEngine.buyOilStake", U), "oilexp": ("GameEngine.exploreForOil", U),
 "mgrsearch": ("GameEngine.searchManagers (Company > Team)", U), "mgrsearch56": ("GameEngine.searchManagers (Company > Team)", U), "mgrask": ("GameEngine.interviewManager (Company > Team)", U),
 "mgrref": ("GameEngine.checkManagerReferences (Company > Team)", U), "mgrhirego": ("GameEngine.hireManager (Company > Team)", U), "mhire56": ("GameEngine.hireManager (Company > Team)", U),
 "mgrgo": ("Company > Team", U), "mgrraise": ("GameEngine.giveManagerRaise (Company > Team; the yearly raise ask is answered in the Inbox)", U), "mgrfire": ("GameEngine.dismissManager (Company > Team)", U),
 "mgrmove": ("GameEngine.moveManager (Company > Team)", U), "mgrmovego": ("GameEngine.moveManager (Company > Team)", U), "askmgr": ("GameEngine.askManager (Company > Team)", U),
 "authlvl": ("GameEngine.setManagerAuthority (Company > Team)", U), "authbuy": ("GameEngine.setManagerAuthority (Company > Team)", U), "authhire": ("GameEngine.setManagerAuthority (Company > Team)", U),
 "authad": ("GameEngine.setManagerAuthority (Company > Team)", U), "oa59meet": ("GameEngine.meetManager (Company > Team)", U),
 "asstsearch": ("GameEngine.searchAssistants (Company > Team)", U), "asstsearch56": ("GameEngine.searchAssistants (Company > Team)", U), "asstgo": ("GameEngine.hireAssistant (Company > Team)", U),
 "asstduty": ("GameEngine.toggleAssistantDuty (Company > Team)", U), "asstfire": ("GameEngine.dismissAssistant (Company > Team)", U),
 "promosheet": ("PromotionSheet (Company > Team > Promote)", U), "p11talk": ("GameEngine.promotionPosts (Company > Team > Promote)", U), "p11set": ("PromotionSheet", U), "p11offer": ("GameEngine.offerPromotion (Company > Team > Promote)", U),
 "p11back": ("PromotionSheet", U), "p11duty": ("", N), "promoteact": ("PromotionSheet", U),
 "salary": ("PlayerActions.setOwnerSalary", E), "tcAS": ("CompanySetup.create(accountantID:)", E),
 "reopen": ("", N),
 "propsheet": ("GameEngine.propertyListings", U), "buyprop": ("GameEngine.buyProperty", U), "sellprop": ("GameEngine.sellProperty", U), "renprop": ("GameEngine.renovateProperty", U),
 "marketprop": ("GameEngine.tenantOffers", U), "leaseprop": ("GameEngine.leaseSpace", U), "sellto": ("GameEngine.sellBuilding", U),
 "prodtog": ("GameEngine.setInsuranceProduct", U), "f17prod": ("GameEngine.verifySalesperson", U),
 "devgo": ("GameEngine.startDevelopment (Company > Projects)", U), "devprice": ("GameEngine.setDevelopmentPrice (Company > Projects)", U), "devsheet": ("GameEngine.developmentQuote (Company > Projects)", U),
 "tnd56go": ("GameEngine.bidOnTender (Company > Projects)", U), "tnd56re": ("GameEngine.withdrawBid (Company > Projects)", U), "tnd56auto": ("GameEngine.setManagerBids (Company > Projects)", U),
 "ch12make": ("GameEngine.makeChain", U), "ch12new": ("GameEngine.openChainStore", U), "ns13go": ("GameEngine.openChainStore", U), "ch12rule": ("GameEngine.setChainRule", U), "ch12off": ("GameEngine.setStoreRule", U), "ch12join": ("GameEngine.joinChain", U),
 "brandapply": ("GameEngine.applyToFranchiseBrand", U), "brandopen": ("Franchise meeting", U), "negsend": ("GameEngine.negotiateFranchise", U), "negsign": ("GameEngine.signFranchiseTerms", U), "brandstart": ("GameEngine.startFranchisedCompany", U), "brandfacts": ("Franchise meeting > Facts", U),
 "frlaunch": ("GameEngine.launchFranchise", U), "frt56go": ("GameEngine.offerToApplicant", U), "fr24term": ("GameEngine.terminateFranchiseUnit", U), "frmast": ("GameEngine.sellMasterFranchise", U), "fb24leave": ("GameEngine.leaveFranchise", U),
 "ch27set": ("GameEngine.setSupplier", U), "ch27off": ("GameEngine.clearSupplier", U),
 "tnd56set": ("Company > Projects (bid price and quality choice)", U),
}
action_rows = [(a, *actions.get(a, ("", N))) for a in inv["actions"]]

# ---- systems (the pipelines of the original, grouped by what they do)
systems = [
 ("Seeded random numbers (Z, hrng)", "GameCore/DeterministicRandom, HashedRandom", V, "FoundationTests, golden currency_tax_rng"),
 ("Calendar, month/year ends", "GameCore/GameCalendar", V, "FoundationTests"),
 ("Currency, exchange rates, euro drift, price rounding", "Countries/Currency", V, "golden currency_tax_rng"),
 ("23 countries: taxes, VAT, wages, rent, cities, names", "Countries/Country, countries.json", V, "golden countries_derived"),
 ("Income tax, wealth tax, dividend tax", "Countries/Taxes, Finance/PersonalFinance", V, "PersonalFinanceDifferentialTests"),
 ("67 trade definitions and calibration", "Businesses/TradeCatalog, trades.json", V, "golden trades_calibrated"),
 ("Annuity loans, credit score, loan offers, repayment", "Finance/Annuity, Banking", V, "FinanceDifferentialTests"),
 ("Cash ledger (every movement booked, gaps detectable)", "Finance/Ledger", P, "SimulationSmokeTests (no gaps after months)"),
 ("Company payments, monthly-bill accrual, VAT, dividends", "Finance/Payments, Businesses/Vat", V, "FinanceDifferentialTests"),
 ("Demand: local market, fit, price, affordability, ways to sell, weather, tourists, premises, owner attention", "Businesses/Demand", V, "oracle_demand_cap, CompanyModelDifferentialTests"),
 ("Capacity and equipment limits", "Businesses/Capacity", V, "oracle_demand_cap"),
 ("Daily retail trade (real days, stock, shelf)", "Businesses/DailyTrade, Shelf, StockHandling", S, "cafe_weeks golden; docs/BALANCE_PARITY.md"),
 ("Company valuation and net worth", "Businesses/Valuation", V, "nw_cafe_week* goldens"),
 ("Marketing channels, awareness, campaign customers", "Businesses/Marketing", P, "unit tests; not compared number for number"),
 ("Quality and reputation", "Businesses/QualityModel", P, "smoke"),
 ("Customer complaints (arrive, managers answer, unanswered become bad reviews)", "Businesses/Satisfaction", P, "SimulationSmokeTests; effect on reputation compared in BALANCE_PARITY"),
 ("Word of mouth, buzz, limit of a local name, closing when nobody works", "Businesses/Satisfaction", P, "awareness and reputation track the original (BALANCE_PARITY)"),
 ("Paperwork for new people and inspection fines; commission mishaps; hidden talent", "Businesses/StaffExtras", P, "fine totals compared in BALANCE_PARITY"),
 ("Equipment units: wear per unit, breakdowns, warranty, repair cost, downtime", "Businesses/EquipmentUnits", P, "units carry brand, class and reliability; warranty text and wear as the original"),
 ("Text tokens {auth:..} {m:..} resolved per country", "Countries/TextTokens", V, "TextTokenTests"),
 ("Staff: skill, learning, tiredness, sickness, quitting, seasonal staff", "Employees, Businesses/StaffRoutine", P, "smoke"),
 ("Hiring and firing, candidate generation", "Businesses/Hiring", P, "PlayerActionsTests"),
 ("Payday on the real date, payroll approval, month-end bills", "Simulation/Payday", P, "SimulationSmokeTests (staffing)"),
 ("Month-end and year-end tax settlement for companies", "Simulation/MonthEnd", P, "SimulationSmokeTests"),
 ("Bankruptcy, forced sale, overdraft rules", "Simulation/Failure", P, "smoke"),
 ("World economy, interest rate, competitors, disruptions", "Simulation/WorldWeek", P, "smoke"),
 ("Stocks, crypto, funds, savings, fixed deposits", "Investments", P, "PlayerActionsTests"),
 ("133 random events with weighted choices and expiry", "Events", P, "data equals the original; firing is smoke-tested"),
 ("Event consequence previews", "Events/EffectPreview", P, "PreviewAndAdvisorTests"),
 ("Save: legacy JSON / LZ1 / LZ64 import, native envelope, backups, atomic write", "SaveSystem", V, "LZStringTests, SaveRoundTripTests, SaveStoreTests"),
 ("Rental businesses (3 trades): properties, tenants, vacancy, rent policy, maintenance, mortgages, valuation with the housing market", "Businesses/RentalModel", V, "RentalFinanceDifferentialTests (weekly model, listings, buy/renovate/sell, leases, valuation against the original)"),
 ("Insurance company: products and approvals, verified salespeople, premiums, claims, storms, solvency and regulator", "Businesses/FinanceModel", V, "RentalFinanceDifferentialTests (weekly model, products, f_storm); balance bands in RentalFinanceBalanceTests"),
 ("Bank: deposits, loan book, spread, loan losses, runs, capital ratio, central bank liquidity facility", "Businesses/FinanceModel", V, "RentalFinanceDifferentialTests (weekly model, f_run, f_default); bank run and regulator closure in RentalFinanceTests"),
 ("Investment fund: assets under management, flows, fees, performance fee at year end", "Businesses/FinanceModel", V, "RentalFinanceDifferentialTests (weekly model, year-end fee, redemptions)"),
 ("Regulator closes a bank or insurer whose capital is gone (not in the original)", "Businesses/FinanceModel.insolventCompanies", P, "RentalFinanceTests"),

 ("Project businesses: jobs in hours, milestone payments, receivables, overruns, defects (plumber, electrician, construction, engineering office, event agency)", "Businesses/ProjectModel, ProjectWeek", V, "ProjectDifferentialTests (demand, hour value, hours a week, mix against the original); balance probe in BALANCE_PARITY. Price and demand carry a native calibration"),
 ("Real-estate development: land, zoning, building, units sold, construction loan, housing market", "Businesses/ProjectDeveloper", V, "ProjectDifferentialTests (land, build, units, price, cash); statistical balance probe"),
 ("Tenders for building, design and event work (bids, scoring, awards, managers who bid)", "Businesses/ProjectTenders", P, "ProjectTradeTests; the volume contracts the original also tenders for are not ported"),

 ("Service, venue, retail, production, logistics families (50 trades)", "Businesses/CompanyWeek", S, "statistical comparison; gym is +31% (open)"),
 ("Energy: renewable power producer (turbine build time, source, hedging) and oil and gas (fields, stakes, exploration, development loans, discoveries)", "Businesses/EnergyModel", P, "SpecialTradesDifferentialTests: weekly arithmetic equals the original with fixed random draws; SpecialTradesTests: books balance, balance probe"),
 ("Salmon farm (cohorts, growth, disease, harvest at the market price)", "Businesses/SalmonModel", P, "SpecialTradesDifferentialTests: 90 weeks of cohorts equal the original; random disease and events smoke-tested"),
 ("Holding companies (stakes, index fund, dividends up and down, net worth, tax group, failure)", "Businesses/HoldingModel", P, "SpecialTradesTests; listing on the exchange and raising money by selling shares not ported"),
 ("Football clubs (league, season, table, tickets, TV, sponsors, wages, transfers, coaches, buying and founding)", "Businesses/FootballModel", P, "SpecialTradesDifferentialTests: clubs of a league equal the original; the random match draw is a shuffle, not the original's random sort"),
 ("Pay talks: people ask for a raise or a fixed salary, the answer changes pay and mood", "Businesses/StaffTalks", P, "StaffTalksTests"),
 ("Strategic decisions (ev27): 66 of 79 ported (startup, growth, established, crisis, group and general ones, 41 country events); poaching, rival merger/distress sales, listing, private equity, hostile takeover, antitrust, activist, auction, new-site and franchise offers not ported", "Events/StrategicDecisions", U, "DecisionsTests: every decision fired and every answer taken, books balance; defaults on timeout"),
 ("Poaching of the best worker (g_poach: match, bonus or let go) and of the manager (match or let go); the other 50 'strategic' decisions (ev27)", "Events/EventEffects, Businesses/ManagerPeople", P, "ManagementTests for the manager side; the ev27 decisions are in KNOWN_GAPS"),
 ("Realistic equipment buying: brands and models, used market, leasing, subscriptions", "-", N, "quickSetup buys standard equipment at the standard price"),
 ("Key accounts (business customers)", "-", N, ""),
 ("Assistant managers (two jobs: complaints, paperwork, equipment; pay; let go)", "Businesses/ManagerPeople", P, "ManagementTests; the monthly suggestion and basic insurance are not ported"),
 ("Managers: find (search, interview, references), hire, authority, pay review, proposals, yearly raise, resign and notice, rival offer, move, replace, ask for changes, meetings", "Businesses/ManagerModel, ManagerPeople, ManagerWeek", P, "ManagementTests; buying equipment, vehicles and space and the profit bonus are not ported"),
 ("Promotions: a worker to a higher role or to manager, with the pay talk and patience", "Businesses/ManagerPeople", P, "ManagementTests; duties, authority, bonus and shares in the offer, and the analyst report are not ported"),
 ("Boards, votes, CEO and managing director, regional and chain managers, group executives", "-", N, "needs chains and shareholders first; listed in KNOWN_GAPS"),
 ("Chains (registration, new stores, shared rules, reach, buying discounts, brand marketing), franchising out (units, applicants and talks, royalties, arrears, renewals, master franchise), being a franchisee (brands, application, terms talk, royalties, quality standard, buyout), supply between your own companies", "Businesses/Chains, Franchising, FranchiseBrands, IntercompanySupply", P, "ChainsTests (books balance); no differential test; see KNOWN_GAPS"),
 ("Selling a company: quiet sale or broker, offers over weeks (private, fund, rival, management buyout), counter +8%, loans closed, staff released, tax gain", "Events/CompanySale", U, "DecisionsTests.testSellingACompany; selling part of the shares and raising funding not ported"),
 ("Startups you found, private equity funds, stakes in other groups", "net worth counts imported values only", N, ""),
 ("Luxury and estates, family office", "net worth counts imported values only", N, ""),
 ("Poaching of the best worker and the other 50 'strategic' decisions (ev27)", "-", N, "listed in KNOWN_GAPS"),
 ("Realistic equipment buying: brands and models, used market, leasing, subscriptions", "Businesses/EquipmentMarket + data equipment_brands.json", U, "catalogue, used listings, lease, finance, plans, licences, sell; supplier relationship discounts and per-person equipment rules not ported"),
 ("Key accounts (business customers), assistant managers", "-", N, ""),
 ("Managers and boards (managers who manage, board votes, CEO)", "partial: ManagerModel", N, "manager drift in demand only"),
 ("Chains (registration, new stores, shared rules, reach, buying discounts, brand marketing), franchising out (units, applicants and talks, royalties, arrears, renewals, master franchise), being a franchisee (brands, application, terms talk, royalties, quality standard, buyout), supply between your own companies", "Businesses/Chains, Franchising, FranchiseBrands, IntercompanySupply", P, "ChainsTests (books balance); no differential test; see KNOWN_GAPS"),
 ("Startups, private equity funds, stakes", "net worth counts imported values only", N, ""),
 ("Luxury and estates: cars, watches, art, yachts, jets, homes, estates; charter, rent, museum; company cars and jets", "Businesses/Luxury + data luxury.json", U, "fame, rest and abroad-fee perks, the tax-office check and margin call are not ported; the original has no family office"),
 ("Rivals as businesses, price wars, acquisitions", "-", N, "Competition affects demand only"),
 ("Software/IT products, cyber attacks, tenders for other trades", "-", N, ""),
 ("Achievements (trophy wall, 60 of the original's 90 or so), yearly business awards, rich list of the home country", "Events/Trophies, Events/RichList", U, "DecisionsTests.testTrophiesAwardsAndTheRichList; trophies that need chains, luxury, startups, rivals or rankings not ported; awards rank by net worth place"),
]

# ---- trades
fam_supported = {"svc", "venue", "retail", "prod", "logi", "project"}
rental_finance = {"resrent", "comrent", "parking", "insco", "bank", "fund"}   # RentalModel, FinanceModel: ported, family models verified
own_model = {"power", "oilgas", "salmon", "hold", "club"}
trade_rows = []
for t in trade_items:
    pass
for tid, name, fam, *_ in inv["trades"]:
    ok = fam in fam_supported and tid != "salmon"
    trade_rows.append((tid, name, fam, P if (tid in rental_finance or tid in own_model) else S if ok else N))

def table(rows, header):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)

def count(rows, idx):
    c = collections.Counter(r[idx] for r in rows)
    return ", ".join(f"{v} {k}" for k, v in sorted(c.items(), key=lambda kv: -kv[1]))

md = []
md += ["# Feature parity checklist", "",
       "Generated by `tools/gen_parity.py` from `docs/data/original_inventory.json` (a dump of the original HTML game: "
       f"{len(inv['countries'])} countries, {len(inv['trades'])} trades, {inv['events']} events, {len(inv['screens'])} screens, "
       f"{len(inv['actions'])} actions, {len(inv['companyTabs'])} company tabs, {len(inv['pipelines'])} extension pipelines).", "",
       "An item is only marked beyond *Not ported* when code for it exists **and** the status describes what was actually checked.", "",
       "| Status | Meaning |", "|---|---|",
       f"| {V} | compared with the original game on identical inputs by an automated test, results equal |",
       f"| {S} | compared with the original on average results over many seeds (random parts cannot match exactly) |",
       f"| {P} | ported; automated tests check it runs and keeps the books balanced; not compared number for number |",
       f"| {E} | logic ported and tested, no native screen yet |",
       f"| {U} | ported and reachable from a native screen. **The screens have not been run on a device or simulator by the author** (no Mac available); see KNOWN_GAPS |",
       f"| {N} | not in the native game yet |", "",
       "## Summary", "",
       f"- Systems: {count(systems, 2)}", f"- Trades: {count(trade_rows, 3)}",
       f"- Screens: {count(screen_rows, 2)}", f"- Company tabs: {count(tab_rows, 2)}", f"- Actions: {count(action_rows, 2)}", "",
       "## Systems", "", table(systems, ["System", "Where", "Status", "Evidence"]), "",
       "## Countries", "", "All 23 countries are data in `Countries/Resources/countries.json` (verified by golden `countries_derived`):", "",
       ", ".join(c[1] for c in inv["countries"]), "",
       "## Trades", "", table(trade_rows, ["Id", "Name", "Family", "Status"]), "",
       "## Events", "", f"All {inv['events']} events are in `Events/Resources/events.json` (formulas as `{{expr}}`). "
       "Event ids and count match the original; firing, deciders and answers are covered by smoke tests only, status: Ported.", "",
       "## Screens", "", table(screen_rows, ["Original screen", "Native", "Status"]), "",
       "## Company tabs", "", table(tab_rows, ["Original tab", "Native", "Status"]), "",
       "## Actions", "", table(action_rows, ["Original action", "Native / engine", "Status"]), "",
       "## Extension pipelines of the original", "",
       "The original game is built from `addStep` pipelines. The systems table above is the reliable summary; "
       "anything in the list below that is not named there as ported should be treated as **not ported**.", ""]
for k, steps in inv["pipelines"].items():
    md.append(f"<details><summary><code>{k}</code> ({len(steps)})</summary>\n")
    md += [f"- {s}" for s in steps]
    md.append("\n</details>\n")
(root / "docs/PARITY_CHECKLIST.md").write_text("\n".join(md))
print("written", len(md), "lines;", "screens", count(screen_rows, 2), "| actions", count(action_rows, 2))
