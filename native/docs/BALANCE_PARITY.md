# Balance parity: native engine against the original game

Two things were compared, and they mean different things.

1. **Differential tests** (exact). The same company state is given to the original (running in headless Chromium) and to the
   Swift code, and the numbers must be equal. This was done for demand (all 15 parts), capacity, price, VAT, tax, loan offers,
   annuities, net worth and currency formatting. These pass (`swift test`, folder `Tests/LedgerTests/Golden`). No golden was
   changed by the work described below.
2. **Statistical comparison** (approximate). Randomness is not drawn in the same order, so two games cannot match number for
   number. 12 games of 26 weeks are played in each engine with two sets of seeds (A = 1000 + 37 k, B = 5000 + 53 k) and the
   averages are compared. The spread between A and B inside one engine is 5 to 25 %, so **differences below about 10 % cannot be
   told from chance** (a single trade moved by 8 % to 24 % between the two seed sets with the same code).

How to run it:

| What | Original | Native |
|---|---|---|
| Averages (revenue of the last five closed months, cash at week 26) | `node tools/ref/ev.js ledger.html tools/ref/snippets/stats_run_day.js` | `LEDGER_STATS=1 LEDGER_FAITHFUL=1 swift test -c release --filter testPrintStatisticsForComparison` (`LEDGER_SEED0`, `LEDGER_STEP` choose the seeds) |
| Week by week averages (demand, capacity, units, revenue, awareness, reputation, quality, staff, cash, books) | `snippets/trace_weeks.js` | `testPrintWeekTrace` in `BalanceTraceTests` (`LEDGER_TRADES=a,b`) |
| One company week by week (cash, stock, payables, books) | `snippets/weekly_one.js` | `testPrintWeeklyOne` |
| Set-up cost and what "fill in what is missing" buys | `snippets/setup_compare.js` | `testPrintInjected` |
| Parts of the quality target | `snippets/quality_parts.js` | `testPrintQualityParts` |
| Who changes awareness | `snippets/aware_sources.js` | (see `Marketing.swift`, `Satisfaction.swift`) |

`LEDGER_FAITHFUL=1` makes the native test play like the original's script: one offer per job to the median-priced candidate
with no second try (`faithfulHiring`), nobody replaced when they leave, no routine complaints answered. Without it the native
game plays like the app does (better hires, replaced leavers, answered complaints), which is deliberately a little richer.

Setup in both: United Kingdom, limited company, standard setup and staff, funded with 1.6 times the start-up estimate, no
marketing, no later decisions.

## Result

Revenue per month (thousands of accounting units, about 13.5 to the pound), seeds A / B. "Before" is what this document said
before this work (old harness, old code); "original" is re-measured with the corrected harness; "native" is the code now,
played faithfully.

| Trade | Before: original → native (A) | Original now (A / B) | Native now (A / B) | Difference now | Verdict |
|---|---|---|---|---|---|
| café | 78.5 → 87.3 (+13 %) | 82.2 / 92.4 | 104.8 / 120.0 | +27 % / +30 % | deliberate (neighbourhood awareness); +7 % / +8 % without it |
| barber | 70.7 → 73.1 (+8 %) | 70.7 / 80.8 | 78.7 / 84.9 | +11 % / +5 % | chance |
| gym | 283.9 → 367.3 (**+28 %**) | 341.8 / 361.8 | 348.8 / 386.1 | +2 % / +7 % | fixed (was a measuring artefact) |
| restaurant | 201.4 → 166.7 (**−21 %**) | 143.3 / 157.2 | 131.5 / 194.1 | −8 % / +24 % | fixed (artefact and start-up money); rest is chance |
| courier | 269.4 → 243.1 (−7 %) | 269.4 / 283.1 | 269.0 / 285.7 | 0 % / +1 % | fixed (missing awareness rule) |
| boutique | 83.8 → 84.1 (+3 %) | 83.8 / 89.7 | 86.3 / 96.2 | +3 % / +7 % | chance |
| web developer | 40.5 → 36.9 (−12 %) | 40.5 / 47.5 | 39.9 / 45.4 | −1 % / −4 % | fixed (same awareness rule) |
| bakery | 270.8 → 335.1 (**+24 %**) | 317.7 / 342.9 | 379.6 / 434.6 | +19 % / +27 % | deliberate (neighbourhood awareness); −4 % / +5 % without it |

Cash at week 26 (millions), seeds A / B:

| Trade | Before: original → native (A) | Original now (A / B) | Native now (A / B) | Difference now |
|---|---|---|---|---|
| café | 1.61 → 1.40 (−13 %) | 1.55 / 1.61 | 1.64 / 1.69 | +6 % / +5 % |
| barber | 0.89 → 0.77 (−13 %) | 0.82 / 0.90 | 0.89 / 1.00 | +7 % / +12 % |
| gym | 8.00 → 7.15 (−11 %) | 7.85 / 7.91 | 8.15 / 8.24 | +4 % / +4 % |
| restaurant | 5.08 → 3.16 (**−38 %**) | 5.14 / 5.29 | 5.21 / 5.26 | +1 % / −1 % |
| courier | 2.04 → 1.41 (−31 %) | 1.96 / 2.10 | 1.78 / 1.78 | −9 % / −15 % |
| boutique | 1.12 → 0.95 (−15 %) | 1.10 / 1.11 | 1.16 / 1.17 | +5 % / +5 % |
| web developer | 1.75 → 1.69 (−3 %) | 1.72 / 1.77 | 1.69 / 1.72 | −2 % / −3 % |
| bakery | 3.30 → 2.79 (−15 %) | 3.20 / 3.48 | 3.47 / 3.58 | +9 % / +3 % |

