# Balance report: how fast does each trade make you rich?

Run it yourself: `cd native/Engine && LEDGER_BALANCE=1 swift test -c release --filter testPrintWealthSpeedOfEveryTrade`
(options: `LEDGER_MKT=1` a modest ad plan, `LEDGER_NOOWNER=1` the owner does not work there, `LEDGER_AGGR=1` every channel at
its top budget, `LEDGER_COUNTRY=DE`, `LEDGER_TRADES=cafe,gym`). Three seeds per trade, three years, UK capital, standard set-up
(the "Fill in what is missing" button), money in = the estimate shown before starting x 1.3 plus any money added to keep it alive.
Amounts are game accounting units (about 13.5 to the pound). Every supported trade (50) is played.

## Verdict

**No trade makes you rich quickly.** The best returns come from small owner-run services (consulting, photography, car cleaning,
an accounting practice): a few hundred percent a year on a small stake, but in money that is the owner's own wage, and it does not
scale because the owner's hours are capped (80 a week across all companies). With a hired team instead of the owner, the best
trades (accounting, law, estate agency, gym) return 15 to 80 percent a year from year three, after a loss-making first year,
which is in line with real professional-service margins (15 to 25 percent of revenue). Maxing every advertising channel never pays
off. **Capital-heavy trades (shops with stock, workshops, plants, hotels, vehicles, ships, aircraft, lifts) now return a modest
2 to 15 percent a year on the money put in, from the second year on** (see "Capital-heavy trades" below). `BalanceGuardTests`
keeps both ends: nothing becomes a fortune, and a well-run asset-heavy business is not a certain loss.

## Investments (`LEDGER_INVEST=1`): money left three years in every share, coin and fund, five seeds

| | Mean | Median | Best | Worst |
|---|---:|---:|---:|---:|
| Shares | 1.25x | 1.14x | 2.45x | 0.78x |
| Crypto | 1.39x | 1.06x | 6.25x | 0.06x |
| Funds | 1.16x | 1.10x | 1.62x | 0.92x |

About 7-8% a year for shares and 5% for funds, as in real markets; crypto is a lottery with the odd big win and near-total
losses. No safe shortcut to a fortune.

## Problems the probe found, and what was changed

| Problem | Cause | Fix |
|---|---|---|
| Car cleaning, handyman, food truck, car rental, shipping never opened | Vehicles were bought for cash only; the start-up estimate counts a 20% down payment | Vans are bought outright when cash allows, otherwise financed (20% down, 5-year loan) or leased, as in the original; fixed equipment is bought first |
| A business run only by hired staff served no customers | With an empty support role the capacity multiplier divided by zero (also in the original) | The team covers empty support jobs, as the code already intended; parity test records the deliberate difference |
| Staffed businesses shrank to nothing | People who quit were never replaced | Policy "Replace people who leave" (on by default): one network hire a week at the going rate, only with 4 weeks of costs in cash |
| Reputation slid for every unmanaged business | Every customer complaint went unanswered | Policy "Staff answer routine complaints" (on by default); serious complaints still come to the owner |
| Automated hiring overpaid | It took the median asking wage, often a senior at ~45% above market | It takes the most skill for the money among people who can do the job |
| Owner-run companies valued at 7-8x the money put in | Goodwill counted the owner's unpaid work as profit | Company value deducts what it would cost to hire someone for the owner's work |
| Groceries, kiosks, bakeries, cafés starved of customers | Walk-in awareness was the same as a niche boutique's | Shops on a street get a neighbourhood awareness by kind: grocery 48, kiosk and pharmacy 44, bakery 40, hardware 38, café 32 (others 20) |

## Results (with a modest ad plan: search, social and website at their lower budgets)

Three seeds per trade, so a single figure is good for about plus or minus 5 points; the two columns on the right replay the same
set-up with a hired team instead of the owner and with every advertising channel at its top budget. The airline, the shipping
company and the ski centres are lumpy (two aircraft, two ships, one lift): their figures swing most between seeds.
"Money in" includes the money the owner had to add later to keep the company alive (working capital counts as invested).

