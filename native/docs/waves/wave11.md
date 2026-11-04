# Wave 11 notes: financial, energy and group trades (insco, bank, fund, power, oilgas, hold)

Files: `Engine/Sources/Businesses/Wave11.swift` (economics, sync), `Wave11Bases.swift` (the product lines per trade), `Resources/wave11_items.json`, `ItemWave11.swift` (opted in), `App/Ledger/Features/Companies/Wave11ItemBlocks.swift`, `Tests/LedgerTests/Wave11Tests.swift`.
No line outside these files was edited. The existing models (`FinanceModel`, `EnergyModel`, `HoldingModel`) are untouched and keep booking all the money; the items split it by product. Nothing here moves cash.

## What each trade sells now
- insco (SUB): one item per cover of the model's `INS_PRODS`: motor, home, property, life, travel, business. Price = premium per policy-year (the blended premium the model books, split by each cover's premium index); expected claims = the book's loss ratio times the cover's loss factor (normalised so the covers add up to the booked loss ratio); claims handling and running cost 12% of premium; investment income on the float as a credit; reserves = 40% of annual premium (the solvency capital the model tests); risk = claims a policy-year, 1.5x in a storm year, relative swing 14%/sqrt(policies/1000). A cover that is not switched on, approved and staffed shows 0 policies and says so.
- bank (SUB): four loan types (mortgage, business loan, credit card, overdraft; mix follows the "Loan book" knob) and two deposit accounts (savings, current). Loan price = interest per customer-year (central bank rate plus margin spread by type, adding up to the model's interest income); costs = funding at the central bank rate (transfer price), expected credit loss (loss weights normalised to the model's loss rate), capital held = capital ratio times balance; downturn stress = losses at demand 0.9. Deposit price = what the money is worth as funding (central bank rate), cost = interest paid (adds up to the model's deposit interest). Fees (FX, wealth, student account) are not in the model, so they are not default items.
- fund (SUB): six fee classes (index, growth, income, ethical, property, bond) over the fund's AUM (shares fixed in json); fee rate = the model's management fee spread by class factor, adding up to the booked fee; clients = AUM / average client (8m); risk = fee lost in a 20% market fall (class beta times the strategy beta). The yearly performance fee is paid on the whole fund and stays outside the class fees (said in the note).
- power (SUB): three tariffs over the output: Green tariff (spot priced), Fixed-price plan and Business supply (both at the hedged price, 60/40). The hedge knob moves MWh between spot and fixed (0 / 50 / 90%), so the tariffs always add up to the output and revenue. Cost per MWh: running cost of the plant (`lastW.cogs`) and depreciation of turbines, grid, SCADA and roads (from the `eq` records); the generation source and MW are in the note. Risk = revenue swing for a 10% move in the spot price. Solar installs, batteries and EV charging are not in the model, so no default items.
- oilgas (PROJ): one item per field (developing or producing; depleted ones drop out), price per barrel from `EnergyModel.oilPrice` (term contracts share 60%), cost per barrel = lifting cost + depletion (book value / reserves) (a developing field: development capex per barrel), risk = revenue swing for a 10% move in the oil price on the non-contracted share, bad year = 40% fall. Barrels left and years of output are in the item.
- hold (SUB): six group services (management services, shared back office, treasury, group purchasing, brand licensing, training academy); the holding's own smoothed weekly cost is shared by weight; fee per subsidiary-week = cost plus 10% (a transfer price). No cash moves between the companies: the slider shows the margin, it does not charge anything yet.

## Unit costs come from the company's own books
Overhead = smoothed weekly expense (`w11.exp`, EMA 0.9 of `Books.expenses(books.week)`) less what the lines book directly (`w11.dir`: claims, interest paid and credit losses, plant running and depreciation or lifting and depletion), shared by weekly revenue (hold: by weight). The item profits add up to the company's result up to the smoothing (probe: insco items -486/wk against a company result of about -480/wk in year 2; oilgas 12.8m/wk against 12.1m/wk).

## Sliders
The item price multiplier is the shared one (`items27.pm`). Revenue weights keep `sum(share * ratio) = 1` so demand and ticket stay exactly 1 at default prices (tested). The shared page's live profit reads `itemsv2.cost`, which keeps its share of the product's market price in the units of the list price, so the break-even word is true for the real cost. The block `Wave11ItemBlock` shows margin at the slider price, costs by cause, risk and capital. Only insco is moved by the slider in the model (through `Pricing.demandEffect`, already generic); for bank, fund, power, oilgas and hold the slider is a live what-if on margin, as the models set their own rates and prices.

## Save keys
- `w11` on the company: `{w, exp, dir}`, written on the first sync. No key, no change: old saves and other trades unchanged.
- `items27`: managed ids `w11:<line>`; first sync drops the `d*` title items (only when the company has lines to show); owner items stay.
- `itemsv2`: one record per line (model SUB; oil fields PROJ): stock = units, capacity = weekly volume, cost and fair as above, history of weekly units, revenue, profit.

## Hooks for the lead
1. `WaveHooks.weekly`: add `Wave11.weekly(&s, i, data: data)`.
2. `WaveItemBlocks.body`: add `Wave11ItemBlock(companyID: companyID, itemID: itemID, price: price, cur: cur)` (the block reads `price` as the list price on the slider).
No `cogsFactor` change (nothing here changes cost of sales).

## Tools and staff
`EQ_KINDS` for the six trades already match the real kit (core system soft, workstations it, platforms mach/svc); staff roles stay as they are (insco agents already sell on commission through `FinanceModel.verifiedAgents`; bank `banker` is in `pay_plans.json` extraRoles). No changes needed.

## Tests (`Wave11Tests`)
Registry; every trade has products with economics, revenue weights 1, demand and ticket factor exactly 1, live slider outcomes; insco covers add to policies, premium and loss ratio; bank loans carry funding and credit loss, card loses more than a mortgage; oil fields are items and term contracts cut exposure; power tariffs add up to the output and follow the hedge knob; hold fee is cost plus 10%; fund fee classes add up to the fee; old saves and other trades untouched; second sync keeps owner prices; two-year probe.

## Two-year probe (thousand units, UK, seed 11; profit year 1 / year 2, identical before and after)
insco -7322 / -24971; bank -2831 / -33025; fund -1294 / -643; power -7916 / -17836; oilgas -55925 / 628601 (two bought stakes); hold -649 / -649. The wave changes nothing (items do not move cash). The losses of insco, bank, fund and power at default set-up exist before the wave (the models need more than the quick set-up: policies and loans build slowly, power has 30 MW at about 14m each); not caused here.

## Known state of the shared tests
`ItemModelsTests` (4 tests: migration, page, history, registry) already fail on origin/native-swiftui without wave 11 (they expect only the old wave's records), same with and without this wave.

## Not done / lead decisions
Real intercompany fee for hold (SUB between units), pet, gadget and cyber cover, FX/wealth fees, power installs (PROJ), forecourt and refined products for oilgas, distributor commission on funds, performance fee per class, add-item catalog entries with their own economics (the title-only catalog entries stay as they are).
