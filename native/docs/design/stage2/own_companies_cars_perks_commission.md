# Audit: own companies as suppliers, company cars, staff benefits, commission pay

Read-only audit, 23 Oct 2026, branch `native-swiftui` at 205dd3f. Nothing was implemented. Binding rules: `SIMULATION_RULES.md`, `DESIGN_RULES.md`.
Paths are under `native/Engine/Sources/` unless they start with `App/`. "V" = verified by reading the code and/or running a test; "I" = inference, not verified.

Tests run (Swift 6.0.3, `swift test`): `ChainsTests.testSupplyBetweenYourOwnCompaniesMovesMoneyAndBalances` passed (hotel buys cleaning from an own cleaning company at cost+10%, 20 weeks, `Ledger.gaps` empty). Temporary probe tests (deleted, not committed) gave the other numbers quoted below.

---------------------------------------------------------------------------------------------------

## 1. Own companies as suppliers / add-ons

### What exists
| Fact | Where | |
|---|---|---|
| 14 supply "kinds" are hard-coded in a Swift array. Each has the supplier trade(s), a "same city" flag, a book category and a table of buying trades with a share of sales spent: cleaning, building materials, freight, parcel delivery, bread, beer, produce, fish, furniture, web/IT, marketing, temp staff, vehicle service, warehousing, electricity | `Businesses/IntercompanySupply.swift:29-45` | V |
| An own company can supply a buyer only if same country, status open, trade in the kind's list (and same city if `local`). Cleaning, bread, temp staff, vehicle service are local | `IntercompanySupply.swift:86-88` | V |
| Link stored in `rest["l27"]`; the player picks supplier and price mode: market price / cost+10% / at cost | `:122-129`, `:48` | V |
| Money (weekly, `IntercompanySupply.weekly`, called from `Chains.weekly` `Chains.swift:463`): the buyer keeps its normal cost model; the saving `got*(1-pf)` is paid to the buyer as a rebate and booked as a negative cost in the kind's category (`:180-186`). The supplier books revenue `got*pf` (category `rev`) and cost of sales `got*varRatio` (`:188-191`). Both through `Payments`, so both sets of books move and cash balances | `:141-216` | V |
| Price: market = 1.0; cost+10% = `min(1, costRatio*1.1)`; cost = `min(1, costRatio)`; `costRatio` = supplier's own last-3-month cost/revenue, clamped 0.45-1.3. So a transfer price can never exceed the outside price | `:92-106` | V |
| Capacity: supplier's units for the group are held back from its own capacity next week (`int27u`, `Capacity.swift:174`). If supplier delivers less than 98%, the rest is bought outside at +20% and below 80% the buyer loses reputation | `:174-203` | V |
| Supply from inside shields the buyer from outside-supplier events (`g_supply`, `pr_raw`, `r_carrier` ...) if the kind counts as cost of sales | `Businesses/Sourcing.swift:18-30` | V |
| Own-company supply and "business customer" supply (`AccountSupply`, key accounts that run a supplier trade, relationship >= 22) replace each other for the same input | `AccountSupply.swift:76-83`, `IntercompanySupply.swift:124` | V |
| A separate hard-coded link: a car dealer with an own `factory` gets a 6%/12% wholesale rebate booked on both sides | `Chains.swift:441-449` (needs an open factory of yours with its "line" knob set) | V |
| Ledger: existing test asserts `Ledger.gaps` empty after 20 weeks. In my probe (restaurant + cleaning, modes mkt, c10, cost, 8 weeks each) `Ledger.gaps` stayed empty | `ChainsTests.swift:115-131` | V |
| Tax: no VAT on the transfer ("without VAT", `:10-11`); each company's profit tax follows its own books. No transfer-pricing rule, no check that cost-based prices are acceptable to a tax authority | `:10-11` | V |
| UI: Company > Chain > "Supply from your own companies": one row per input the company buys, tap shows own companies that can supply (three price buttons each, with yearly saving) plus business customers; "Back to outside suppliers"; the supplier side lists "Supplies X, n% delivered" | `App/Ledger/Features/Companies/CompanyChain.swift:167-262` | V |