Played the way the app plays (no `LEDGER_FAITHFUL`), revenue per month A / B: café 112.9 / 130.4, barber 80.4 / 93.4, gym 366.0 /
391.7, restaurant 168.7 / 207.9, courier 273.6 / 294.3, boutique 88.9 / 96.5, web developer 40.5 / 46.2, bakery 417.9 / 504.8;
cash 1.65 / 1.68, 0.90 / 0.97, 8.10 / 8.12, 5.13 / 5.24, 1.63 / 1.73, 1.16 / 1.16, 1.69 / 1.73, 3.44 / 3.67. That is 5 to 15 %
more revenue than the faithful play, on purpose: leavers are replaced, complaints are answered, hiring picks the best value.

## What was wrong, in the order it was found

Each item is a real cause, found by tracing the same company week by week in both engines.

1. **Rent was paid again every month (native bug, fixed).** `Payday.payBills` pays rent, then suppliers. After paying the rent
   it re-read the company from the game state before the rent change had been written back, so the rent stayed "owed". The next
   month it paid all rent owed so far, then the same again: 1, 2, 3, 4, 5 months of rent in months 1 to 5. A boutique with 3 100
   rent a week paid about 100 000 too much in 26 weeks. This is the whole of the "lower cash at week 26 in every trade" (3 to
   38 %): the books (profit and loss) were right, only the cash was wrong, which is why nothing in the revenue tables showed it.
   Found by comparing the boutique, which has identical revenue in both engines, and noticing 190 000 of outflow that no
   category of the books explained. Fix: write the company back before moving the money (`Payday.swift`).
2. **The original's script measured an older company (harness, fixed).** `setupAndOpen` lets the weeks of paperwork pass before
   the script's 26 weeks start (3 weeks for a gym, 10 for a restaurant), so the original company was 29 to 36 weeks old when
   compared with a native company of 26 weeks, and the "last five closed months" were different months. This alone turned the
   restaurant from 201 k into 143 k and the gym from 284 k into 342 k. The script now stops when the game clock reads week 26.
3. **Restaurant started with too little money (native bug, fixed).** The original's start-up estimate adds the wages and rent of
   the weeks spent waiting for a long licence (`r.wait`, a restaurant waits 10 weeks: 880 000). The native estimate left it
   out, so the same "1.6 times the estimate" gave the restaurant 1.4 million less. `CompanySetup.estimate` now has `wait`, and
   the estimate on the new-company screen includes it. Restaurant: 4.74 million, the original's 4.74 million.
4. **"Fill in what is missing" hired differently (harness).** The original makes one offer per job to the median-priced
   candidate and does not try again when the person refuses (about 1 offer in 9 is refused), so its companies often start one
   person short. The native button retried up to six times and chose the best value, so native companies started complete
   and, with "replace people who leave" on, stayed complete. That alone explained most of the gym's extra members and wages.
   `quickSetup(faithfulHiring:)` reproduces the original for the comparison; the app keeps its better behaviour.
5. **"People who used you tell others" was missing (native port gap, fixed).** The original has a weekly rule
   (`trades_in_hours.js`, "weekly") that lifts the awareness of a busy business towards a floor of at most 32: about
   `28 * sqrt(average load of the last 26 weeks) * quality factor`, closing 8 % of the gap per week. It was never ported.
   Without it a busy courier stayed at awareness 4.6 against the original's 7.1, and demand was 24 % lower. Ported as
   `Satisfaction.knownByUse`; courier revenue 243 k → 269 k (original 269 k), web developer −12 % → −1 %. Not ported inside it:
   the review-score factor (reviews are not a native screen) and the hour-priced trades (plumber, electrician; project family).
6. **Awareness of neighbourhood shops (deliberate native difference, kept).** In the original every shop on a street has an
   organic awareness of 20 (`organic_awareness.js`); native uses grocery 48, kiosk 44, pharmacy 44, bakery 40, hardware 38,
   café 32 (`Marketing.organicAwareness`, added in the earlier balance pass, see `BALANCE_REPORT.md`). This is the whole of the
   café (+27 %) and bakery (+19 %) difference: with the table emptied the café is +7 % / +8 % and the bakery −4 % / +5 %.
7. **Smaller differences left as they are:** the original draws a vendor for the goods of each business (quality −0.35 to +0.35
   steps of 10, cost ±10 %), brand and class for vehicles and equipment, and loses a person to poaching; none of that is ported
   (`KNOWN_GAPS.md`). Together they probably explain native quality about 2 points above the original (the original's equipment is
   slightly more worn, its staff slightly less skilled, its goods a little cheaper and a little worse) and the gym's staff count
   (original 1.7 at week 26, native 2.2).

