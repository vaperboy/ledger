# Products and services by trade (audit, docs only)

Binding input: owner brief of 4 Nov 2026 (`native/docs/briefs/DEALERSHIP_AND_PRODUCTS_BRIEF.md`, commit cedcb45 on local `native-swiftui`, not yet on origin). Scope: all 69 trades in `Engine/Sources/Businesses/Resources/trades.json`. No code changed.

## What the game models today (applies to every trade unless the row says otherwise)

- **T0 items**: `SalesItems` (`items27`): a list of up to 12 items `{name, unit share, price ratio, price multiplier, discount, listed}`. Names come from `tradeNouns`/`familyNouns` (3 to 4 generic nouns, e.g. "standard service") or `itemcatalog.json` (8 titles per trade via `NewItemOptions`: svc/goods flag, optional develop-first). Demand per item = (price/market)^-1.5, clamped. An item has NO stock, NO cost/buy price, NO inputs, NO lead time, NO capacity, NO reservations, NO own page tabs. It is a price tag on a title.
- **Stock** is one company scalar: `co.inventory` and `shelf` (`Shelf`, `StockHandling`, `CompanyWeek`), driven by trade traits `stock` (days), `perish`, `shrink`. Auto-ordered by demand; nothing is bought per product. Cost of sales is `ticket x cogs%`.
- **Supply**: `Suppliers` (one goods vendor per company, quality class), `IntercompanySupply` and `AccountSupply` (`supply_kinds.json`: 16 kinds: clean, build, freight, parcel, deliv, bread, beer, produce, fish, furn, web, ads, temp, carserv, whouse, power) feed a cost-of-sales percentage, not per-item inputs. `StoreOrders`/`EquipmentMarket` (TechPro) buy equipment and vehicles for use, not for resale (except `usedcar` stock via `Marketplace.buy`).
- **Real models that already exist** (these trades have real "things", the rest do not): `UsedCarDealer` (per-car `stk`: cost, repairs, markup %), `RentalModel` (properties: resrent, comrent, parking), `ProjectModel`/`ProjectTenders`/`ProjectDeveloper` (jobs, hours, units: construction, electrician, plumber, event, engcons, realdev), `SoftwareProducts` (webdev builds a product record `swp`), `StartupProducts` (startup), `SalmonModel`, `FinanceModel` (insco, bank, fund), `EnergyModel` (power, oilgas), `FootballModel` (club), `HoldingModel` (hold), `Capacity` (staff role, equipment, space).
- **Team person page** (`StaffProfileView`, `WorkerProfileSheet`, `CompanyStaffRoster.swift`): one scroll page, not literal tabs. Blocks in order: header with `KeyFigures` (Pay, Contract, With you), Mood, Performance, Contract (action "Discuss"), Promises, Record, "What you can do" (actions). Company page tabs are Overview, Team, Manage, Sales, Stats (`CompanyTab`). Sales today = list of items, tap opens `SalesItemSheet` (price slider, discount, list for group, sold) only.

## Legend

Model codes: **STK** stocked goods bought from suppliers (buy price, shelf stock, lead time) | **MADE** made goods (inputs + recipe, batch, capacity) | **SVC** service with hourly or job price (time, capacity, consumables) | **RENT** rental or booking (units, calendar, occupancy) | **BRK** brokered or commission (own stock OR commission, flagged with source) | **PROJ** project or contract (bid, milestones, retention) | **SUB** subscription (members, churn, recurring).
Middle-man source flags: **mkt** marketplace (listings, haggling, hidden condition), **sup** supplier (catalogue, wholesale, brand contract), **con** contract (client or principal supplies the thing), **own** from your own company (`IntercompanySupply`).
Today codes: **T0** items only (as above), **T0+inv** T0 plus company-wide shelf/inventory scalar, **T0+real** T0 plus the real model named.
`*` = middle-man trade (section "Middle-man trades").

## Trade table (69 rows)

