# Pricing realism and product choice: plan

1. Prices were already refused outside 30%..300% of market (`SalesItems.ratioRange`, `setItemPrice`); 300% is the demand clamp, not a realistic price.
2. New `SalesItems.priceFloor/priceCeiling/priceRange` (0.3..1.8 of market); `setItemPrice`, `setPrice`, `forecast`, the item page slider and the professional-services range use it. `ratioRange` stays for the demand curve.
3. Every trade module seeds starter items into `items27` on its first weekly step, so an empty list cannot be stored: each module would refill it.
4. Instead a company key `pick1` hides them: `{p: true}` until the owner chooses, then `{p: false, hide: [starter ids not chosen]}`. Engine maths still use the full list.
5. `startCompanyChoosingPremises` (the player flow) sets it unless `SetupChoices.chooseFirstItem` is false. `startCompany`, `newGame` and old saves are unchanged (all items visible).
6. API: `salesItems` (filtered), `needsFirstItemChoice`, `firstItemChoices`, `chooseFirstItem`; a custom first item via `addSalesItem`/`addNewItem` also ends the pending state.
7. Item edits (price, discount, group listing, supplier) are refused with "Choose what you sell first." while pending.
8. Who sets prices: `SalesItem.priceSetter` = `.advisor` when the advisor role is filled, else `.manager(name:)` when a manager is hired, else `.owner`; the item page shows "Set by ..." for non-owners. It is shown, not enforced.
9. Tests: `SalesItemsTests` gains ceiling, first-choice and price-setter cases. Nothing was compiled or run here (no Swift toolchain).
10. Ceiling is per trade: `SalesItems.ceiling(for:)` / `range(for:)` (table by trade, then family, default 1.8); `GameEngine.itemPriceRange(companyID:)`, `SalesItem.priceCeiling/maxPrice`.
11. Choosing seeds the trade module's starters first (`SalesItems.seedStarters`), so `firstItemChoices` and the hidden ids are the real list, also before the first weekly step.
12. Hidden starters carry no customers (`SalesItems.shaped`: visible shares renormalised, hidden 0); `DemandModel.compute` and the finance model return 0 while the choice is pending.
13. `newGame(... chooseFirstItem: true)` marks the onboarding company pending (default false so engine balance tests are unchanged; the app passes true).
14. The owner can always set prices; `priceSetter` is information only.
15. Open: rental, developer and special-family models do not read the gate; starters a module adds long after the choice are visible.