The earlier "likely cause" in this document for the gym (one team member fewer because of poaching) was only a small part of it;
the experiment showed the main causes were 2 and 4.

## Which is closer to real life

The figures below are rough real-world benchmarks from memory (UK, independent small businesses) and are used only to choose
between two engines that disagree, or to flag a number both get wrong. Amounts are converted at 13.5 per pound.

| Trade | Game (native, faithful, A) | Real life | Decision |
|---|---|---|---|
| Café, 25 m², 1 barista + owner | 105 k a month = £7.8 k = £93 k a year (£3.7 k per m²); original £73 k | A small independent café turns over £80 000 to £150 000 a year, £3 000 to £6 000 per m²; staff cost 30 to 35 % of sales | Native is closer. Passers-by on a high street know a café at once; awareness 10 for a café on opening day (original) is too shy. Kept. |
| Bakery shop, 75 m², 2 bakers + helper + cashier + owner | 380 k = £28 k = £338 k a year, about £68 k per head; original £283 k, £57 k per head | An independent UK bakery shop takes £250 000 to £500 000 a year, £60 000 to £85 000 per head; wages 30 to 38 % | Native is closer. In the original wages are about 84 % of revenue in steady state (50 k of revenue against 42 k of wages a week), real shops would close. Native 51 %. Kept. |
| Gym, 335 m², 2 trainers + receptionist | about 250 to 280 members at about £71 a month = £300 k a year, £920 per m² | A small UK gym of that size has 150 to 400 members at £25 to £60 a month (budget, mid) up to £80 and more (boutique): £150 000 to £450 000 a year, £300 to £700 per m² | Both engines agree (after the fixes +2 % / +7 %), and both are at the generous end for a gym with no personal-training upsell. Not changed: the demand and price golden tests fix it, and a trade-wide retune is a design decision. Flagged. |
| Restaurant, 80 m², chef + cook + 2 waiters | 131 k a month = £117 k a year in the first half year; 10 covers a day against a capacity of 40; £53 a cover | 35 to 40 seats do 1 to 2 turns a day at £25 to £40 a head: £300 000 to £700 000 a year in a mature year; a new restaurant reaches about 60 % of that in six months | Both engines are low in the first six months, because awareness starts at 10 of 100 and demand is built on it. The capacity (40 a day) and the price per cover (high end) are plausible; the ramp is slower than real. The three-year result (`BALANCE_REPORT.md`) is about 28 % a year on the money put in, which is above the real 10 to 20 %. Not changed in this pass; the first-half-year dip is a start-up effect, not a bug. |
| Courier | 269 k a month | no reliable figure for a 3 vehicle courier | parity reached; nothing to decide |

Three-year returns after the rent fix (profit in year 3 over the money put in; `BALANCE_REPORT.md` addendum): café 42 % (was 29 %),
bakery 30 % (12 %), gym 22 % (16 %), restaurant 28 % (6 %), barber 36 % (15 %), boutique 15 % (4 %). Real operating margins are
café 8 to 15 % of sales, bakery 5 to 10 %, gym 10 to 20 %, restaurant 3 to 9 %. A return on the start-up money is not a margin
(the owner's own work is unpaid, and the start-up money is small), but the restaurant's 28 % a year is above what real
restaurants return (10 to 20 %), and is flagged, not changed here.

## Deliberate differences (and why)

| Difference | Reason |
|---|---|
| Neighbourhood awareness per kind of shop (see 6) | A shop people need every week is known by its street. Realistic; the original's 20 for everything starves cafés and bakeries. |
| `quickSetup` retries a refused offer and picks the best value; "replace people who leave"; routine complaints answered by staff | These are what a player would do next; the comparison uses `LEDGER_FAITHFUL=1` to switch them off. |
| Native is played day by day | The original's day mode. |

## Still different, not explained or not ported

| Difference | Cause | Effect |
|---|---|---|
| Courier cash −9 % / −15 % with equal revenue | About 130 000 of it is there in week 1: the original buys vehicles from a brand catalogue (van 350 800 and bike 61 600 in the sample, native 330 000 and 65 000) and its estimate scales vehicles by a country factor; native uses one standard price. The rest (depreciation 90 k against 75 k) was not traced. | A few percent of cash |
| Quality about 2 points higher, staff count higher, rep 1 to 3 points higher | Vendor choice, equipment brands and reliability, poaching and promotions are not ported | Small |
| Equipment | Brand catalogue, used market, leasing, subscriptions are not ported. All units have reliability 1. | Fewer or more breakdowns than the original, depending on brand choices |
| Key accounts, assistant managers, 50 strategic decisions, rivals as businesses | Not ported | Missing opportunities and setbacks |
| Review score factor of "people who used you tell others" | Reviews are not ported as a screen | Small |

Balance numbers can now be trusted to about ±10 % for the eight trades above. For the other 42 trades only the cash fix applies
with certainty; their revenue has not been compared with the original.
