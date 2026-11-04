# Wave 4: MADE industrial/digital and SUB (salmon, furniture, factory, startup, gamestudio, webdev)

Files: `Businesses/Wave4Items.swift` (enum `Wave4`), `Businesses/Resources/wave4_items.json`, `Businesses/ItemWave4.swift` (registry), `Tests/LedgerTests/Wave4Tests.swift`, app `Features/Companies/Wave4ItemBlocks.swift`, add-item entries of the six trades in `itemcatalog.json` (line-local).

## What each trade sells now
- furniture: oak table, fitted kitchen run, fitted wardrobe, hotel and office fit-out (made to order, quote and lead 28 to 56 days, minimum 20 pieces and 5% retention on the fit-out), restoration job (service), dining chair, office desk series, flat-pack bookcase, children's bed (made for stock in batches of 8 to 50 with lead 5 to 10 days). Bill of materials per item, labour minutes, scrap.
- factory: custom machined part, prototype run (made to order, lots of 250 and 5, scrap 4% and 15%), standard component, maintenance spares, packaging line unit (stock lots), assembly service, quality inspection service, annual supply contract (SUB, minimum 3 call-offs, churn per 4 weeks). B2B payment terms from the trade (`terms`).
- salmon: whole fresh, fillets, smoked, roe, ready meals, restaurant box, pet food trimmings, farm visits. Per item: yield of product per tonne of fish, processing cost. Live cycle on the page from the real cohorts: weeks to harvest, fish and tonnes in the water, average kilos, weekly losses, tonnes a week.
- gamestudio: work for other studios and publisher deal advance (fixed bids with hours, overrun, milestones), console port (bid), premium game, free-to-play game, DLC, cosmetics (titles: development hours, development cost at the company's pay, sales halve every N weeks, remaining profit, payback), live-service club (SUB).
- webdev: company website, online shop, design system (fixed bids: hours, bid, labour, margin at the bid and if it overruns), web app development (hourly), maintenance plan, hosting and care, SEO package (SUB: subscribers, MRR, churn, lifetime value, cost to serve), website template (digital title).
- startup: Starter, Pro, Team (10 seats), Enterprise (annual), API access, Premium support (SUB with MRR, churn, cost to serve, lifetime value), onboarding service, custom integration (bid). Subscribers are the real product's customers from `StartupModel` (`sw16.cust`) split by unit share.

## Decisions
- Same pattern as Wave 6: an untouched item list is replaced by the real menu on install; a touched list is kept and only gets records. Items without a spec fall back to `ItemModels.migrateItem`.
- Books do not move: revenue weights add up to 1 (demand and ticket factors exactly 1) and item costs are scaled so the weighted cost of the menu equals the trade's `cogs`. The salmon farm has `cogs` 0 (its cost is the cohorts' feed, smolt and site cost, expensed at harvest), so its items keep the data's cost shares (fish about 57% of the whole-fish price from smolt 14.5, feed 27 per kg gained, site 0.15 per kg-week) and are not calibrated.
- Records: made-for-stock goods are `made` with a batch cycle (batches of whole `batch` units arrive after the lead days: plan kind `batch:<n>`), made to order and fixed bids are `proj` (stock 0, lead days), digital titles are `proj` (a development project, not a stock line, so the list never says "Sold out"), services `svc`, plans `sub`.
- Cost of one unit includes scrap (cost / (1 - scrap)); the page splits inputs, other direct cost and scrap so they add to the unit cost (tested).
- Labour is shown at the company's own average pay (`lastWages` over staff x 36 hours); it is not added to the item cost, because wages are booked separately.
- Salmon items: units a week = average harvest tonnes (cohorts over a cycle) x unit share x yield. Display only.
- Nothing here moves cash. No new save key: `items27` and `itemsv2` only, for these six trades only.

## Limits (questions for the lead)
1. Salmon and startup run their own weekly model (`SpecialFamilies`): revenue comes from harvest and from subscribers, not from the item list, so the price slider of their items shows profit and loss but does not change sales. Options: (a) leave it (display only); (b) a hook in `StartupModel.context` multiplying the subscription price by the weighted price multiplier of the sub items; (c) the same for salmon harvest revenue.
2. Capacity, lead time and scrap are shown and planned, not yet a limit on sales (demand is aggregate in `CompanyWeek`).
3. Gamestudio and webdev item prices are per the trade's unit (dev hour) times the item's price ratio; the title lines say what the unit is (100 copies, 1000 players).

## Hooks the lead adds (shared files, not edited here)
1. `Businesses/WaveHooks.swift` `weekly`, after `Wave8.weekly(...)`: `Wave4.weekly(&s, i, data: data)`.
2. `Features/Companies/WaveItemBlocks.swift`: `Wave4ItemBlocks(engine: engine, companyID: companyID, itemID: itemID, currency: currency)` next to the other wave blocks.
3. `pay_plans.json` `extraRoles`: none needed; furniture `sales` and factory `sales` already exist.
4. `tables.json` `EQ_KINDS`: furniture and factory machines are already `mach`; salmon pens, barge, boats, cameras and lice system `mach`; startup has no equipment. No edit needed.

## Save keys
None new. `itemsv2` (model made/proj/svc/sub, cost, lead, capacity, stock, onOrder, plans `batch:<n>`), `items27` (the menu).

## Tests (`Wave4Tests`)
Registry, spec consistency (weights, unique names, calibration, subscription and title fields), install per trade (real menu, neutral factors, weighted cost = books for cogs > 0, idempotent), record models, touched list kept, not-opted-in no-op, furniture cost breakdown adds up, factory lots and contract, web bid and maintenance MRR, game title curve, salmon products follow cohorts, startup plans, batch cycle, save round trip, gated two-year probe (`LEDGER_WAVE4=1`, before and after, same seed).
