# Wave 6: SVC appointment and crew model (barber, drivsk, physio, dental, carclean, cleaning)

Files: `Businesses/Wave6Services.swift`, `Businesses/Resources/wave6_services.json`, `Businesses/ItemWave6.swift` (registry), `Tests/LedgerTests/Wave6Tests.swift`, app `Features/Companies/Wave6ItemBlocks.swift`, add-item entries of the six trades in `itemcatalog.json`.

## Decisions
- A real service is an item with: price per job (unit of the trade: treatment, lesson, car, cleaning hour; packs are priced per unit), minutes of chair/car/crew, skill and room, consumables plus direct cost (lab fee, car running, implant part), no-show and rebooking rate, recurring plans (membership, recall, rehab, fleet, office contract) with visits per period and churn, retail stock with lead time.
- Untouched item lists (default titles) are replaced by the real menu on install (`Wave6.install`). A list the player already changed is kept; its items get records (known names from the spec, other items from the old cost-of-sales share).
- Books do not move: `share x rel` is normalised so revenue weights add up to 1 (demand and ticket factors stay exactly 1), and item costs are scaled so the weighted cost of the whole menu equals the trade's `cogs` in trades.json (calibration printed by the spec test: barber 0.90, drivsk 0.83, physio 1.14, dental 0.86, carclean 0.86, cleaning 1.19; 1 = data already agreed). Per item the margins differ (a crown carries its lab fee, a check-up almost nothing).
- Nothing here moves cash. Retail stock is a shelf with a reorder cycle (order when cover falls under lead time plus one week, arrives after the lead days); purchase cost is already in the cost of sales. A stock-out does not stop sales in W6 (see questions).
- No-shows: base rate per trade, cut by a third when the trade's booking/patient system is owned (`eq.<id>.n` or lease). Rebook share recovers part; the rest is shown as lost revenue per week. Display only; demand is the existing model.
- Recurring plans: members = weekly units x period / visits; billed per period = members x visits x price; leaving per period = members x churn. Cleaning contracts also show crew hours a week and full-time people (`fteHours` 36).
- Capacity per job = company capacity (`CapacityModel`, customers a week) x average job minutes of the menu / the job's minutes: a colour takes four times a cut's chair time.
- No save-format change: only `items27` (existing) and `itemsv2` (existing) are written, for opted-in trades only.

## Save keys
None new. Records: `itemsv2` (model svc/sub/stk, cost, lead, capacity, stock, onOrder, plans `order:<n>` with the arrival week).

## Hooks the lead adds (shared files)
1. `PriceMoves.swift` line 41, next to `ItemModels.weeklyTick(&s, i, data: data)`: `Wave6.weekly(&s, i, data: data)` (installs the real menu and records, runs the retail stock cycle; no-op for other trades).
2. `ItemPageView.swift` `body`, after `supplyBlock(pg, cur)`: `Wave6ItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)`.
3. `pay_plans.json` `extraRoles`: `"barber": ["barber"], "dental": ["dentist"], "physio": ["physio"], "drivsk": ["instr"], "carclean": ["carwash"]` (stylists, associate dentists, therapists, instructors and detailers are paid on what they bill; cleaning stays hourly).
4. `ItemModelsTests.testRegistryIsEmptyAndMigrationDoesNothingByDefault` asserts an empty registry; it must be relaxed once any wave opts in.
5. `tables.json` `EQ_KINDS.barber.prod` is `mach` for "Product retail stock"; no stock kind exists, left as is.

## Tests (Wave6Tests, 11 + 1 gated)
Specs consistent with the books, install gives the real menu and neutral books, models per item, touched list kept, not-opted-in no-op, facts (service, membership, contract), reminders cut no-shows, retail reorder cycle, record round trip, and `LEDGER_WAVE6=1` two-year probe before/after (same seed, same standard set-up as BalanceProbeTests).
