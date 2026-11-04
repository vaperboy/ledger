# Wave 9 notes: venues with capacity tickets and passes (nightclub, casino, fun, skires, indoorski, gym, club)

Files: `Engine/Sources/Businesses/Wave9Venues.swift`, `Resources/wave9_venues.json`, `ItemWave9.swift` (opted in), `App/Ledger/Features/Companies/Wave9ItemBlocks.swift`, `Tests/LedgerTests/Wave9Tests.swift`.
Line-local edits outside my files: `FootballModel.context` (one line: `tix` plus `Wave9.clubTixShift(co)`, exactly 0 at default), `itemcatalog.json` (add-item lists of the seven trades only), `pay_plans.json` (`extraRoles`: nightclub bartender; gym trainer, recept; skires and indoorski skiinst, cashier; fun cashier; casino recept).

## What each trade sells now
Every item has price against the going ticket, a share of customers, a share of the venue's weekly capacity (`fleet`), the capacity one sale uses (`use`), a direct cost share (`vc`), and a recipe line. Peak and off-peak are separate items. Models: `rent` (capacity ticket, table, session, booking), `sub` (pass or membership: holders and monthly churn), `svc` (bar, food, hire, lessons, shop).
- nightclub: early entry (off-peak), late entry (peak), VIP entry, bottle service (table of six, bottle about 30% of price), bar drinks (pour cost about 24%), private hire.
- casino: slots (edge 8%), roulette (5.3%), blackjack (1.5%), poker rake (5%), high-roller room (3%, comps), restaurant and bar, poker tournament entry. Existing luck (`fm.lastHold`) is attributed to the games with an edge, so the item revenues add up to the week's takings. The block shows edge and money played per sale.
- fun: weekday and weekend entry, all-rides pass, season pass (ten visits, priced per visit), birthday party (ten kids), food.
- skires: peak day pass, midweek and half-day pass, season pass (25 days, priced per day), ski lessons, equipment hire, night skiing, mountain restaurant.
- indoorski: peak and off-peak hourly session, lessons, annual membership (30 visits, priced per visit), kids' party, hire, apres cafe.
- gym: off-peak, standard and premium membership (churn factor 1.2, 1, 0.6), day pass, personal training, class pack, supplements (cost 62%).
- club: match ticket, season ticket (19 home games, priced per game), hospitality boxes, merchandise, sponsorship. The club model and its records (`fm`, league, sponsors, transfers) are untouched. Items are attributed from the club's own week (`fm.wk`): matchday takings split by the item weights, merch and sponsor takings as booked, wages, coaches and running costs as the cost pool less the broadcast money (shown as a credit part). Tickets sold are implied (takings / price). Sponsorship units are active deals, its price is the deal's weekly money (not a slider).

## Economics
Cost of one sale = direct cost + (the item's share of the weekly overhead / sales). Overhead = smoothed weekly expenses from `books.week` (EMA 0.9, key `w9u.exp`) less the direct costs; allocated half by revenue and half by capacity used (`sold * use`). Direct costs are rescaled so that at default prices the revenue-weighted cost equals the trade's own cost-of-sales share. The break-even price equals the cost per sale (direct cost does not move with the price charged). Capacity = `lastW.cap` split by `fleet / use`.

## Hooks for the lead
1. `WaveHooks.weekly`: `Wave9.weekly(&s, i, data: data)`. Without it nothing is created.
2. `WaveHooks.cogsFactor`: multiply by `Wave9.cogsFactor(s, companyID: companyID, data: data)` (exactly 1 at default prices; below 1 when the owner prices above market because the bottle costs the same; above 1 below market). Not wired: the probe below shows the wave without it.
3. `ItemPageView.body`, after `overview`: `Wave9ItemBlock(companyID: companyID, itemID: itemID)`. Add the Wave8 and Wave9 blocks inside the same wave dispatch (`WaveItemBlocks`).
4. Club: `FootballModel` line `let tix = fm["tix"].double + Wave9.clubTixShift(co)` is already in. +50% on the match, season and box prices (weighted) is the top ticket level (+1): takings per match times (1 + 0.15 level), fill minus 0.07 per level (the club's existing law).

## Save keys
`w9u` on the company `{w, exp, mdh}` (written on the first sync; `mdh` is the last home matchday takings, for the club), `items27` managed ids `w9:<id>` (the first sync drops the old `d*` titles; items the owner added stay), `itemsv2` one record per item (cost = cost of one sale, fair = market price, capacity a week, stock = places per session or holders, reserved = booked ahead). No key, no change: old saves and other trades unchanged.

## Decisions and limits
- Tier churn factors, pass holders and bookings ahead are estimates for display; the gym member model keeps its single churn law.
- Goods (bottles, meals, merchandise) are bought on the fly through the cost of sales: no stock record per item, no supplier link per item (`supplierID` empty). Option for a later wave.
- `trades.json` and `tables.json` need no edit. Optional for the lead: nightclub equipment has no capacity unit (capacity comes from the company's weekly capacity); a `tables` unit for the nightclub would make bottle-service capacity real.

## Tests (`Wave9Tests`)
Registry; seven trades sell at least five items with economics, record cost equals the books, slider outcomes profit above and loss below break-even, shares and weights add to one, `Ledger.gaps` empty; casino edge; cost-of-sales factor 1 at default and moving with the bar price; club ticket price moves the level and club items are attributed; old saves and reads change nothing; second sync idempotent and owner prices kept; two-year probe.

## Two-year probe (thousand units, UK, seed 11, profit year 1 / year 2, identical before and after: items do not move cash until the `cogsFactor` hook is wired)
casino -1616 / 12289; club 3310 / -37258 (the club model with no manager hired in the probe; same before the wave); fun 24 / 2241; gym 1908 / 1869; indoorski 50621 / 82424; nightclub -839 / 507; skires 4625 / 13898.

## Not done
Event calendars with dated fixtures and capacity per fixture, pay-per-view, per-item supplier links and stock, tournament prize pools as cash, VIP table reservations as a calendar.
