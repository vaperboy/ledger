# Balance parity: native engine against the original game

Two things were compared, and they mean different things.

1. **Differential tests** (exact). The same company state is given to the original (running in headless Chromium) and to the
   Swift code, and the numbers must be equal. This was done for demand (all 15 parts), capacity, price, VAT, tax, loan offers,
   annuities, net worth and currency formatting. These pass (`swift test`, folder `Tests/LedgerTests/Golden`).
2. **Statistical comparison** (approximate). Randomness is not drawn in the same order (the native game has more and fewer
   draws in places), so two games cannot match number for number. 12 games of 26 weeks are played in each engine, with two
   different sets of seeds (A and B), and the averages are compared. Tools: `tools/ref/snippets/stats_run_day.js` (original,
   day by day) and `LEDGER_STATS=1 swift test --filter testPrintStatisticsForComparison` (native; `LEDGER_SEED0`/`LEDGER_STEP`
   choose the seeds).

Setup in both: United Kingdom, limited company, standard setup and staff, funded with 1.6 times the start-up estimate, no
marketing, no later decisions. Revenue is the average of the last five closed months; cash is at week 26.

| Trade | Revenue per month, original (A / B) | Revenue per month, native (A / B) | Difference | Cash at week 26, original → native |
|---|---|---|---|---|
| café | 78.5 k / 87.2 k | 87.3 k / 100.5 k | +13 % | 1.61 M → 1.40 M |
| barber | 70.7 k / 72.9 k | 73.1 k / 82.3 k | +8 % | 0.89 M → 0.77 M |
| gym | 283.9 k / 301.8 k | 367.3 k / 380.1 k | **+28 %** | 8.00 M → 7.15 M |
| restaurant | 201.4 k / 234.2 k | 166.7 k / 179.4 k | **−21 %** | 5.08 M → 3.16 M |
| courier | 269.4 k / 265.3 k | 243.1 k / 252.6 k | −7 % | 2.04 M → 1.41 M |
| boutique | 83.8 k / 85.6 k | 84.1 k / 90.3 k | +3 % | 1.12 M → 0.95 M |
| web developer | 40.5 k / 47.5 k | 36.9 k / 40.3 k | −12 % | 1.75 M → 1.69 M |
| bakery | 270.8 k / 306.1 k | 335.1 k / 381.8 k | **+24 %** | 3.30 M → 2.79 M |

Amounts are in the game's accounting unit. The spread between seed sets A and B inside one engine is 3–15 %, so differences
below about 10 % cannot be told from chance. **Not within chance:** gym, restaurant and bakery, and the lower cash at week 26
in all trades (3 % to 38 %).

## What was found and fixed along the way

Each of these was a real difference between the engines, found by comparing averages and then comparing parts:

* The comparison script in the first attempt funded the native company from the estimate at the company's size and the original
  from the estimate at size 1, so the native company started with half the cash. Fixed in the test helper.
* Awareness was lower than the original because "happy customers tell others" (word of mouth and a busy street) was missing.
* Reputation was too high because complaints were missing; ignoring a complaint costs reputation.
* The hype from a viral moment never faded, and a one-shop business could not reach awareness above its local cap. Fixed.
* Companies were not fined for missing paperwork (3–4 % of revenue in the original). Fixed (`StaffExtras`).
* "A company with nobody working closes" was missing. Fixed.
* The decay of awareness for companies that spend nothing on marketing (4 % faster) was missing. Fixed.
* Event titles with `{eq}` were shown with the placeholder. Fixed. `{auth:…}` and `{m:…}` tokens are now resolved when shown.
* Equipment wore as one lump. Each unit now wears and breaks down on its own (warranty, repair cost, days out of use).

## What is still different, and why

| Difference | Cause | Effect |
|---|---|---|
| Gym revenue +28 % | Likely cause (seen, not yet proven by an experiment): at week 26 the original gyms have about one team member fewer, because the original has poaching offers and other staff events that the native game does not have yet (pay talks have since been added; the gym row was measured before that). Native staff are also hired about 5 % above the market rate on average, so they ask for raises later than in the original; cause not found. With the same state, demand and capacity are equal (golden tests). | More staff, more members |
| Restaurant revenue −21 %, cash −38 % | Not yet explained. Demand parts match on the golden state; the difference is in how the state evolves. | |
| Bakery revenue +24 % | Not yet explained. | |
| Lower cash everywhere | Not yet explained; partly more costs in the native books (wages for staff that stay), partly timing of VAT and payables at the moment of measuring. | |
| Equipment | Brand catalogue (reliability, class, performance), used market, leasing and subscriptions are not ported. All units have reliability 1. | Fewer or more breakdowns than the original, depending on brand choices |
| Key accounts, assistant managers, 50 strategic decisions, rivals as businesses | Not ported. | Missing opportunities and setbacks |

Because the native game does not yet reproduce every system, **balance numbers should not be trusted until the open
items above are closed**. They are listed in `KNOWN_GAPS.md`. The harness above is how to check each step.

## Rental and finance trades (UK, three seeds, three years, standard set-up, funded at 1.6x the estimate)

Original (a run of the HTML game with the same set-up) against native (`LEDGER_RF=1 swift test --filter RentalFinanceProbeTests`), year 1 / 2 / 3, millions:

| Trade | Original revenue | Native revenue | Original profit (after mortgage interest) | Native profit |
|---|---|---|---|---|
| resrent | 1.2 / 1.2 / 1.2 | 1.2 / 1.2 / 1.2 | 0.2 / 0.2 / 0.3 | -0.3 / 0.3 / 0.4 |
| comrent | 9.3 / 9.7 / 9.6 | 8.5 / 9.4 / 9.3 | 4.3 / 4.7 / 5.0 | 1.8 / 4.9 / 5.7 |
| parking | 3.6 / 3.7 / 3.8 | 3.5 / 3.7 / 3.6 | 1.3 / 1.5 / 1.6 | 0.4 / 1.6 / 1.7 |
| insco (no marketing) | 6.4 / 6.8 / 5.5 | 0.7 / 7.6 / 1.8 (bust in year 3) | -23 / -18 / -16 | -7 / -23 / -5 |
| bank (no marketing) | 7.9 / 9.2 / 9.4 | 0 / 6.9 / 6.1 | -27 / -21 / -13 | -3 / -26 / -27 |
| fund (no marketing) | 1.5 / 2.5 / 2.1 | 0.5 / 2.8 / 1.8 | -1.8 / -0.4 / -1.0 | -1.3 / 0.2 / -0.7 |

The first native year is shorter (the company opens after paperwork; the insurer waits about 40 weeks for product approvals).
The weekly models give the same numbers as the original to ten digits on a saved game (differential tests), so the differences
are the random draws and the opening weeks. See KNOWN_GAPS.md for what a mature finance company earns.
