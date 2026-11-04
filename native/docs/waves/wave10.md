# Wave 10 notes: transport and logistics (taxi, courier, trucking, shipping, airline, wh3pl)

Files: `Engine/Sources/Businesses/Wave10Logistics.swift`, `Resources/wave10_services.json`, `ItemWave10.swift` (opted in), `App/Ledger/Features/Companies/Wave10ItemBlocks.swift`, `Tests/LedgerTests/Wave10Tests.swift`. No edits outside them.

## What each trade sells now (model SVC, one item per service or route)
- taxi (per ride): standard fare, airport run, night fare, corporate account; add-ons tourist tour, school run contract.
- courier (per parcel): same-day, next-day, bulk contract; add-ons returns collection, signature and tracking premium, medical courier.
- trucking (per trip): full load lane, groupage (part loads), hazardous (ADR), dedicated contract lane; add-ons subcontracted load (forwarding margin), fuel card service.
- shipping (per voyage): container lane per TEU, bulk charter spot, time charter, reefer lane; add-ons port handling, cargo insurance bundle. Broker commission 2.5% of price.
- airline (per flight): trunk economy, business cabin, regional public-service route, charter, cargo hold; add-ons ancillaries, in-flight sales. Agent and OTA commission 5% of price.
- wh3pl (per order): pallet storage per week, pick and pack, cross-dock, returns handling, kitting; add-ons same-day dispatch, inventory reporting.

## Economics (all from the company's own books, nothing moves cash)
- Capacity of an item = its fleet share x vehicles, aircraft, ships, bays of the main pool (vehicles read from the `veh` records) x capacity per unit (`normalCapacity / standardCount` of the main pool). Load factor = sold last week / capacity (shown with trailing quarter basis).
- Fixed weekly cost by cause: depreciation or lease payments, loan interest, servicing, fuel where the company pays the fuel line (vehicle records via `VehicleRunning`), then wages, premises and fixed overheads. The overhead is the smoothed weekly expenses (`w10u.exp`) less what items carry directly, shared by capacity. Cost of one unit = variable + fixed / (capacity x trailing load factor). Uses `Wave8.econ`, `Wave8.UnitEconomics`, `Wave8.Part` (same module).
- Variable per unit: share of the item's going price (fuel carried in cost of sales, tolls, port dues, handling, packaging, catering) plus commission. Weighted over the mix each trade's variable share is near its cost-of-sales share, so the item costs tie to the books.
- Empty running or empty seats at a normal load and lead time (days, on the record `leadDays`) are shown per item; booked ahead = sold x `adv`.
- The price slider is the existing item price (`priceMultiplier`); demand moves by the shared price elasticity. Shares and ratios are normalised so the revenue weights stay 1: at default prices the trade earns what it earned.

## Save keys
`w10u` {w, exp} on the company when set up; `items27` managed ids `w10s:<type>` and `w10x:<n>` (the first sync drops the old `d*` title items, owner items `n*` stay); `itemsv2` one SVC record each (cost per unit, capacity, stock = vehicles/aircraft/bays, leadDays, fair, reserved). No key, no change: old saves and other trades unchanged.

## Hooks for the lead
1. `WaveHooks.weekly`: `Wave10.weekly(&s, i, data: data)`.
2. `WaveItemBlocks`: `Wave10ItemBlock(companyID: companyID, itemID: itemID)`.

## Not done
Per-vehicle items (each van, truck or aircraft as its own item), real backhaul matching and subcontracting capacity as a rule (the subcontract item is a margin line only), contract subscriptions with churn (corporate accounts, frequent flyer), pallet positions held for client stock, seat-by-seat cabin pricing, pay plans (commission roles for dispatch or ticket desk: only airline `recept` exists), `pay_plans.json` untouched.

## Tests (`Wave10Tests`)
Registry; every trade has 3+ services with economics, record cost = books, live profit sign around break-even; fleet cost parts; old saves untouched; second sync idempotent and owner prices kept; two-year probe per trade (before vs after within 2%).
