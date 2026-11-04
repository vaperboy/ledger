# Wave 8 notes: RENT trades (resrent, comrent, parking, carrental, hotel, pcbang)

Files: `Engine/Sources/Businesses/Wave8Rent.swift`, `Resources/wave8_units.json`, `ItemWave8.swift` (opted in), `App/Ledger/Features/Companies/Wave8ItemBlocks.swift`, `Tests/LedgerTests/Wave8Tests.swift`.
Line-local edits outside my files: `RentalModel.weekly` (3 small changes, the building rate), `itemcatalog.json` and `pay_plans.json` (entries of the six trades only; pay plans: commission roles hotel recept, pcbang cashier, resrent and comrent propm).

## What each trade sells now (model RENT)
- resrent, comrent, parking: one item per building (`Property`), id `w8u:p<propertyID>`. The rate is the rent per flat, m2 or space per week; the item rate slider IS the rent charged (`Wave8.rateMultiplier` in `RentalModel.weekly`) and moves the building's vacancy target (`0.28 * (m - 1) * elasticity`, the same law as the company price level). Cost per let unit-week: mortgage interest, upkeep and repairs, property tax, re-let cost (`relet` weeks of rent per `tenure` weeks) and damage, plus a share of the company's other weekly costs.
- carrental: one item per car or van in `veh` (`w8u:v<vehicleID>`), rate per rental day. Cost: depreciation by vehicle kind, lease payment or loan interest, servicing, fuel when the company pays it, cleaning and damage per rented day, share of overheads. Extras sold as items: excess waiver, child seat and sat-nav, airport delivery.
- hotel: room types (standard, superior, family, suite) split the `rooms` equipment by fleet share; rate per room-night; cost: furniture depreciation and upkeep scaled by room class, laundry and amenities, damage, OTA commission (30% of bookings at 17%), share of overheads. Extras: breakfast, conference package.
- pcbang: seat classes (standard PC, high-end PC, VIP booth) over `pcs` and `seats` equipment, rate per hour (100 open hours a week). Extras: snacks and drinks, tournament entry, night pass.

## Unit cost comes from the company's own books
Overhead shared by the units = smoothed weekly expenses from `books.week` (`Books.expenses`, EMA 0.9, key `w8u.exp`) less what the units and extras carry directly, allocated by value (buildings) or by rate times units. The sum of unit profits therefore ties to the company's weekly operating result before profit tax. The residual is floored at 0 only as an attribution guard. Cost per rented period divides fixed weekly cost by periods x trailing 13-week occupancy (record history, units = rented periods). Occupancy above 100% shows as is: the old demand model is not unit-capacity aware.

## Save keys
- `w8u` on the company: `{w: week, exp: smoothed weekly cost}`, written on the first sync. No key, no change: old saves and other trades unchanged.
- `items27`: managed ids `w8u:...` (units) and `w8x:<n>` (extras). The first sync drops the old `d*` title items; items the owner added (`n*`) stay.
- `itemsv2`: one RENT record per unit: stock = units, capacity = periods a week, cost = cost of one rented period, fair = market rate, reserved = periods booked ahead (rented x `adv`, an estimate), status `repair` for a car in the workshop.

## Hooks for the lead
1. `PriceMoves.weekly`, after `ItemModels.weeklyTick(&s, i, data: data)`: `Wave8.weekly(&s, i, data: data)`. Without it nothing is created (tests call it by hand).
2. `ItemPageView.body`, after `overview(pg, cur)`: `Wave8UnitBlock(companyID: companyID, itemID: itemID)`.
3. `SalesItems.forecast` uses `market * costOfSales` as cost, which is 0 for resrent and comrent: the "Profit change" row of the demand block misleads for rent items. Suggest reading the item record cost there.

## Tests (`Wave8Tests`)
Registry; units as items with economics and slider break-even; hotel room types add up to the rooms and revenue weights stay 1; one item per car; building rate moves rent and vacancy; old saves untouched; second sync idempotent and owner prices kept; two-year probe per trade (before vs after identical at default rates).

## Two-year probe (thousand units, UK, seed 11, profit year 1 / year 2, same before and after)
resrent -205 / 100; comrent -530 / 1737; parking -481 / 230; carrental 705 / 465; hotel 2291 / 5261; pcbang 319 / 241. The wave does not change them: items do not move cash at default rates.

## Not done
Damage claims and no-shows as random events with real cash, reservation calendars per unit, buying or selling one unit from its page, tournament prize pools as cash, hotel channel mix as a slider.