| Trade | Money in (k) | Profit, year 3 (k) | Return a year | Worth / money in | Run by hired team: return | Every channel at max: return |
|---|---:|---:|---:|---:|---:|---:|
| acctfirm | 1307 | 2083 | 159% | 8.0x | 78% | -6% |
| airline | 281379 | 16022 | 6% | 1.0x | 11% | 6% |
| bakery | 9986 | 1162 | 12% | 0.3x | 13% | -1% |
| barber | 2032 | 307 | 15% | 0.1x | -9% | 7% |
| boutique | 2078 | 209 | 10% | 0.0x | -8% | 3% |
| brewery | 10835 | 1292 | 12% | 0.6x | 6% | -13% |
| cafe | 2586 | 757 | 29% | 0.6x | 1% | 8% |
| carclean | 226 | 479 | 212% | 5.7x | -25% | 35% |
| cardealer | 34440 | 1697 | 5% | 0.2x | 6% | -6% |
| carrental | 3111 | 450 | 14% | 0.5x | 2% | 12% |
| carrepair | 5835 | 470 | 8% | 0.1x | -6% | 3% |
| casino | 62370 | 7728 | 12% | 0.5x | 11% | 7% |
| cleaning | 1002 | 685 | 68% | 3.0x | 9% | 5% |
| cons | 195 | 645 | 330% | 7.1x | -20% | -53% |
| courier | 5425 | 727 | 13% | 0.5x | 5% | -1% |
| dental | 5761 | 271 | 5% | 0.1x | -1% | 13% |
| drivsk | 1411 | 626 | 44% | 2.3x | 8% | -7% |
| estate | 1998 | 442 | 22% | 2.3x | 16% | -15% |
| factory | 55841 | 4401 | 8% | 0.4x | 12% | 2% |
| farm | 13662 | 624 | 5% | 0.5x | 0% | -3% |
| foodtruck | 484 | 776 | 160% | 5.5x | -7% | 4% |
| fun | 13858 | 3089 | 22% | 0.8x | 9% | 2% |
| furniture | 9774 | 687 | 7% | 0.4x | 4% | -5% |
| gamestudio | 3373 | 228 | 7% | 0.0x | -6% | 21% |
| grocery | 69183 | 3424 | 5% | 0.0x | 5% | 2% |
| gym | 11336 | 1822 | 16% | 0.6x | 16% | -0% |
| handy | 251 | 218 | 87% | 2.6x | -13% | 7% |
| hardware | 25073 | 2331 | 9% | 0.3x | 4% | -3% |
| hotel | 47883 | 5257 | 11% | 0.5x | 11% | -0% |
| indoorski | 976497 | 30141 | 3% | 1.1x | 3% | 1% |
| kiosk | 4731 | 314 | 7% | 0.0x | -6% | 9% |
| law | 1714 | 2124 | 124% | 5.7x | 32% | -17% |
| mktg | 1132 | 501 | 44% | 1.7x | -29% | 10% |
| nightclub | 11813 | 1779 | 15% | 0.5x | 9% | -1% |
| pcbang | 5325 | 445 | 8% | 0.2x | -6% | 8% |
| pets | 1145 | 1143 | 100% | 2.2x | 14% | 22% |
| photo | 222 | 587 | 265% | 7.0x | -27% | -0% |
| physio | 3028 | 398 | 13% | 0.1x | -1% | 12% |
| restaurant | 12539 | 705 | 6% | 0.3x | 5% | -1% |
| security | 2467 | 299 | 12% | 0.1x | 2% | 19% |
| shipping | 57645 | 3812 | 7% | 1.1x | 13% | 68% |
| skires | 107425 | 8053 | 7% | 0.7x | 8% | -2% |
| staffing | 2190 | 48 | 2% | 0.6x | -20% | -31% |
| taxi | 1512 | 552 | 36% | 2.4x | 9% | -10% |
| trucking | 14646 | 972 | 7% | 0.6x | 9% | -7% |
| tutor | 114 | 114 | 99% | 3.1x | -29% | 88% |
| vineyard | 12056 | 620 | 5% | 0.3x | 8% | -4% |
| webdev | 1378 | 708 | 51% | 2.0x | -27% | -21% |
| webshop | 3133 | 541 | 17% | 0.2x | -2% | 5% |
| wh3pl | 18232 | 1290 | 7% | 0.3x | 7% | -8% |

