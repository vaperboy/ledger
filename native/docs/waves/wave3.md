# Wave 3: made goods with recipes (bakery, cafe, restaurant, foodtruck, brewery, vineyard, farm)

## What it does
- `Businesses/Wave3Recipes.swift` + `Resources/wave3_recipes.json`: each trade has a real product list with a recipe per product (inputs with quantity and share of price, spoilage, labour minutes, batch, units per shift, shelf life, days of stock, days to make or age, allergens, harvest window).
- Opted in through `ItemWave3.swift` (all 7 trades).
- `Wave3Recipes.apply(&s, companyID:, data:)`: (1) if the item list is still the untouched default titles it is replaced by the trade's real products (ids `w3-<recipe>`, same total demand: unit shares and price ratios are normalised the way `SalesItems.defaults` does, all multipliers 1); (2) every item gets a MADE record (STK for bought-in drinks, beans, wine) with `cost` = inputs, `prep` = spoilage per unit sold, `leadDays`, `capacity` (units a shift x shifts a week x company size), `stock` (days of sales on hand), `onOrder` (in tanks, barrels, fields, for lead >= 7 days), a default supplier (best relationship and rating of the goods suppliers) and plans (batch, over capacity, shelf life, harvest and vintage). Items added by the player match a recipe by name words, else get the trade's average recipe.
- `Wave3Recipes.weeklyTick(&s, data:)`: the same function as the weekly refresh (costs follow market price, stock follows sales).
- `Wave3Recipes.card(...)`: the recipe card for the item page (lines, input cost after supplier relationship discount, spoilage, food cost percent at the shown price, production, allergens). `Features/Company/Wave3ItemBlocks.swift` draws it.

## Decisions
- Balance parity by construction: input shares are scaled per trade so the revenue-weighted food cost equals `cogs` of the trade, and the weighted spoilage equals `perish*0.6 + shrink*0.3` (what `TradeCatalog` already charges as variable cost). The books are not touched; the item page now shows where the books' cost comes from. Test asserts both to 1e-9.
- Spoilage is separate from inputs (shown as "Spoilage and write-offs"), because the books charge it separately.
- Supplier: one linked supplier per item (`Record.supplierID`, existing `Suppliers` goods candidates); the relationship discount applies to the inputs only.
- Capacity, shelf life and lead time are shown and planned, not yet a limit on sales (demand is aggregate in `CompanyWeek`; no shared file changed).
- No money literals: all costs are shares of the item's market price, so every country scales.

## Hooks for the lead (shared files, not edited here)
1. After `ItemModels.migrateOptedIn` and in the weekly loop after `ItemModels.weeklyTick` (`PriceMoves.weekly`): `Wave3Recipes.weeklyTick(&s, data: data)`. It upgrades STK records that migration created and converts old companies on their first week.
2. Item page: after `supplyBlock(pg, cur)` add `if let c = Wave3Recipes.card(e.state, companyID: companyID, itemID: itemID, price: price, data: e.data) { Wave3RecipeBlock(card: c, cur: cur) }`.
3. `ItemModelsTests.testRegistryIsEmptyAndMigrationDoesNothingByDefault` asserts the registry is empty; it fails once any wave opts in (shared test, not edited).

## Save keys
No new key. Uses `itemsv2` (records, model `made`/`stk`, plans of kind `w3`) and rewrites `items27` once, only for opted-in trades whose list is still the default.

## Tests (`Tests/LedgerTests/Wave3Tests.swift`)
registry, parity of food cost and spoilage with the books per trade, same revenue after the switch, supplier set, idempotence, card and page agree, wine/beans STK, vintage and ageing, brewing lead time, other trades untouched, save round trip, 104-week probe per trade (gross margin and cash identical with and without the wave, `Ledger.gaps` empty).