### Which services/goods can be supplied by an own company
| Need | Own company possible? | Detail |
|---|---|---|
| Cleaning (office/venue) | Yes | kind `clean`, ~25 buying trades incl. restaurant 1.5% of sales, hotel 3.5% |
| Parcel delivery | Yes, only for webshop, boutique, pets, furniture | kind `parcel`; restaurant, cafe, bakery, hardware, grocery are NOT buyers |
| Meal/food delivery, delivery to sites | **No** | Restaurant add-on `xtra/deliv` "Delivery apps" is only `fx {d:1.12, t:0.9}` in `Businesses/Resources/trades.json` (no courier, no cost line). Hardware `deliv` is `fx {d:1.08, w:1200}`. Bakery, furniture, webshop, hardware have a delivery van as equipment instead |
| Freight, building materials, bread, beer, produce, fish, furniture, web, marketing, temp staff, vehicle service, warehousing, power | Yes (kinds above) | |
| Goods for resale/ingredients generally (the "goods supplier" chips, quality class) | **No** | `Suppliers.candidates` (`Suppliers.swift:49-54`) builds only generated outside vendors; no own-company option |
| Equipment repair/maintenance supplier (`fixv`) | **No** | same vendor pool. Only the `carserv` kind (carrepair -> taxi, courier, trucking, cardealer ...) is own-company |
| Security, accounting, legal, IT support, wholesale | **No kind** | I found no wholesale trade in the 67 trades; security/law/accounting trades exist but have no kind |

### Gaps
1. Delivery is not modelled as a service at all. The restaurant "delivery" add-on cannot use an own courier company, an outside courier, or staff; its cost is baked into ticket x0.9 (V).
2. Kinds are a Swift array, not data (breaks `ADDING_CONTENT.md` / SIMULATION_RULES 5 "data-driven"). Buyer shares are separate from the add-on's own cost (I: two sources of truth if delivery were added naively).
3. The UI hides the row when no own supplier exists: `shown` requires an existing link, a possible own supplier or a business-customer candidate (`CompanyChain.swift:177`). There is no "start a courier company" path (V).
4. Add-ons / how-you-sell options (`Knobs`) have no supplier concept; `SalesWays` add-ons (`platform`, `members`, `emergency`, `upsell`) are separate and pay fixed fees.
5. Arm's-length: modes below market are allowed with no tax consequence and no limit; fine inside one country, but there is no rule if buyer and supplier have different legal forms/owners/minority holders (I: a partly owned supplier subsidises the buyer; `GroupStakes` not consulted - not checked).
6. In my probe the new cleaning company was loss-making, so `costRatio >= 1` and cost+10% / cost gave `pf = 1.0` and zero saving; correct per the rule, but the UI still labels the buttons "saves" only if `pf < 1` (V, UI line).
7. No tests for kinds other than `clean`; no test that the shield, held-back capacity or the 98%/80% shortfall rules fire.

### Proposed small batches (item 1)
**1A. Make supply kinds data (no behaviour change).** Purpose: SIMULATION_RULES 5, adding delivery needs data. Move `kinds` to `Resources/supply_kinds.json` (id, name, suppliers, local, category, noCapacity, buyers). Tests: golden equality of the 14 kinds vs the Swift array before deletion; existing chain tests unchanged.
**1B. Delivery as a service (restaurant, cafe, bakery, foodtruck, hardware, grocery).** Purpose: restaurant delivery needs couriers; the player chooses outside couriers or an own courier company. Reuse: `IntercompanySupply` link + `AccountSupply` + the existing `deliv` knob option. Interactions: the knob keeps its demand effect `d`; the app commission stays for "apps"; a new option "Own delivery" (knob `delivown`, same `d`) gets an explicit cost share `c` in trades.json and a new kind `meal` whose `buyers` share is that same cost share (derive, do not duplicate). Outside supplier = the cost share at market; own courier at market/cost+10%/cost with the existing rebate mechanism; courier capacity held back; couriers' `food` segment (already a courier knob) is the supplier side. No new cap: the courier's capacity is what limits it (if the courier is short, existing +20% emergency premium applies). Rule data to author: cost share per trade (needs a source; not invented here), which trades offer own delivery. Tests: gaps clean over 20 weeks; courier shortage lowers delivered share and charges the premium; switching back leaves the add-on running at the outside cost; multi-seed restaurant with/without own courier.
**1C. UI: pick "my own company" from the place where the need arises, and start the missing one.** Show the provider row in the add-on / how-you-sell picker (and keep the Chain card), with three choices: Outside / My company X (price mode) / "Start a courier company here" which opens the New company flow with trade and city pre-filled and returns to the add-on. Reuse `CompaniesView` route `.newCompany`, `GameStore.openCompany(id, section:)`. Always show the saving or cost before confirming (DESIGN_RULES).
**1D. Own supplier for goods and repairs.** Add own companies (matching trade) to `Suppliers.candidates` for scope `goods`/`fix` as a vendor with price from the transfer mode, so the Suppliers chips can pick them; remove the dual path once covered by 1A kinds. Only after 1A-1C.
**1E. Arm's-length guard (rule data per country).** Optional `transferPricing` flag in country tax data: when on, cost-based modes are booked at market for tax purposes (or a note/warning). Needs sources in `TAX_SOURCES.md` first; do not guess.

