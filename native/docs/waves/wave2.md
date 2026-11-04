# Wave 2 notes (STK resale and parts): kiosk, boutique, grocery, hardware, webshop, pets, carrepair

Code: `Businesses/Wave2.swift`, `Wave2Repair.swift`, `ItemWave2.swift`, `Resources/wave2_items.json`, `Simulation/Wave2Actions.swift`, tests `Wave2Tests.swift`.

## Decisions
- Catalogue per trade in `wave2_items.json` (real items, real-life margin per item `mc`, fixed extra cost `fix`, lead days, shelf life, returns, season curve, supply kind, licence knob).
- Per company one scale `k` (key `w2` = {k, nm}) so the revenue-weighted cost of the starting list equals the trade's cost of sales: books unchanged at default prices and mix.
- Commission lines (kiosk top-ups 4%, lottery 6%) and pass-through costs (fulfilment, carrier) are `fix`, never scaled.
- Stock per item = the company's real inventory (ledger) shared by what each item sells. Nothing is invented; the item layer writes no money.
- Item names equal the add-item popup titles (`itemcatalog.json`, my 7 entries rewritten); weekly `adopt` gives any item with a catalogue name its real record. Licensed items (tobacco, alcohol, lottery, parcel, tool hire, pet taxi) need their business-choice option.
- Job orders: `Wave2.carRepairQuote` / `Wave2.orderRepair` (engine: `carRepairQuote`, `orderCarRepair`, `carRepairGarages`). Price = bay hours x hourly rate (share of the garage ticket) + parts at cost x (1 + markup); weeks from the garage's spare capacity (`OwnListings.spareSlots`) less jobs already booked (`w2jobs`). Booked at order: dealer pays (category `cogs`), garage `rev` + parts `cogs`, VAT via `IntercompanySupply.transferVat`. Same country only.

## Save keys (only written for opted-in trades)
`w2` {k, nm} on company; `w2jobs` list and `w2jid` counter on a garage; `itemsv2` records and `items27` list (existing keys).

## Hooks the lead adds (shared files)
1. `PriceMoves.weekly`, after `ItemModels.weeklyTick(&s, i, data: data)`: `Wave2.weekly(&s, i, data: data)`.
2. `CompanyWeek`, where the week's `cogs` is final (before `Suppliers.recordGoods`): `cogs *= Wave2.cogsFactor(s, companyID: co.id, data: data)` (exactly 1 at default prices; makes the price slider change the real margin).
3. `ItemModelsTests.testRegistryIsEmpty...`: the first assertion must go (the registry is no longer empty).
4. `pay_plans.json` extraRoles: `"carrepair": ["recept"]` (service adviser), `"pets": ["groom"]`.
5. Item page: dropship items are model `svc` ("Service"); a "Dropshipped" label would read better.

## Tests
Wave2Tests: registry, cost-of-sales parity per trade, kiosk commission and licences, price slider vs margin and cogsFactor, perishable and seasonal notes, webshop dropship and own brand, pets boarding capacity, garage job order double entry and capacity, old saves untouched, 2-year probe per trade (prints `WAVE2 PROBE`).