| key | sells (real life) | today | gap | model | wave |
|---|---|---|---|---|---|
| usedcar* | used/damaged cars and vans; finance, warranty, insurance, trade-in | T0+real: `UsedCarDealer` per-car stock, flat markup %, Marketplace buy | per-car page with buy, repair (own mechanic as supplier), slider live P/L (shows 0 or negative bug), lot spaces from premises, repair-time grey-out + reservations, stuck cars/forced loss, buyer role, commission add-ons | BRK (mkt+own) | W1 |
| cardealer* | new cars (brand), used trade-ins, finance, warranty, insurance, service plan | T0 titles ("Certified used cars"); company-wide `stock` trait 40 days | no cars at all, showroom, supplier pick, brand contract with % commission and renewal, per-car page, add-on commissions | BRK (sup, con brand) | W1 |
| estate* | sale listings, lettings, valuations, inventories | T0 titles; revenue = `unit` home sold 76k | no listings: properties come from nowhere; commission % on real sold price; vendor instruction (from owners, own realdev/resrent), exclusivity, viewings | BRK (con listing, own) | W1 |
| realdev | flats, houses, plots, conversions | T0+real: `ProjectDeveloper` units sold, land/build costs | units are counts; no per-unit page (spec, cost, price slider, reserved off-plan, sold-via-agent commission) | PROJ + STK units | W1 |
| staffing* | temp workers (bill rate), permanent placements (fee %), exec search | T0 titles; cogs 0.76; supply kind `temp` | no candidate pool, no placed-worker records: bill rate vs pay rate per placement, client contracts, guarantee period | BRK (con client, labour pool) | W1 |
| event* | weddings, conferences, launches, festivals | T0+real: `ProjectModel` hours spec; supply `ads`/`temp` | no per-event package: venue, catering, AV bought in as suppliers with markup or commission, deposit, date calendar | BRK + PROJ (sup) | W1 |
| kiosk* | newspapers, snacks, drinks, lottery, top-ups, parcel pickup | T0+inv: titles, one shelf scalar, stock 12 days | no SKUs: buy price, shelf stock, wholesale supplier, lead time, shrink per product; lottery/top-up/parcel are commission lines | STK + BRK (sup, con) | W2 |
| boutique* | clothes, accessories, alterations, made-to-measure, gift cards | T0+inv, stock 70 days, seasonal | no collections with buy price and sizes, season markdown, supplier minimums; alterations = SVC | STK (sup) + SVC | W2 |
| grocery* | fresh, own-label, deli, bakery counter, delivery | T0+inv, perish 0.04, stock 9 days | no SKU/category stock, shelf life, supplier per category (own bakery/farm/fish via `IntercompanySupply`), own-label margin | STK (sup, own) + MADE counter | W2 |
| hardware* | tools, paint, timber, garden; hire, cutting, trade counter | T0+inv, stock 45 days, B2B 0.45 | no SKUs, trade vs retail price, hire fleet as rentable units, supplier credit lines | STK (sup) + RENT hire | W2 |
| webshop* | own-brand or resold goods, subscription box, express delivery | T0+inv, ecom, returns 0.18, stock 35 | no catalogue: dropship vs stocked, 3PL (`whouse` supply), returns per item, shipping cost per order | STK/BRK (sup dropship, own 3PL) | W2 |
| pets* | grooming, walking, sitting, boarding, pet food/accessories | T0 titles (mostly svc, 2 goods) | boarding = bookable kennels with capacity; food/accessories need stock and supplier; transport | SVC + RENT + STK | W2 |
| carrepair | labour hours + parts, MOT prep, tyres, bodywork; repairs for your dealers | T0 titles; cogs 0.36; supply kind `carserv` (it is the supplier) | job = labour hours x rate + parts at markup; parts stock; bay capacity; repair queue incl. cars from your own `usedcar` (job order with due date) | SVC (job) + STK parts | W2 |
| bakery | bread, pastries, cakes, sandwiches, wholesale to cafes | T0 (goods nouns sourdough/croissants/cake), perish 0.08, stock 1 | no recipes: flour/butter/sugar inputs, batch size, oven capacity, shelf-life waste per product, wholesale vs counter price | MADE | W3 |
| cafe | coffee, pastries, lunch, beans to take home | T0 menu nouns, perish 0.05 | no menu items with recipe cost; ingredient stock; beans retail STK; pastries bought from own bakery | MADE + STK | W3 |
| restaurant | starters, mains, desserts, wine, private dining | T0 menu nouns, perish 0.07 | dishes with recipe, food cost %, wine list bought in (STK), covers/seat capacity, bookings | MADE + STK wine + RENT seats | W3 |
| foodtruck | wraps, burgers, fries, drinks, catering events | T0 menu nouns, perish 0.06, hours 40 | recipes, prep stock, location per day, catering jobs with quote | MADE (+SVC catering) | W3 |
| brewery | beer by litre, kegs to pubs, gift packs, tours | T0 titles; excise trait; supply kind `beer` is supplier | batch brewing: malt/hops inputs, fermenter tank capacity, lead time weeks, kegs/bottles stock, excise; pub contracts | MADE (batch) | W3 |
| vineyard | wine by bottle, club, tastings, tours, venue | T0 titles; harvest, excise, stock 40 | vintage per year (harvest input), barrels/ageing time, bottle stock per wine, club subscription; tours = RENT/booking | MADE (seasonal batch) + SUB | W3 |
| farm | veg boxes, eggs, dairy, meat, wholesale produce, farm shop | T0 titles; harvest, subsidy; supply kind `produce` is supplier | crops/livestock cycle, field/barn capacity, harvest lots, price per tonne vs box, farm shop STK | MADE (cycle) | W3 |
| salmon | fresh, smoked, roe, ready meals, restaurant boxes | T0+real: `SalmonModel` (cycle, tonnes, smolt, feed) but items are titles | the model sells tonnes only; processed lines (smoked, fillets) need a processing recipe and cold stock | MADE (cycle) + processing | W4 |
| furniture | made-to-measure tables, ranges, kitchens, restoration, contract fit-out | T0 titles, stock 20 | per-piece recipe (timber, hardware, hours), made-to-order vs stock, lead time, custom quote, restoration as SVC | MADE (order, batch) | W4 |
| factory | custom parts, components, prototypes, spares | T0 titles; order lot 62k; supply none | BOM and routing per part, lot size, machine hours, minimum order, quality/inspection, B2B contracts | MADE (lot) | W4 |
| startup | licences, seats, onboarding, support plans, API | T0+real: `StartupProducts` record; add-ons titles | tiers/plans with seats, churn, support cost; integrations as projects | SUB (+MADE digital) | W4 |
| gamestudio | games, DLC, in-game items, subscriptions, publishing deal | T0 titles; dev hours | title with dev phase, platform, price, units/DLC, live-ops; publisher deal as contract advance | MADE (digital) + SUB + PROJ deal | W4 |
| webdev | websites, shops, maintenance, hosting, SEO, own software | T0+real: `SoftwareProducts` (builds a product) + titles | site builds as fixed-bid projects with scope and hours; maintenance/hosting as SUB with per-client record; templates sold as digital goods | PROJ + SUB + MADE digital | W4 |
| cons | strategy workshops, audits, interim management, retainers | T0 titles | engagement = days x day rate, scope, retainer SUB; capacity = billable hours; templates minor | SVC (hour/day) + SUB | W5 |
| tutor | 1-to-1 lessons, groups, exam courses, subscription | T0 titles | lesson slots with capacity, group seats, term enrolment, workbooks stock | SVC + SUB + STK | W5 |
| photo | weddings, portraits, headshots, product shoots, prints, drone | T0 titles (1 goods) | booking date and deposit, shoot hours + editing hours, prints as made goods, gear as capacity | SVC (job) + MADE prints | W5 |
| law | contract review, formation, conveyancing, probate, disputes | T0 titles; B2B 0.85 | matter with fixed fee vs hourly, hours budget, trust/disclosure documents, templates pack | SVC (hour/fixed fee) | W5 |
| acctfirm | bookkeeping, payroll, annual accounts, VAT, audit support | T0 titles | per-client engagement with monthly fee, deadline calendar (year-end), hours per client; recurring | SVC + SUB | W5 |
| mktg* | social management, brand, ads, content, video, research | T0 titles; supply kind `ads` is supplier | retainers (SUB) and campaigns (PROJ); ad spend passed through with commission/markup (media buying) | SVC + SUB + BRK (sup ad media) | W5 |
| hold | management services, shared back office, group purchasing, licensing | T0 (one noun "management fee") | fees charged to own units as intercompany SUB; group purchasing is a broker between units and suppliers | SUB (own) + BRK (own) | W11 |
| barber | cut, shave, colour, beard, membership, products | T0 nouns (haircut, beard trim, full style) | service menu with duration, chair capacity, colour consumables per treatment, retail products STK, membership SUB | SVC (appointment) + STK + SUB | W6 |
| drivsk | lessons, intensive courses, theory coaching, Pass Plus | T0 titles | lesson = instructor hour + car (fuel km 1000), pupil enrolment pack (prepaid blocks), pass rate drives reputation | SVC (lesson pack) | W6 |
| physio | treatments, rehab programme, home visits, massage, braces | T0 titles (1 goods) | session length, therapist capacity, referral source, course of N sessions, braces STK | SVC (appointment) + STK | W6 |
| dental | check-ups, hygiene, whitening, ortho, implants, products | T0 titles | treatment with chair time, materials cost (implants, lab fees), recall plan SUB, price per treatment | SVC (appointment) + consumables | W6 |
| carclean | washes, deep clean, ceramic coating, fleet contracts, products | T0 titles | job = time + chemicals, mobile route; fleet contract as SUB; cleaning work for your own `usedcar` yard (prep) | SVC (job) + SUB | W6 |
| cleaning | regular home plan, office contract, deep clean, end-of-tenancy | T0 titles; B2B 0.8; supply kind `clean` is supplier | hours x crew, consumables, recurring contract (SUB) with rota, per-site record | SVC (hour) + SUB contract | W6 |
| construction | extensions, new builds, fit-out, roofing, maintenance | T0+real: `ProjectModel`/tenders (jobs, bids) but items are titles | per-job page: bid, materials (`build` supply), subs, milestones, retention, change orders (data exists in project model, no item page) | PROJ | W7 |
| electrician | rewiring, fuse boards, EV chargers, inspections, call-outs | T0+real: job model (3 wks, mat 0.38) | call-out vs install job vs inspection plan: price per job type, materials (parts stock), certificates as documents | PROJ + SVC call-out + SUB inspection | W7 |
| plumber | boiler service plans, bathrooms, call-outs, heat pumps, certificates | T0+real: job model | same as electrician; service plans as SUB; parts stock | PROJ + SVC + SUB | W7 |
| handy | assembly, small repairs, painting, call-outs, home-check plan | T0 titles; materials 22% | job = hours + materials; call-out fee; plan SUB; tool kit STK | SVC (job) + SUB | W7 |
| engcons | structural design, feasibility, supervision, audits, retainers | T0+real: hours spec in `ProjectModel` | deliverables with milestones and fee % of build cost; retainers | PROJ (fee) + SUB | W7 |
| security | guarding contracts, alarm monitoring, CCTV install, patrols, key holding | T0 titles; supply kind `temp` | contract = guard hours x rate with site and shift rota; monitoring SUB; CCTV install = PROJ with equipment STK | SVC (hour contract) + SUB | W7 |
| resrent | furnished/student/short lets, management plan | T0+real: `RentalModel` properties | lets are title items; each flat needs own page (rent slider, tenant, void weeks, repairs, deposit); management plan is service | RENT | W8 |
| comrent | serviced offices, desks, meeting rooms, retail units | T0+real: `RentalModel` (m2) | rentable units by type (office, desk, room) with occupancy, lease terms, service charge | RENT | W8 |
| parking | permits, long-stay, EV bays, valet, self-storage | T0+real: `RentalModel` spaces | space types with price slider, occupancy, EV bay hardware, per-space booking | RENT | W8 |
| carrental* | daily/weekly rentals, chauffeur, vans, long-term lease, extras | T0 titles; cars/vans equipment | fleet as units (bought new/used, depreciation, status: out, cleaning, repair), booking calendar, insurance/extras commission, damage claims | RENT + BRK (own fleet via `StoreOrders`/mkt) | W8 |
| hotel* | rooms, conference, wedding venue, spa, breakfast | T0 titles; `ota` 0.17 channel; rooms kind in `DailyTrade` | room types as bookable units (rate slider, occupancy, ADR), channel mix (direct vs OTA commission), add-ons with stock | RENT (+BRK channel) | W8 |
| pcbang | hourly gaming, passes, tournaments, snacks | T0 titles; hours 100 | seats as units with hourly price, peak/off-peak, snacks STK, tournaments as events | RENT (seat-hours) + STK | W8 |
| nightclub | table service, bottles, themed nights, private hire | T0 titles; perish 0.02 | tables/bottles as stock (bottle buy price, per-bottle margin), door cover, event date capacity | RENT + STK bar | W9 |
| casino | tables, slots, high-roller, poker, dining | T0 titles; variance 0.5 | games as capacity units (tables, slots) with house edge, comps, tournaments, dining F&B | RENT (units) + variance | W9 |
| fun | tickets, season pass, birthday party, group, F&B | T0 titles; `rooms` kind | attractions as capacity units, ticket tiers, party bookings, F&B stock | RENT (tickets) + SUB pass | W9 |
| skires | ski school, passes, hire, night skiing, restaurant | T0 titles; hours 56 | lift tickets by day/season, hire fleet units, lessons capacity, snow/weather, restaurant F&B | RENT + SVC lessons | W9 |
| indoorski | lessons, annual membership, parties, hire, apres cafe | T0 titles | slots on the slope (capacity), membership SUB, hire units, cafe | RENT (slots) + SUB | W9 |
| gym | membership, classes, personal training, nutrition, supplements | T0 nouns; `sub` 1, churn 0.012 | membership tiers with members and churn, class timetable capacity, PT hours, supplements STK | SUB + SVC PT + STK | W9 |
| club | membership, merchandise, hospitality, youth academy | T0+real: `FootballModel` (season, budget, transfers, sponsors) | merchandise STK, tickets by matchday, hospitality boxes as units | RENT tickets + STK merch (+ own model) | W9 |
| taxi | airport transfers, night rides, corporate accounts, tours | T0 titles; fuel 0.1, km 1900 | rides priced per km/fare, vehicle as capacity unit, corporate accounts SUB, shift per driver | SVC (per ride) + SUB accounts | W10 |
| courier | same-day, next-day, pallets, medical, contracts | T0 titles; supply `parcel`/`deliv` is supplier | per-parcel rate by zone/speed, route capacity, business contracts SUB | SVC (per parcel) + contract | W10 |
| trucking* | full loads, reefer, cross-border, dedicated contract | T0 titles; fuel 0.22, km 3200 | load as job (lane, rate per km, backhaul), own trucks vs subcontracted capacity (forwarder), contract lanes | SVC/PROJ (load) + BRK forwarding (con) | W10 |
| shipping* | container, bulk, reefer, charter, port handling | T0 titles; `rooms`, rate index | voyages with cargo space sold (TEU), charter vs spot rate, ship as unit; forwarding commission | RENT (cargo space) + BRK | W10 |
| airline* | seats by cabin, cargo hold, charter, frequent flyer | T0 titles; `rooms`, rate index | flights as units with seats per cabin, fare slider, load factor, ancillaries, agent/OTA commission | RENT (seats) + SUB loyalty | W10 |
| wh3pl* | pick and pack, cold storage, pallet storage, returns, kitting | T0 titles; supply kind `whouse` is supplier | pallet positions as capacity, per-order handling fee, client stock held (not yours), contract with storage + handling rate | RENT (storage) + SVC handling (con) | W10 |
| insco* | home/motor/travel/business/pet/life/gadget/cyber cover | T0+real: `FinanceModel` insurer (policies, premium, claims) but items are titles | each cover line with premium, loss ratio, exposure; distribution via agents and brokers (your dealers earn commission) | SUB (policy) + BRK channel | W11 |
| bank* | savings, mortgage, business loan, card, overdraft, FX | T0+real: `FinanceModel` bank | per-product rate/margin; loans/finance sold through your dealers pay them a commission | SUB/rate products + BRK channel | W11 |
| fund | growth/income/index/ethical/property/bond funds, portfolios | T0+real: `FinanceModel` fund (AUM, mgmt, perf fee) | each fund as product with AUM, fee, performance; distributor commission | SUB (AUM fee) | W11 |
| power | green tariff, fixed plan, business supply, solar, battery, EV charging | T0+real: `EnergyModel` (MW, capacity factor) | tariffs as plans with customers (SUB) vs generation; installs as PROJ; supply kind `power` to your companies | SUB (tariff) + PROJ install | W11 |
| oilgas | fuel grades, heating oil, lubricants, bunkering, gas contracts, forecourts | T0+real: `EnergyModel` oil (explore, barrels) | refined products as made/stock lots, forecourt retail STK, contract sales; exploration licence separate | MADE lot + STK forecourt + PROJ | W11 |

