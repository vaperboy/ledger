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
off. Capital-heavy trades earn little or lose money (see below). A regular test (`BalanceGuardTests`) keeps it that way.

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
| Groceries, kiosks, bakeries, cafés starved of customers | Walk-in awareness was the same as a niche boutique's | Everyday shops get a higher neighbourhood awareness (32 instead of 20) |

## Results (with a modest ad plan: search, social and website at their lower budgets)

| Trade | Money in (k) | Profit, year 3 (k) | Return a year | Worth / money in | Run by hired team: return | Every channel at max: return |
|---|---:|---:|---:|---:|---:|---:|
| acctfirm | 1307 | 2083 | 159% | 8.0x | 78% | -6% |
| airline | 1727017 | -43277 | -3% | 0.0x | -2% | -3% |
| bakery | 9416 | 1009 | 11% | 0.2x | 12% | -1% |
| barber | 2032 | 307 | 15% | 0.1x | -9% | 7% |
| boutique | 1831 | 79 | 4% | 0.0x | -10% | 2% |
| brewery | 10245 | 853 | 8% | 0.5x | 2% | -13% |
| cafe | 2586 | 757 | 29% | 0.6x | 1% | 8% |
| carclean | 226 | 479 | 212% | 5.7x | -25% | 35% |
| cardealer | 32800 | -6 | -0% | 0.0x | 1% | -7% |
| carrental | 3111 | 450 | 14% | 0.5x | 2% | 12% |
| carrepair | 7194 | -657 | -9% | 0.0x | -15% | 0% |
| casino | 61095 | 2108 | 3% | 0.3x | 4% | 1% |
| cleaning | 1002 | 685 | 68% | 3.0x | 9% | 5% |
| cons | 195 | 645 | 330% | 7.1x | -20% | -53% |
| courier | 5877 | 259 | 4% | 0.3x | 2% | 5% |
| dental | 6189 | 181 | 3% | 0.1x | 1% | 11% |
| drivsk | 1411 | 626 | 44% | 2.3x | 8% | -7% |
| estate | 1998 | 442 | 22% | 2.3x | 16% | -15% |
| factory | 56989 | -3364 | -6% | 0.1x | -6% | -3% |
| farm | 15344 | -1460 | -10% | 0.3x | -10% | -5% |
| foodtruck | 484 | 776 | 160% | 5.5x | -7% | 4% |
| fun | 13858 | 3089 | 22% | 0.8x | 9% | 2% |
| furniture | 10567 | 352 | 3% | 0.3x | -1% | -5% |
| gamestudio | 3373 | 228 | 7% | 0.0x | -6% | 21% |
| grocery | 57383 | -3102 | -5% | 0.0x | -6% | -5% |
| gym | 11336 | 1822 | 16% | 0.6x | 16% | -0% |
| handy | 251 | 218 | 87% | 2.6x | -13% | 7% |
| hardware | 22751 | -676 | -3% | 0.0x | -6% | -8% |
| hotel | 48134 | 957 | 2% | 0.3x | 0% | -4% |
| indoorski | 976649 | -57 | -0% | 0.0x | -0% | -0% |
| kiosk | 4541 | 194 | 4% | 0.0x | -8% | 6% |
| law | 1714 | 2124 | 124% | 5.7x | 32% | -17% |
| mktg | 1132 | 501 | 44% | 1.7x | -29% | 10% |
| nightclub | 11813 | 1779 | 15% | 0.5x | 9% | -1% |
| pcbang | 5692 | 224 | 4% | 0.1x | 5% | 5% |
| pets | 1145 | 1143 | 100% | 2.2x | 14% | 22% |
| photo | 222 | 587 | 265% | 7.0x | -27% | -0% |
| physio | 3028 | 398 | 13% | 0.1x | -1% | 12% |
| restaurant | 12539 | 705 | 6% | 0.3x | 5% | -1% |
| security | 2467 | 299 | 12% | 0.1x | 2% | 19% |
| shipping | 126454 | -32123 | -25% | 0.2x | -26% | -19% |
| skires | 128296 | -10395 | -8% | 0.4x | -16% | -9% |
| staffing | 2190 | 48 | 2% | 0.6x | -20% | -31% |
| taxi | 1512 | 552 | 36% | 2.4x | 9% | -10% |
| trucking | 14646 | 972 | 7% | 0.6x | 9% | -7% |
| tutor | 114 | 114 | 99% | 3.1x | -29% | 88% |
| vineyard | 12430 | -294 | -2% | 0.2x | -3% | -1% |
| webdev | 1378 | 708 | 51% | 2.0x | -27% | -21% |
| webshop | 3133 | 541 | 17% | 0.2x | -2% | 5% |
| wh3pl | 19411 | -790 | -4% | 0.1x | -8% | -9% |

## Still not realistic (left for a balance pass with real-world figures)

* Capital-heavy trades lose money in every scenario: grocery, hardware, factory, farm, vineyard, warehouse (wh3pl), car repair,
  shipping, ski resort. Their accounts show thin margins eaten by fines, shrinkage and seasonal swings; a real grocery makes 1-3%.
* The airline always goes bankrupt with the standard set-up; the indoor ski centre cannot be set up with the estimated budget.
* Staffing agency and consulting run by hired staff lose money: one employee costs more than the hours clients book at first.