## Capital-heavy trades: why they lost money, what was changed, and why that is realistic

Per-trade causes found with `LEDGER_TRACE=<trade>` (weekly demand, capacity, and the year's books):

1. **Demand level too low for assets that must be used.** Each trade is "designed" so that a normal number of customers
   covers its fixed costs plus a target profit margin (`TradeCatalog.calibrate`). For a thin-margin trade that margin is 3 to 5
   percent of revenue, but the money tied up is a multiple of revenue (stock, lifts, ovens, vehicles), and interest, shrinkage,
   marketing and fines come on top of the calibration's reserve. A 3 percent margin on a business that turns its capital 3x a
   year is a 9 percent return before those extras, i.e. about zero after. Real asset-heavy businesses run their assets at high
   utilisation (airline load factors of 75 to 85 percent, hotel occupancy 65 to 75 percent, plants 80 percent), so the
   *demand level* of these trades was raised (`demandLevel` in `trade_tuning.json`). This is the main change.
2. **Capacity (output per employee) too low** for courier, warehouse, ski resort, vineyard, farm and the ships: demand was
   there (D several times the capacity) but each employee or vessel served too few customers per week, so wages ate the
   revenue. A parcel courier delivers 100 to 150 stops a day, the game's 40 to 50. `Dc` and `capD` (normal demand and
   capacity) of those trades were raised by 1.15 to 1.9x, with fixed costs unchanged. Shipping and the airline are also
   *granular*: with 1 to 2 voyages or flights a week, rounding made the weeks swing between zero and a full voyage.
3. **Awareness.** The airline, a hotel, a shipping line and a vineyard have no walk-in trade, so they started at the same
   awareness as a one-room consultancy, 12 of 100, and were seen by a sixth of the customers a real carrier gets from booking
   platforms and agents. They now start like destinations (`Marketing.organicAwareness`: 22 to 30).
4. **The start-up estimate was fine but the *test* was not.** The old probe gave the owner 200 M units of test funds, which is
   less than the airline (131 M estimate x 1.3 + planes) or the indoor ski centre (751 M) needs, so those could not even be set
   up and the airline "always went bankrupt". The probe's funds are now 20 bn.
