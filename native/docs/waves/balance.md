# Balance notes (4 Nov): why ten trades lost money in the standard two-year probe

Probe: `BalanceCausesProbe` (`LEDGER_P2=<trades>`, optional `LEDGER_YEARS`), UK, seed 11, the standard owner of `BalanceProbeTests.play` (quick set-up, size 0.4, manager hired at the start when the standard team has 4 or more people or the owner cannot work in the trade, every manager proposal left unanswered). Extra switches in `play`: `LEDGER_PLAYTRACE=1` (staff, wages, capacity parts every 8 weeks, books of the last year, notes), `LEDGER_NOMGR=1` (owner-operator, no manager), `LEDGER_APPROVE=1` (owner approves the manager's hire, equipment, vehicle, space and premises proposals). Amounts in accounting units (1 GBP = 13.5).

## Profit year 1 / year 2, standard owner (thousands)

| Trade | Money in | Before | After | Variants after (y1 / y2) |
|---|---:|---|---|---|
| security | 4327 -> 1683 | -1885 / -2034 (bust risk) | +136 / +135 | owner-operator +890 / +1422; approving proposals +18 / +467 |
| drivsk | 3245 -> 2292 | -1097 / -1704 | -35 / +1571 | owner-operator +60 / +246; approving -39 / +1322 |
| physio | 3275 -> 1840 | -1556 / -1319 | -579 / +106 | owner-operator +383 / +509; approving +225 / +782 |
| dental | 5190 -> 3622 | -1567 / -2491 | -330 / -302 | owner-operator +1703 / +2145; approving +319 / +1366 |
| law | 3271 -> 1802 | -1215 / -1271 | +774 / +1924 | owner-operator -523 / -407 (demand 8 to 16 hours a week, no one sells) |
| mktg | 2288 -> 1678 | -906 / -1036 | -654 / -751 | owner-operator +126 / +91 |
| courier | 2611 | +282 / -496 | unchanged | owner-operator +704 / +197; approving +1240 / +1290 |
| nightclub | 8187 | -839 / +524 | unchanged | approving -839 / +628; years 1 to 4 standard: y4 -849 |
| airline | 284892 | -29775 / +56828 | unchanged | years 1 to 4: y4 +32731 |
| salmon | 318196 | -45055 / -42233 | unchanged | years 1 to 5: y3 +64911 (first harvest in month 25) |
| startup | 4517 | -2703 / -1765 (bust) | unchanged, see below | founded properly: see below |

"Money in" falls because top-ups (cash below -50k) were no longer needed.

## Causes found

1. Support-role cover with a manager (code, `Capacity.swift`). In trades that sell hours, the time an owner or manager spends as dispatcher or receptionist was converted into billable hours of the FIRST role. At size 0.4 the support post (0.4 of a dispatcher) is not hired, the manager covers it, and the whole firm was capped at about 19 guard hours a week while its two guards could give 72. Now the covering time counts at that role's own scale, like an employee in the post. Affects security, drivsk, physio, law, mktg, dental (and other hour trades with a manager and a missing support role).
2. Congestion cost on booked trades (code, `CompanyWeek.swift`). The 4 Nov cost (18 percent of payroll above 85 percent utilisation) was made for walk-in floors but covered every `svc` trade. A full diary is a waiting list, not a crowd. Physio paid about 460k a year (cost of sales 14 percent against 4 percent in the data), dental about 870k. Booked trades (law, acctfirm, cons, mktg, webdev, tutor, drivsk, physio, dental, security, gamestudio) no longer pay it. Walk-in trades (restaurant, barber, ...) keep it.
3. Not data errors (nothing changed in trades.json or tables.json):
   - Manager at size 0.4. A trade is designed so that its standard team earns the margin `m` (`TradeCatalog.calibrate`: demand = fixed costs / (ticket x (1 - costs - m))). The manager is not in that design (the owner is: `ownerFTE`). At size 0.4 a manager paid 52k to 77k a month takes 30 to 60 percent of the sales of a one- or two-person trade (mktg: one marketer plus a manager; security: 1.75 guards plus a manager). Without a manager the same trades earn 4 to 90 percent a year (table). The probe hires the manager from the head count of the size-1 team (4 or more), not of the team actually hired.
   - Unanswered proposals. The manager has no spending authority at the start, so "Hire a ...", "Expand the premises" and "Buy ..." wait for the owner and lapse after 3 weeks; the standard probe never answers. Courier (premises cap 1360 parcels against demand of 2000 to 5000, 4.5 couriers idle 25 percent), dental (one chair and 60 m2 against demand of 120+) and physio stay capped; with approval courier earns +1.2m a year and dental +1.4m.
   - Thin by design: `m` is 0.04 courier, 0.04 airline, 0.06 security, 0.08 nightclub, close to real net margins (couriers 4 to 6 percent, airlines 3 to 8, contract guarding 5 to 8, clubs 5 to 15). A manager and a ramp-up year turn that into a loss; the game does not guarantee otherwise.
   - Nightclub payroll is 51 percent of sales at year 4 (real 25 to 35). The standard team (12 people for 1067 guests a week, open 40 hours) looks 1.5 to 2 times what a small club rolls, but staff, demand and capacity are one calibration (F, Dc, capD) held against the original; changing it moves the golden tests. Left as a question.
   - Salmon: the farm opens in week 36 to 40, the first cohort needs 78 weeks, so the first harvest lands in month 25. The two-year window ends before it (cash falls from 226m to 0.1m on feed, which is held as stock). Over five years: year 3 +64.9m on 330m in (20 percent), harvest months +75m to +94m.
   - Airline: positive from year 2 (+56.8m, 20 percent on 285m; year 4 +32.7m). Not thin in this run.
   - Startup is not a trade-menu trade (`SpecialFamilies.isStartable` excludes it): a company made through `CompanySetup.create` has no product record, `StartupModel.context` returns an empty week and it can only bleed its two developers. A startup founded as the game does it (`Startups.found`, SaaS CRM, subscription, two builders, seed x1; `LEDGER_STARTUP=saas,crm,sub,c2,1`) launches in week 10, grows to 70 customers (20k a week) and runs out of seed in week 80, staff leave, 26 customers remain and it earns 16 to 20k a month. A venture that needs a funding round or marketing, as designed.

## Checks
- `CountryNeutralityTests`, `SaveRoundTripTests`, `TradeCatalogTests`: pass.
- `MoneyLiteralLintTests`: fails on literals in UsedCarWeek, DealerAddons and Wave11Bases, none in the files changed here.
- `BalanceGuardTests`: airline and shipping, vehicle trades, hired team, no trade makes you rich: pass. `testCapitalHeavyTradesEarnModestReturns` fails on cardealer (-20.5 percent a year, 22.8 times the money after three years), with identical numbers after each of the two changes (cardealer is not an hour trade and not in the booked set): not caused here.