---------------------------------------------------------------------------------------------------

## 2. Company cars and fleets

### What exists (V unless marked)
| Fact | Where |
|---|---|
| 24 of 67 trades have vehicle equipment (field `vo` in trades.json): carclean, handy, cleaning, drivsk, estate, pets, foodtruck, webshop, hardware, cardealer, construction, electrician, plumber, event, bakery, brewery, furniture, taxi, courier, trucking, shipping, airline, security, carrental | `Businesses/Resources/trades.json` |
| No vehicle (43): tutor, photo, webdev, mktg, law, acctfirm, staffing, barber, physio, carrepair, cafe, restaurant, nightclub, gym, hotel, casino, fun, skires, indoorski, kiosk, boutique, grocery, realdev, engcons, salmon, factory, farm, wh3pl, resrent, comrent, parking, insco, bank, fund, power, oilgas, dental, gamestudio, vineyard, pcbang, cons, hold, club | same |
| Per-person need rules (a van per 3 cleaners, a car per estate agent ...) are a Swift table of 24 entries | `Businesses/PersonalEquipment.swift:22-33` |
| Purchase: cash (asset, no expense), finance (20% down, 80% loan, 60 months), lease (monthly = 2.15% of price, book value 0, 3-year warranty) | `CompanySetup.swift:240-275` |
| Depreciation weekly to `dep` by class (van 15%, car 16%, truck 12%, bike 20% a year); condition wear; upkeep 1.3x equipment rate unless leased | `CompanyCosts.swift:156-171` |
| Lease payment weekly to `oth` | `CompanyWeek.swift:401-404` |
| Fuel: only trades with a `fuel` trait (taxi, courier, trucking, shipping, airline): `costRate += fuel*(economy.fuel-1)` (`CompanyWeek.swift:147`), plus extra fuel for bigger courier/trucking vans (`PersonalEquipment.swift:116-123`). The `km` trait only advances the odometer (`CompanyCosts.swift:168`) and the breakdown chance (`EquipmentUnits.swift:210`) | |
| Insurance: no motor/fleet product in `INSP` (prop, liab, cyber, bi, key, prof). Vehicles count in the book value that sets the property premium (`CompanyFigures.swift:13-18`, `CompanyCosts.swift:112`) | |
| Tax: no road tax, no benefit-in-kind for staff cars. BIK exists only for luxury items bought through a company (`Luxury.swift:207`) | |
| Perk "Company car" (5500/month per manager and team lead, quit x0.82, manager mood) is a separate flag with no vehicle behind it | `StaffPerks.swift:32` |
| Own car with mileage exists for estate agents only: `offersOwnCar` is `bd.id == "estate"`; hire sheet offers "Own car"; staff menu toggles it | `PersonalEquipment.swift:158`, `App/.../CandidateSheet.swift:21`, `CompanyOtherSections.swift:174-179` |
| Mileage is a flat 4500/month (scaled) per own-car person, independent of distance | `PersonalEquipment.swift:115` |
| Demand effect of a luxury car for estate/cardealer (+5% x share of luxury) and taxi class | `PersonalEquipment.swift:138-153` |

