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
10. Open: starters added by a module after the choice are visible; revenue is not zero while nothing is chosen; the first company from `newGame(tradeID:)` is unchanged.
