# Balance pass (local, no CI)

Harness: `Engine/Tests/LedgerTests/CareerSimHarness.swift`, skipped unless an env var is set.
`LEDGER_SWEEP=1` plays every startable trade (standard set-up, modest ads, 1.3x the estimate, topped up when short) for 3 years in
CH, UK, MX, JP. `LEDGER_CAREER=1` plays scripted 10-year careers (baker, landlord, investor, momentum trader, hardware shop,
cleaning firm); `LEDGER_SCENARIO=funded` gives all careers the same stake, default is the start loan only.
`LEDGER_MARKET=1` prints index fund prices. Money in local currency; margins = profit / revenue.

## Findings against the targets

| Target | Result before | Verdict |
|---|---|---|
| First company profitable in 6-12 months | Start loan affords only the tutor business (UK 128k of 88k estimate; JP 93k of 88k). Honest start (start loan only): 8 of 12 runs (UK, MX, JP) went bust, CH survived. First year profit > 0 in 4 of 12 runs. | Not met. Not changed (see open points). |
| 1M in 2-4 years | Honest start: never in 10 years in any career/country (CH reaches 185k at year 10). Funded equal stake: landlord UK 4.7 years, others fall below the stake. | Not met. |
| 10M much later | Never reached (honest). | Trivially met. |
| No trade a money machine (ROI > 60% steady) | Owner-run micro services (carclean, cons, photo, handy, foodtruck, pets, acctfirm) show 60-200% ROI on a 20-30k stake, but profit is about one median wage (UK carclean 11-29k a year). `fund` (investment company) earns 150-430% ROI, 50-80% margin from year 3. | Services fine (labour income). `fund` flagged, not changed. |
| No trade always loses | electrician, plumber, event, staffing, restaurant, trucking, construction lost money in every country; bakery in 2 of 4. Documented calibration (electrician 12%, plumber 12%, construction 6%) had regressed to -17..-48% after the payroll/VAT audits. | Fixed below. |
| Index fund | Median index 10 years: about -0.6% a year (8 seeds: 59, 75, 46, 107, 106, 179, 79, 107 from 100). Investor/trader careers ended below their stake. | Fixed below. |

## Changes

| File | Change |
|---|---|
| `Businesses/ProjectModel.swift` priceFactor | electrician 1.1 -> 2.2, plumber 1.15 -> 2.3, construction 1.27 -> 2.6, event 0.82 -> 1.15 |
| `Businesses/Resources/balance.json` priceLevelByTrade | restaurant 1.97 -> 2.4, staffing 1.26 -> 1.7, trucking 1.63 -> 2.1, bakery 1.98 -> 2.3, tutor 1.15 -> 1.45 |
| `Investments/Markets.swift` | every market mood drifts +0.12% a week more; median index about +6% a year (Monte Carlo of the same rules) |
| `Events/RichList.swift` | crash fix: a net worth of a few cents overflowed `Int` in the rank estimate |

## Trade margins and ROI, year 1 / year 3 (3 seeds, mean of runs)

| Trade | | CH | JP | MX | UK |
|---|---|---:|---:|---:|---:|
| electrician | before | -54 / -16 | -74 / -18 | -75 / -26 | -76 / -21 |
| | after | 10 / 21 | 5 / 25 | -2 / 20 | 3 / 18 |
| plumber | before | -56 / -34 | -84 / -21 | -141 / -32 | -64 / -26 |
| | after | 9 / 16 | 4 / 20 | -30 / 19 | 4 / 18 |
| construction | before | -24 / -11 | -13 / 1 | -70 / -5 | -27 / -17 |
| | after | 9 / 14 | 13 / 20 | 0 / 12 | 6 / 11 |
| event | before | -59 / -8 | -94 / -10 | -126 / -40 | -83 / -8 |
| | after (factor 1.15) | -17 / 13 | -39 / 9 | -71 / -8 | -32 / 12 |
| bakery | before | -15 / -2 | -14 / -7 | -14 / 2 | -25 / -7 |
| | after | -1 / 9 | 2 / 15 | 1 / 14 | -4 / 1 |
| restaurant | before | -24 / -24 | -29 / -1 | -24 / -2 | -46 / -32 |
| | after | -5 / -1 | -7 / 14 | -4 / 15 | -16 / -13 |
| staffing | before | -35 / -24 | -30 / -6 | -16 / -4 | -45 / -19 |
| | after | -16 / -3 | -17 / 4 | -7 / 5 | -21 / -9 |
| trucking | before | -48 / -1 | -45 / -10 | -154 / -65 | -52 / -17 |
| | after | -4 / 20 | -11 / 14 | -78 / -33 | -4 / 13 |
| tutor | before | 15 / 20 | -58 / 1 | - | -30 / 0 |
| | after | 40 / 45 | -25 / 1 | -147 / -22 | 5 / 23 |

(project trades after: electrician/plumber/construction rows are the final factors; event, bakery, restaurant, staffing, trucking, tutor
rows come from the run with the same values.) Full 61-trade before table: all trades not listed above were not touched.

## Career runs before (10 years, 3 seeds, local currency; "after" not re-run for lack of time)

Honest start, all careers began with the tutor business (nothing else affordable, banks lend nothing at net worth 0):
bust UK 2/3, MX 3/3, JP 3/3, CH 0/3; median net worth year 1/3/5/10 CH 10.9k / 44k / 83k / 185k; others bust.
Funded equal stake (net worth year 10 divided by year 1, medians): investor UK 0.56, CH 0.19; trader UK bust 1/3; landlord UK 1.85,
JP 2.2, MX bust 3/3; hardware UK 0.62, JP 9.4; baker UK 0.18, CH bust 3/3; cleaning UK 0.34. Cash after year 1 (honest, local): UK
2.1k, MX 17k, CH 0.5k, JP 0.

## Open points for the owner

* Start loan vs first business: it affords only the tutor business, which is a coin flip. Raising `start.loan` breaks the
  FoundationTests golden (original values), so left alone. Needs a decision: loan size, a cheaper standard set-up, or a cheap first trade.
* Bank lends nothing to a new player (net worth 0 after the start loan), so there is no second step up.
* A player with no company and cash below minus three overdraft limits is declared insolvent instantly even with millions in shares
  (`Failure.checkOver`); engine rule, not changed.
* `fund` company ROI 150-430%; real estate developer, oil, power, insurer, shipping, indoor ski, estate agent lose in many cells (lumpy
  models); MX trucking still -33%. Not judged.
* Feel: are 20-25% margins for electrician/plumber right, and is +6% a year for the index too generous?