### Defects found
- **Mileage is booked twice.** `PersonalEquipment.weeklyCosts` (`:114-115`, from `CompanyWeek.swift:410`) and `StaffRoutine.weekly` (`StaffRoutine.swift:92`, label "Mileage for own cars", from `CompanyWeek.swift:421`) both pay `scaledPrice(4500)*12/52` per own-car person. Test: estate company, same seed, one agent on own car vs not, 4 weeks: `oth` books +8304 = 7.996 weeks of one agent's mileage (expected 4). (V)
- Duplicated dead code: `StaffTalks.toggleOwnCar` (`StaffContracts.swift:199`) has no callers; `PersonalEquipment.toggleOwnCar` is the live one. The company-car-vs-own-car state is inconsistent in meaning: the estate trade requires "Company cars" equipment but an own-car agent subtracts from the need (`PersonalEquipment.swift:60`).

### Where cars would sensibly matter but there are none (I - judgement)
| Trade | Who travels | Today |
|---|---|---|
| staffing, mktg, insco (agents), factory/brewery/furniture/hardware sales, vineyard | sales reps (roles in `SALES_ROLES`) | no vehicle; `sales` role not in `PersonalEquipment.table` |
| law, acctfirm, engcons, realdev, tutor, photo, physio, dental (home visits) | visit clients/sites | none |
| cons (consulting), webdev | client visits | none |
| restaurant, cafe, grocery, boutique (delivery) | couriers | none (see item 1) |
| factory, wh3pl, farm | deliveries, yard vehicles | factory/wh3pl have none; farm has no tractor/vehicle |
| hotel (shuttle), resrent/comrent (caretaker van), parking | | none |
| Vehicle trades without fuel: cleaning, plumber, electrician, construction, handy, carclean, pets, bakery, brewery, furniture, hardware, webshop, event, security, carrental, drivsk, estate | | depreciation/upkeep only; no running cost per km |

### Proposed small batches (item 2)
**2A. Fix the mileage double count** (bug, no design). Keep one booking (PersonalEquipment, or StaffRoutine with a label), delete the other; regression test = the 4-week probe above (expect 4 weeks). Also delete the dead StaffContracts duplicates.
**2B. Vehicle running cost for every vehicle trade.** Reuse the `VEH` table (column 4 is already the fuel factor used for couriers) x `km` trait x `economy.fuel`; electric models cheaper via the same column. Author `km` for the trades that lack it (data, needs a source/estimate flagged as such). Replace the courier/trucking special case with this one path. Tests: multi-seed courier ROI unchanged within noise (do not retune to a band), plumber gains a fuel line, EV vs diesel van.
**2C. Move `PersonalEquipment.table` to data and add roles** (sales reps for mktg/staffing/insco/factory/brewery/furniture/hardware; visiting professionals) using the existing "needed units = people / peoplePerUnit, capacity shortfall" mechanism. No new capacity cap: missing vehicles reduce work through the existing `workWithout` fraction. Trades-json equipment entries with `vo` for the trades added.
**2D. Own car vs company car for any travelling role** (generalise `offersOwnCar` to a trade/role flag in data). Mileage = km x rate per country (country data) instead of a flat 4500; ties to 2B's km. Hire-sheet "Own car" shown by that flag.
**2E. Fleet insurance and vehicle tax as country data** (insurance product `motor` in `INSP` with rate on vehicle value; road tax per vehicle class; BIK for private use of a company car in tax data). Sources into `TAX_SOURCES.md` first; unverified rates must be flagged like the other unverified entries.

---------------------------------------------------------------------------------------------------

## 3. Staff benefits and bonuses