5. **Not changed on purpose:** depreciation and valuation are fine. Vehicle depreciation in the weekly books (planes 5 percent,
   ships' equipment 8 to 18 years) is in line with real lives; the calibration's 15 percent for every vehicle only affects
   the (stored) fixed-cost figure. Loan interest is a real cost of financing 80 percent of a 180 M aircraft (7 percent interest);
   the standard set-up deliberately finances. Price levels were not touched.

### Before and after (return a year on the money put in, year 3, three seeds)

| Trade | Before | After | What changed | Real-world picture |
|---|---:|---:|---|---|
| airline | -3% (bankrupt) | 6% | demand level x3.2, awareness 30, probe funds | regional carriers earn 3 to 8% EBIT in a good year, lose in a bad one |
| shipping | -25% | 7% | demand level x1.9, capacity x1.7, awareness 24 | small coasters: 5 to 10% on capital, cyclical |
| skires | -8% | 7% | demand level x1.6, capacity x1.8 | lift operators 3 to 8%, very weather dependent |
| indoorski | -0% (could not be opened) | 3% | demand level x1.7, capacity x1.5 | indoor snow centres: break-even to low single digits |
| farm | -10% | 5% | demand level x2.2, capacity x1.9 | farm businesses 2 to 6% on capital |
| vineyard | -2% | 5% | demand level x2, capacity x1.3, awareness 22 | 4 to 8% once the vines are mature |
| factory | -6% | 8% | demand level x2 | contract manufacturers 6 to 12% |
| wh3pl | -4% | 7% | demand level x1.8, capacity x1.25 | third-party logistics 5 to 8% EBIT |
| courier | 4% | 13% | demand level x2, capacity x1.2 | franchise-type parcel delivery 8 to 15% |
| hardware | -3% | 9% | demand level x2 | DIY and builders' merchants 5 to 10% |
| grocery | -0% | 5% | demand level x1.9 | independent grocers 1 to 3% of sales, 5 to 8% on capital |
| cardealer | -0% | 5% | demand level x1.8 | dealerships 1 to 3% of sales, 8 to 15% on a small equity |
| carrepair | -9% | 8% | demand level x2.1 | independent garages 5 to 10% of sales, payback 4 to 6 years |
| boutique | 4% | 10% | demand level x1.5 | independent fashion retail 5 to 10% |
| brewery | 8% | 12% | demand level x1.5 | craft breweries 5 to 12% once volumes are there |
| hotel | 2% | 11% | demand level x1.8, awareness 24 | hotels 6 to 12% on invested capital at 65 to 75% occupancy |
| casino | 3% | 12% | demand level x1.5 | licensed casinos are very profitable; kept at the low end |
| kiosk | 5% | 7% | demand level x1.4 | convenience kiosks 5 to 10% |
| furniture | 3% | 7% | demand level x1.3 | furniture makers 4 to 9% |
| dental | 3% | 5% | demand level x1.8 | dental practices 10 to 20% of sales but heavy equipment: 5 to 12% on capital |
| pcbang | 4% | 8% | demand level x1.6 | internet cafes 5 to 12% |

Left alone because they were already in a believable band: bakery 12%, restaurant 6%, gym 16%, nightclub 15%, trucking 7%, cafe,
barber, physio (small shops and clinics with a low capital base, 10 to 30% on a small stake is normal for an owner-operator).
The numbers live in `Engine/Sources/Businesses/Resources/trade_tuning.json` (merged over `trades.json` and `balance.json` at
load; see `TradeTuning.swift`). The original's golden numbers for these trades no longer apply, so the parity tests skip them.

### Still imperfect

* Results swing by 5 to 10 points between seeds (each company has a hidden "fit" with its concept); a single played company can
  do much better or worse than the table.
* A start-up that needs a licence for a year (airline AOC 52 weeks, banking, casino) pays its staff and aircraft finance
  during the wait because "Fill in what is missing" hires everybody at once. That first loss-making year is realistic in size
  but the estimate shown before starting does not include it; the airline needs about twice the estimate in cash to reach opening day.
* Shipping with every advertising channel at its maximum still returns 68 percent (two ships, lumpy demand); no real shipper
  could buy that growth with advertising.
* Staffing agency and consulting run by hired staff lose money: one employee costs more than the hours clients book at first.

## Addendum: after the rent fix (see `BALANCE_PARITY.md`)

The tables above were produced while the native game paid every company's rent again, and in growing amounts, each month
(`Payday.payBills`). That is fixed, so every cash and return figure above is too low for any trade with premises. A fresh run of
the same probe (`LEDGER_BALANCE=1 LEDGER_MKT=1`, one seed, three years; money in is now larger because the start-up estimate includes
the licence wait) gives, for the trades compared with the original:

| Trade | Return a year before | after |
|---|---:|---:|
| bakery | 12% | 30% |
| barber | 15% | 36% |
| boutique | 4% | 15% |
| cafe | 29% | 42% |
| courier | 4% | 4% |
| gym | 16% | 22% |
| restaurant | 6% | 28% |
| webdev | 51% | 51% |

Most trades with premises moved up by 5 to 25 points, so the verdict "no trade makes you rich quickly" still stands in money
terms but the capital-heavy trades listed as losing money (grocery, hardware, car repair) are much closer to break-even. The
full table was not regenerated; run the probe to refresh it.