Count check: the table has 69 rows (waves: W1 6, W2 7, W3 7, W4 6, W5 6, W6 6, W7 6, W8 6, W9 7, W10 6, W11 6 = 69).

## Models and tabs

### Models (one record shape each; all feed the existing ledger: stock = inventory at cost, sale = revenue + cost of sales)

1. **STK stocked goods**: item = SKU. Fields: buy price (per supplier offer, relationship discount from `Suppliers`), sell price slider, stock on hand, on order, lead time days, reorder level or auto (manager), shelf life/perish, shrink, supplier choice. Live margin = sell - buy.
2. **MADE made goods**: item = recipe. Fields: inputs list (qty per unit, each input a STK-like buy), labour minutes, batch size, equipment/capacity (oven, tank, line, fermenter weeks), yield and waste, lead time, quality tier, made stock. Cost per unit rolls up from inputs.
3. **SVC service**: item = service type. Fields: price per hour or per job, duration, consumables per job, capacity (staff hours), booking slots, cost per job. Live margin = price - labour - consumables.
4. **RENT rental/booking**: item = unit (flat, room, seat, space, vehicle) or unit type. Fields: rate slider (per night/week/hour), status calendar (free, booked, repair), occupancy, deposit, turnover cost, minimum stay. Units cannot be sold twice.
5. **BRK brokered/commission**: item = listing or principal line. Either **own stock** (buy, hold, resell) or **commission** (% of principal's price, paid on completion). Fields: source (mkt, sup, con, own), exclusivity, commission %, holding cost, reservations, add-on commissions (finance, warranty, insurance one-off %). Stock/listing must ARRIVE by a real route; nothing appears on its own.
6. **PROJ project/contract**: item = job type with a bid. Fields: bid price, materials estimate (`build` supply), hours, subcontract share, milestones, retention, overrun risk, margin if it overruns.
7. **SUB subscription**: item = plan. Fields: price per period, subscribers, churn, cost to serve, tiers, upgrades. Live margin per subscriber.

### Item page tabs (mirror the Team person page, one-to-one)

The Team person page has no literal tab bar; it is one scroll of blocks. The item page uses the same blocks as sections (and the same `TeamGroup`/`Card`/`KeyFigures`/`TeamAction` components), so Sales and Team look identical. If a tab bar is wanted, use one per block.

| Team person block | Item page block | Content |
|---|---|---|
| Header, `KeyFigures` (Pay, Contract, With you) | Overview | name, thumbnail, status (in stock, being fixed, reserved, listed), key figures: Cost (buy + prep), Price, Margin now, Stock/Units, Time in stock/with you |
| Pay / Contract (+ "Discuss") | Price | the price slider with live profit vs loss band (green above cost, red below, 0 shown as break-even not negative), market price marker, discount (weeks), "list for group"; supplier terms for STK (buy price, minimum, lead time) |
| Performance | Sales/Demand | units sold, weekly trend, demand vs price, reviews/returns, share of company revenue |
| Mood | Demand and reputation | wanted/asked-for count, reservations queue, complaints, quality score (equivalent of mood chip) |
| Promises | Plans and promises | reservations and pre-orders made to customers, backorders, scheduled batches/repairs/bookings, warranty promises; keep now / ask to wait maps to "fulfil now / push back" |
| Record | History | purchase and cost history (buy, repair costs, stock moves), price changes, sale record, per-item profit and loss ledger entries |
| (paperwork done) | Documents | provenance and inspection report, warranty terms, spec sheet, certificates (electrician), recipe/allergen sheet, VAT scheme (`used_goods` margin scheme for cars) |
| "What you can do" | Actions | reprice, discount, send to repair, reorder, sell at a loss (forced), delist, retire, move to group |

Per-item fields by model: STK buy price, stock, on order, lead time, shrink; MADE inputs, batch, capacity use, lead time; SVC duration, hourly/job price, consumables, capacity; RENT rate, calendar, occupancy; BRK source, cost basis, commission %, reservations, lot space used; PROJ bid, materials, milestones; SUB price, subscribers, churn. Lot or space capacity (cars, pallets, rooms, seats) comes from premises (`Capacity` kind `space`; `prem` in trades.json).

### Shared engine work (needed before the waves)

- **Item record v2** in `items27` (or a new key): add `cost`, `stock`, `status`, `lead`, `reserved`, per-model payload; keep default-derivation so old saves load (SAVE_FORMAT.md note, save migration).
- **Item page** `ItemPage` replacing `SalesItemSheet` (sections as above), reusing Team components.
- **Live P/L slider** component: one view (cost line, break-even, colour band); fixes the "profit shows 0 or always negative" display bug for dealers.
- **Supply per item**: `Suppliers`/`IntercompanySupply`/`Marketplace` offers become per-item buy sources; keep the cost-of-sales percentage as fallback for untouched items so balance (BALANCE_PARITY) does not move until a wave switches over.
- Demand stays the existing elasticity model; stock-outs and reservations feed into it.

## Middle-man trades: how stock or commission arrives

| trade | route | notes |
|---|---|---|
| usedcar | mkt (Marketplace listings, haggling, hidden condition) + own mechanic company as repair supplier (`carserv`) | stuck cars, forced loss, lot spaces from premises, buyer/manager skill = deal quality; commission on finance, warranty, insurance |
| cardealer | sup: chosen supplier (lower margin); con: brand contract replaces generic supplier, dealer gets % of sales; renewal if brand pleased | showroom cost; same commission add-ons |
| estate | con: vendor instructs you (listings from NPC owners, own `realdev`/`resrent`); commission % of sale or lettings fee | no stock, listing = reservation of viewings |
| staffing | con: client order; labour pool supplies candidates; margin = bill rate - pay | placement fee % for permanent |
| event | sup: venue, catering, AV bought in; con: client; markup or commission | deposit and date |
| realdev | not a broker; sells via estate (pays commission) | listed here because estate depends on it |
| kiosk, boutique, grocery, hardware, webshop, pets | sup: wholesaler/manufacturer catalogue; own: your bakery, brewery, farm, salmon, furniture via `IntercompanySupply`; webshop dropship/3PL | lottery, top-ups, parcel pickup are commission lines |
| mktg | sup: media (ad spend pass-through) | commission vs markup |
| carrental | own fleet (new via `StoreOrders`, used via Marketplace); commission on insurance and extras | fleet is rented, not resold (remarket old cars to usedcar via mkt) |
| hotel, airline, shipping | channel commission: OTA (`ota` 0.17), agents, forwarders | they are sellers, not brokers; commission is a cost |
| trucking | con: shipper load; can subcontract to other hauliers (forwarding margin) | |
| wh3pl | con: client goods; no own stock | clients can be your own companies (`whouse`) |
| insco, bank | channel: your dealers, agents (`agent` role) distribute policies and loans for commission | a stand-alone broker trade does not exist (see owner decisions) |
| hold | own: group purchasing between units and suppliers | |

## Waves (6 to 8 trades each; one agent per wave; wave 0 is the shared engine work above)

| wave | model | trades |
|---|---|---|
| W0 | shared | item record v2, item page, live P/L slider, per-item supply (no trades switched) |
| W1 | BRK unique units (lots, listings, commission add-ons) | usedcar, cardealer, estate, realdev, staffing, event |
| W2 | STK resale + parts | kiosk, boutique, grocery, hardware, webshop, pets, carrepair |
| W3 | MADE food and drink recipes | bakery, cafe, restaurant, foodtruck, brewery, vineyard, farm |
| W4 | MADE industrial/digital + SUB | salmon, furniture, factory, startup, gamestudio, webdev |
| W5 | SVC professional hour/day | cons, tutor, photo, law, acctfirm, mktg |
| W6 | SVC appointment and crew | barber, drivsk, physio, dental, carclean, cleaning |
| W7 | PROJ and job contracts | construction, electrician, plumber, handy, engcons, security |
| W8 | RENT property, fleet, seats-by-hour | resrent, comrent, parking, carrental, hotel, pcbang |
| W9 | RENT venues and capacity tickets, SUB passes | nightclub, casino, fun, skires, indoorski, gym, club |
| W10 | transport and logistics (per ride/load/seat/pallet) | taxi, courier, trucking, shipping, airline, wh3pl |
| W11 | financial/energy products, group services | insco, bank, fund, power, oilgas, hold |

Order: W0, W1 (brief priority, defines BRK and lot logic reused by W2 and W8), then W2, W3, W8, W6, W5, W7, W4, W9, W10, W11. W1 depends on W2 carrepair being the repair supplier (`carserv`); build carrepair job-orders in W1 if W2 is later.

Each wave definition of done: every trade in the wave has real items with cost/price/stock (or the model's equivalent), item page with the sections above, add-item popup creates real items (not titles), save migration, engine tests per model, balance check (profit unchanged at default settings within tolerance).

## Owner decisions open

1. Stock migration: (a) switch each wave's trades to real per-item stock and cost at once; (b) keep the cost-of-sales percentage until the player adds real items. Default assumed: (a) per wave, with balance check.
2. Missing trades named in the brief: a travel agency, an insurance broker and a stand-alone finance broker do not exist. Options: (a) add them as new trades in W1; (b) keep them as add-on commission lines on dealers, estate and hotels only.
3. Services with no physical item (law, consulting, tutoring): (a) keep items as service types with hourly/job price and capacity; (b) also add per-client engagements. Default assumed: (a).
4. Item page layout: (a) one scroll page of blocks like the Team person page; (b) a literal tab bar. Default assumed: (a), as Team has no tab bar.