### What exists (V)
| Item | Detail | Where |
|---|---|---|
| Perk catalogue (5): company car, gym, health insurance, yearly team trip, free lunch. Cost per person per month (scaled): 5500 car (managers and `lead` only), 450, 650, 350, 1500. Hard-coded Swift array | `StaffPerks.swift:31-37` |
| Switch: company-wide on/off per perk (`perks58`). No per-role or per-person choice. UI: Company > Team > Perks card with cost and "% fewer leave" and a confirmation dialog | `StaffPerks.swift:71-79`, `App/.../CompanyPeopleActions.swift:104-161` |
| Cost: weekly `monthly*12/52` to `wages`, label "Staff perks", for `headcount` (all staff + manager; includes seasonal people who are off) | `StaffPerks.swift:94-95`, `:46` |
| Effects wired: quit odds x product of `quitFactor` (`StaffRoutine.swift:77`); applicant skill +`pull`x(2..7) (cap 97), ask -4% x pull, fewer bad-trait applicants (`Hiring.swift:53-63`); gym/lunch reduce tiredness 1.0/0.5 a week; car/trips lift the manager's mood (`StaffPerks.swift:96-106`); trip note once a year | |
| Not wired: a worker's mood explanation (`StaffProfile.mood`) never mentions perks (no `StaffPerks` reference in `StaffProfile.swift`); perks do not change `happyUntilWeek`, pay-ask talks or the pay gap; the "company car" perk is not tied to vehicles (item 2) | |
| Costs not taxed: perks go straight to `wages` without `employerCostFactor` and no benefit-in-kind | I (not seen anywhere in code) |
| Lent luxury pieces to a manager or star worker (mood, loyalty) and hosting evenings exist (`StaffPerks.swift:231-301`) | |
| Bonuses: **managers only.** Monthly target bonus (levels none/standard 8%/high 15% of monthly wage per target met), year-end bonus (0 / 1 / 1.5 months' wage) if sales and profit budgets are met, profit share 0-30% (`managerProfitBonus`, paid at month end with employer cost), executive yearly bonus. UI: Company > Team targets/bonus level, profit share sheet | `ManagerTargets.swift:20-21,215-231,263-279`, `Simulation/MonthEnd.swift:83-87`, `CompanyPeopleActions.swift:95`, `CompanyManagement.swift:259-291` |
| **No bonus for ordinary staff** (no bonus round, no 13th month, no performance bonus). The only ordinary-staff pay levers: raise on a pay-ask talk, fixed vs hourly, commission for sellers, hours | |
| Expense reimbursement: travel = flat mileage for estate own cars only; phone, uniforms: none. Training: `Academy.takeCourse` one-off courses (cost, days, skill gain), player triggered, not a recurring benefit. Onboarding paperwork items exist (`StaffExtras.swift:9-22`) but cost nothing | |
| Employer pension/social/injury are in `country.employerCostFactor` (`Country.swift:139`) and applied to wages and commission, not to perks | |
| Tests: `PerkTests.testPerksCostMoneyEaseTirednessAndKeepPeople` only; none for ask/pull, headcount, car-for-leads-only | |

### Gaps
1. All-or-nothing, company-wide perks; the car perk's "% fewer leave" shown in the card applies only to leads but the UI shows 18% (`CompanyPeopleActions.fewer`, V).
2. Catalogue and numbers are not data; no role/trade applicability (a gym membership for cooks and pilots alike).
3. No bonus or reimbursement for workers; managers are the only ones with performance pay.
4. Perks affect only quit odds and applicants, not satisfaction shown on the profile or pay-ask pressure, so the player cannot see them at the person (I: UX gap).
5. Perk cost bypasses employer charges.
6. `pull` caps at 1 via `min(1, sum)` (sum of listed pulls is 1.05): an implicit cap (`StaffPerks.swift:57`), to be re-derived, not preserved as a limit.

### Proposed small batches (item 3)
**3A. Perks as data with applicability.** `Resources/staff_perks.json`: id, name, monthly cost per person, `quitFactor`, `pull`, `roles`/`roleKinds` or `trades` it applies to (e.g. car: roles with a travel need from item 2C; uniform: roles with a `uniform` kind; health: all). `headcount` becomes "people it applies to, not off season". Existing saves: keep `perks58` keys. Tests: cost = sum over eligible people; a cook never pays for a car; golden of the old five.
**3B. Reimbursement lines (phone, uniform, training budget, travel) through the same catalogue** with `kind: reimbursement`; they pay a real expense (category `oth`), have an effect only where the data says (e.g. `training` raises skill growth in `growSkills`, uniform lowers a hygiene/inspection risk). Do not invent effects for phone beyond removing a dissatisfaction term. Interaction: replaces the flat own-car mileage (item 2D).
**3C. Worker bonus plan reusing `ManagerTargets`.** Same monthly/yearly judging, a plan "bonus pool = x% of payroll when the company's own targets are met" paid through `Payments` with `employerCostFactor`; effect via `happyUntilWeek` (same field raises use) and a lower quit factor while paid; not paid in a bad month (no rescue). UI: one control in the Perks card ("Bonus plan: none / standard / high") with cost preview from last year. Tests: not paid when target missed, paid with employer charges, gaps clean, multi-seed.
**3D. Show perks and bonuses in the person's mood explanation** (`StaffProfile.mood`) and in the pay-ask gap, so they matter for retention at the individual level.
**3E. Employer charges on benefits** (country data: which perks are taxable benefits) after sources are recorded.

---------------------------------------------------------------------------------------------------

## 4. Commission pay

### What exists (V)
| Item | Detail | Where |
|---|---|---|
| Sales roles = 5 role ids in `tables.json` `SALES_ROLES`: `sales`, `cardealer`, `estate`, `agent`, `broker`. Trades whose standard staff contain one: mktg, staffing, hardware, event, brewery, furniture, factory, vineyard (`sales`), estate, cardealer, insco (`agent`). `broker` is in no trade's standard staff | `Resources/tables.json`, `trades.json` |
| Pay models per person: fixed / "mix" (base = 60% of market wage, rate 3%) / "com" (base 0, rate 6%); rate then selectable 2/3/5/8/12%. A security-minded person (`sec` > 0.65) refuses commission-only with 60% chance and resigns | `StaffProfile.swift:217-244`, UI `CompanyOtherSections.swift:180-196` |
| Calculation: weekly commission = rate x the seller's own attributed sales revenue (daily-trade companies: attributed per sale, weighted by skill+10, you included if you sell) or, otherwise, last week's revenue x skill share x rate | `CompanyCosts.swift:17-40`, `DailyTrade.swift:204-250,305-312` |
| Booking: added to gross wages, multiplied by `employerCostFactor`, accrued as payable `wages` and paid on payday | `CompanyCosts.swift:46-60` |
| Effects: commission lifts the seller's skill +4 (mix) / +9 (com); pay cost factor 1.06/1.12 in FTE; smoothed pay `commEma` feeds the quit pay gap and pay-ask talks; commission-only workers risk a "pushy selling" fine (0.3% a week) and quit after slow months (0.4%+1% when utilisation < 50%) | `Employees/StaffModel.swift:48-62`, `StaffRoutine.swift:69`, `StaffExtras.swift:64-75` |
| Other commission-like mechanisms: hotel OTA commission knob, platform fee in `SalesWays`, gym personal-training knob, cardealer finance commission knob (all fixed knob effects, not staff pay) | `trades.json`, `SalesWays.swift` |

### Defects / gaps
1. **Commission-only has no pay floor.** `StaffProfile.setPayModel` sets wage 0 for "com" and `paidByWage` is false for commission, so the minimum-wage lift (`StaffRoutine.swift:62-66`) never applies. Probe (NO, cardealer): commission-only base wage 0.0 vs minimum wage 30,968/month (V). The dead duplicate `StaffTalks.setPayModel` (`StaffContracts.swift:176`) has the floor (`max(..., floor)` for fix/mix), but nothing calls it (V: no callers). Cleanup under the A1 principle: one function.
2. Commission is on revenue (units x price), not on margin; a loss-making sale still pays commission (I; `r += got*price`).
3. Rates (3%/6%, 60% base), skill lifts and risk chances are hard-coded constants; the rate menu is five fixed values.
4. No hire-time pay plan (the hire sheet offers full/part/seasonal/own car only) and no company-level default; only per-person menu.
5. No test covers `setPayModel`/commission (grep over `Tests/`), and none the minimum wage floor.
6. Sensible but not using sales roles (I - judgement; roles exist or are easy to add): realdev (unit sales), carrepair (service advisers upselling), bank (`broker` is unused; mortgage/loan advisers), taxi and courier (per-job pay; courier already has a "gig" knob), retail shop assistants (cashier in boutique, grocery, hardware), travel/booking in hotel/airline reception, webdev/law/acctfirm (business development), staffing consultants (only `sales`/`hr` exist), resrent/comrent letting.

### Proposed small batches (item 4)
**4A. One pay-model function with the pay floor.** Delete the StaffTalks duplicates, make commission-only respect minimum wage where the country requires it (country data flag `minimumWageAppliesToCommission`, default true until a source says otherwise) and keep the "refuses commission only" roll. Tests: wage never below floor in countries with the flag; a 26-week commission-only seller's total pay (base + commission) equals what is booked in `wages` x employer factor; gaps clean.
**4B. Data for pay plans.** `Resources/pay_plans.json`: per role (or role kind) the allowed models, base share, default rate, rate steps, commission basis (`revenue` | `grossProfit`), skill lift and risk constants. No behaviour change first (golden equality), then add trades. Reuse `SALES_ROLES` as the eligibility list, extended in data.
**4C. Add commission eligibility for the trades above** one family at a time (start with realdev and bank where a real sales process exists, then carrepair and retail assistants), each with `commissionBasis` chosen from the trade's economics (gross profit for dealers/real estate). Interactions: `attributeSales` already assigns sales to people with a sales role; for retail, attribution must not make every cashier a "seller" without a sale-based mechanism - needs a per-trade check before enabling (I). Tests per trade: representative company, 3 seeds, commission = rate x attributed basis, effect on quit gap.
**4D. UI.** Add the pay plan to the hire sheet and a company default plan on Team; show projected monthly pay (base + smoothed commission) and the employer cost before confirming, per DESIGN_RULES.

---------------------------------------------------------------------------------------------------

## Housekeeping: roadmap items

| Item | Required status | Found in `IMPLEMENTATION_ROADMAP.md` | Code remnants |
|---|---|---|---|
| B4c age targeting | DEFER | Stage 2 table: "B4c Age targeting - DEFER - trade data has no customer-age profile" (V) | No customer-age targeting in code. `Trade.audience` (0 consumer ... 1 business, `trades.json` `aud`) is a business/consumer split used by marketing, not age. Table B still lists B4 as KEEP ("length and age-group targeting"), superseded by Stage 2 rows B4a-c but not edited |
| Typed age, start city | REMOVE | Stage 2 table row "- Typed age, start city - REMOVE" (V) | Start screen has no age field. `GameEngine.newGame(... age: Int = 30 ...)` (`Simulation/GameEngine.swift:52,63`) still accepts an age parameter (no caller passes it; default 30; age is needed by credit-after-60 rules). City is chosen for the heir story only (`StartView.swift` `familyCityID`, `story.needsCity`), the other stories use the default city. Remnant: the unused `age:` parameter |
| B7 manager focus plans | DEFER | Stage 2 row B7 DEFER (V). Table B row B7 still reads KEEP | None in Swift (grep `setfocus`, `focusPlan`: only `docs/data/action_status.json:1894` records it as missing) |
| B10 web analytics | REMOVE | Stage 2 row B10 REMOVE (V); table B also REMOVE | None in Swift (grep `gaon`, `analytics`: only `action_status.json:802,806`, and an unrelated regex in `equipment_brands.json`) |

Inconsistency to tidy (not changed here): table B still shows B6 Deal of the week and B7 Manager focus plans as KEEP while the Stage 2 table says REMOVE / DEFER. `docs/data/action_status.json` lines 584, 802, 806, 1894 still describe them as "missing"; update the status text when the next doc pass happens.

---------------------------------------------------------------------------------------------------

## Suggested order
1. 2A (mileage double booking) and 4A (commission floor + dead duplicates): defects, tiny, no design.
2. 1A and 3A/4B (move constants to data, golden-equal): unlock everything else.
3. 1B + 1C (delivery with own couriers, start-provider path), 2B/2C (vehicle running cost and roles).
4. 3B-3D, 4C-4D.
5. Tax/insurance data (1E, 2E, 3E) only when sources are recorded.
