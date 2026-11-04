# Wave 5: professional services (cons, tutor, photo, law, acctfirm, mktg)

Model SVC (hour or job), with SUB for retainers and MADE or STK for the few goods. Code `Engine/Sources/Businesses/Wave5Services.swift`, data `Resources/wave5_services.json`, registry `ItemWave5.swift`, page block `App/Ledger/Features/Companies/Wave5ItemBlocks.swift`, tests `Tests/LedgerTests/Wave5Tests.swift`.

## Decisions
- A service TYPE is the item. The engine unit stays one block of billable hours (`hpu`: 1 hour; photo 6 hours), so demand, capacity, prices and old saves are unchanged. Item share `q` is a share of billable hours, `f` the price per hour against the trade's average hour; ratio = f / mean f, so shares times ratios add up to 1 and revenue at market prices does not move.
- Hourly rate = item price / hours in a block. Job price = hourly rate x hours per job (`h`). The slider is on the hourly rate; the shared price slider (price per block) still works.
- Cost of a block = trade labour share `L` x the going ticket x role pay factor x quiet-week factor, plus (consumables + write-off) x market price. Role pay factor = pay of the roles doing the item (`ROLES` monthly wage, weights per item) against the trade's standard team (a paralegal does a contract review cheaper than a lawyer does a dispute). Quiet-week factor = `fix` x planned utilisation / last week's utilisation (at most 1) + (1 - fix): paid staff cost the same when free, so a half-empty week makes every sold hour dearer. No floors; a full week costs the planned labour.
- Write-offs (`wo`) are unbilled time, scope creep and bad debt; consumables (`c`) are filing fees, venues, media, stock images. Both are in the unit cost the page already shows (one figure everywhere). They are reads: the company week books revenue and cost of sales as before.
- Retainers (`m: sub`) show clients served (jobs a week x 52/12) and a monthly churn. Client type: business, households, retainer.
- Goods: photo prints and albums (MADE, materials share, 0.5 h of work, batch 10, lead 5 days), tutor workbooks (STK, bought in batches of 25). They hold stock; orders appear as plans, arrive after the lead time, sales leave stock. No money moves for it (the books pay for goods as before). Digital goods (templates packs) have no stock.
- Seeding: only when the company still has the default item list (`items27` absent) are the trade's real service types written (start set per trade); records of the old default ids are removed. A list the player or an old save changed is kept and only gets records. Items added from the catalog get their real price against the others (list rescaled so the total stays 1).
- The add-item catalog of the six trades (`itemcatalog.json`) is exactly the service types of the JSON (test). Goods entries are developed first.
- Tools (`EQ_KINDS`) checked against the real trades and kept: laptops it, software soft, cameras and lenses tool, lighting and studio mach, drone tool, furniture furn. No change.

## Save keys
- Company `w5seed` = 1 once an opted-in company has been prepared (new key, opted-in trades only). Records are the existing `itemsv2` (W0). Nothing else.

## Hooks for the lead (shared files, not edited here)
1. `Businesses/PriceMoves.swift` `weekly`, after `ItemModels.weeklyTick(&s, i, data: data)`: `Wave5Services.weekly(&s, i, data: data)`. Without it nothing is seeded.
2. `ItemPageView.body`, after `priceBlock(pg, co, cur, price)`: `Wave5ServiceBlock(companyID: companyID, itemID: itemID)` (the VStack then has 10 children, the ViewBuilder limit).
3. `ItemModelsTests.testRegistryIsEmptyAndMigrationDoesNothingByDefault` asserts the registry is empty; it fails as soon as any wave opts in.

## Test rows (Wave5Tests)
Registry and catalog match; roles exist and every service earns at planned utilisation; seeding keeps revenue and cash identical over 6 weeks for each trade, ledger gaps empty; slider loss below break-even, profit above, fewer hours at a dearer rate; quiet weeks raise cost; role pay decides labour; added catalog item adopted; retainers and goods stock; other trades untouched; save round trip; two-year probe per trade (before = after, no money moves).

## Two-year probe (seed 11, UK; cash and revenue identical before and after the wave)
Standard owner of `BalanceProbeTests.play`, yearly profit in year 2 on money invested (accounting units): cons 195,639 on 283,481; tutor 39,061 on 114,449; photo -8,825 on 309,893; acctfirm 621,465 on 2,828,559; law -1,270,734 on 3,271,005; mktg -1,035,592 on 2,288,320. Law and mktg already lost money before this wave and the wave moves no money, so the cause is in the base trade balance (payroll of the standard team against a small client base), not in W5.
