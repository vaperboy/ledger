# Wave note: new-car dealership (`cardealer`)

Engine: `Businesses/CarDealer.swift` (stock, orders, week), `Businesses/CarBrands.swift` (brand data + `CarBrandContract`), `Resources/car_brands.json` (11 invented brands with model ranges, margin, bonus, term, target, standards, markets per country), `Simulation/CarDealerActions.swift` (GameEngine API). Tests: `CarDealerTests` (10).

Rules
- Nothing appears by itself: opening stock is 0 for `cardealer` (`OpeningChecklist.openingStockCost`). Cars are ordered, arrive after a lead time (distributor 1-2 weeks, brand 2-4), are paid on delivery, sit as inventory at cost.
- Save keys (only set when used): `cd` = {cars, orders, con}. Car: id,b,m,name,list,cost,ask?,wk,fair,rsv?. Order: id,b,m,name,list,cost,due,res?. Contract `con`: b,start,end,margin,bonus,target,minSpaces,minSales,minSat,yr,sold,soldList,warn,offer?,last?,asked?,declined?.
- Spaces = premises m2 / 60 (showroom, lot, handover). Cars plus orders may not exceed spaces.
- Generic distributor: any brand, dealer buys at list x (1 - 4 percent - buyer edge up to 1.2 percent). Brand contract: only that brand, buys at list x (1 - brand margin 5.5 to 8.5 percent) plus yearly volume bonus (1 to 2 percent of list value sold) after the review; total at most 10.5 percent.
- Brand contract: term 3 to 5 years; signing needs the brand's standards (car spaces, salespeople, satisfaction = reputation). Yearly review: target met -> full bonus, 85 percent -> half; under 60 percent of target or standards missed -> warning; second warning -> brand drops the dealer (no penalty, back to distributor). 8 weeks before the end: renewal offer if no warnings, standards met, last review at least 90 percent (110 percent -> margin +0.3 point, target +10 percent), else it lapses. Early exit penalty = target x avg list x margin x 0.5 x years left (min 0.25 year), paid from cash, booked as `fine`.
- Shoppers (demand model) compare up to 3 cars (showroom plus unreserved orders); price ratio against car value x brand appeal; a customer can reserve a car on order and buys it on delivery if the price still suits. Cars older than 13 weeks lose 0.3 percent of value a week. Holding cost 0.12 percent of stock value a week.
- Buyer role (`buyer`) or a manager orders up to 2 cars a week when stock plus orders are thin; the buyer's skill lowers the distributor price. `pay_plans.json` extraRoles now lists `cardealer: ["buyer"]` so a buyer can be commission-only, base+commission or fixed; salespeople (`cardealer`) already had the three plans.
- Add-on hook: `CarDealer.week` has a comment at each sale where `cardealerSaleAddons(saleID:)` (DealerAddons.swift) must be called.

Touched outside my files (small, line-local)
- `Businesses/CompanyWeek.swift`: 7-line `if bd.id == CarDealer.tradeID` block after the usedcar block (merge next to the usedcar agent's edit).
- `Businesses/OpeningChecklist.swift`: `openingStockCost` returns 0 for `cardealer`.
- `Businesses/Resources/pay_plans.json`: one line `"cardealer": ["buyer"],`.
- `trades.json` NOT touched (single-line file). Not done there: the equipment list still has lifts and diagnostics (tools should be only cleaning products + CRM like usedcar); `eq` and `std` mech staff need the same change the usedcar agent makes. Trade `D` is 0 in data; demand still comes from the demand model (about 3 customers a week).

App (wire-up needed by the lead)
- `Features/Companies/CarDealerSection.swift`: `CarDealerSection(engine:company:)` (supplier block, showroom list with `CarStockCard` in the Team row layout, order sheet, per-car price sheet with live profit/loss slider). `CarDealerBrand.swift`: `CarBrandScreen(companyID:)` (brand list, terms, sign, running contract, results, renewal, leave). Mount `CarDealerSection` in the company page for `company.type == "cardealer"` (e.g. in CompanyDetailView / products tab).
- Not compiled here (no Mac): CI is the compiler.
