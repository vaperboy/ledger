# Audit part 4a: the other 16 countries

Countries: SE, LT, FR, ES, NL, CA, AU, KR, BR, CH, AE, IT, DK, FI, IE, SG (UK, US, MX, PL, DE, JP, NO were probed earlier, see `calculations.md`).
Test: `native/Engine/Tests/LedgerTests/CountryAuditProbeTests.swift` (22 tests, about 35 s in total, all pass after the fixes below).

## Method
- Half year: a limited-company cafe (5,000,000 units paid in, share capital counted) played 26 weeks day by day with payroll approved. Checked `Ledger.gaps` (empty) and equity (assets - debts) = injected capital (incl. share capital) + booked profit - tax, tolerance max(20,000 units, 2% of profit).
- Minimum wage: hire the cheapest candidate (barista, "young" tier) at wage 1, then at the minimum, then at asking; the stored wage and every employee must be at or above `World.minimumWage`.
- Dismissal: five years' service, redundancy; quote against `LabourRules.termination` x on-cost, and against the cash that actually leaves the company when `Dismissal.dismiss` books it.
- Data tests: shared employer on-cost, VAT filing months and rates, personal tax at median and 5x median (rises with income, no negative), overtime pay formula, leave and notice present.

## Defects found and fixed
| ID | What | Fix |
|---|---|---|
| P4A-1 | CALC-01 was not fixed on this branch: payroll charged `employerCostFactor` (social + pension + injury) but notice in lieu, contract-talk extra notice, vehicle running and team/assistant/manager releases charged social only. Understated by 1 to 17 points of pay in FR (1% injury), ES, NL (5% pension), AU (13%), BR (10%), CH (8%), DK (8.5%), FI (17.8%), IE, SG, AE, IT, CA, KR | New `Country.employerOnCost(monthlyWage:)` = `employerSocialRate` + pension + injury. Used by `WorldLabour.terminationPayments`, `Dismissal.quote` (extra notice), `ContractTalk` (3 places), `VehicleRunning`, assistant pay and release, team head pay and release (`ManagerPeople`, `ManagerTeam`), layoff preview (`StaffProfile`), overtime pay (`StaffRoutine`, which used social only) |
| P4A-2 | Overtime was paid with social-only on-cost, so overtime hours cost less than the same hours in payroll | Same function |

At the median wage `employerCostFactor` = 1 + `employerOnCost` (tested for all 16), so payroll and every quote agree. Tests that pinned the old factor (`DismissalEngineTests`, `DismissalCharacterizationTests`, `ContractTalkTests`) now use the shared function.

## Per country
Min = monthly minimum in local currency at the standard week; OT = overtime premium; "paid" = hired at wage 1 / minimum, ends at the minimum or asking.

| Country | Half year (gaps, equity) | Min wage on cheapest job | OT | Leave | Notice / severance (5 y) vs booking | VAT rates / filing | Personal tax median / 5x |
|---|---|---|---|---|---|---|---|
| SE | ok | ok (23,883) | +50% | 25 d | ok / none statutory | 25/12/6, quarterly | rises, below 50% / 65% |
| LT | ok | ok | +50% | 20 d | ok | 21/12/5, monthly | ok |
| FR | ok | ok | +25% | 25 d | ok (tiered severance) | 20/5.5/10, monthly | ok |
| ES | ok | ok | +25% | 22 d | ok | 21/4/10, quarterly | ok |
| NL | ok | ok | +25% | 20 d | ok | 21/9/9, quarterly | ok |
| CA | ok | ok | +50% | 10 d | ok | 13/0/5, quarterly | ok |
| AU | ok | ok | +50% | 20 d | ok | 10/0/10, quarterly | ok |
| KR | ok | ok | +50% | 15 d | ok | 10/0/10, half-yearly | ok |
| BR | ok | ok (FGTS fund and fine) | +50% | 30 calendar | ok | 17/7/12, monthly | ok |
| CH | ok | ok | +25% | 20 d | ok / none | 8.1/2.6/3.8, quarterly | ok |
| AE | ok | ok (candidate asks 228% of minimum) | +25% | 30 calendar | ok | 5/5/5, quarterly | none (0), by design |
| IT | ok | ok | +25% | 20 d | ok | 22/10/4, quarterly | ok |
| DK | ok | ok | +50% | 25 d | ok | 25/25/25, quarterly | ok |
| FI | ok | ok | +50% | 25 d | ok | 25.5/13.5/10, monthly | ok |
| IE | ok | ok | +25% | 20 d | ok (notice bands) | 23/0/13.5, bimonthly | ok |
| SG | ok | ok (candidate asks 159% of minimum) | +50% | 7 d | ok | 9/9/9, quarterly | ok |

Sick pay: not modelled per country. Paid leave and sick days are one flat uplift on staff pay (`1 + leaveWeeks/52 * 0.3` in `CompanyCosts.wages`), so the only country difference is the leave days. This is a gap, not a defect found by the probe.

## Unsure items for the owner (not changed)
- Sick pay by country (statutory sick pay levels and waiting days) is not in the data or the code; sick days are absorbed in the leave uplift.
- CA: notice, severance and overtime follow the federal Canada Labour Code (2 weeks notice, 2 days a year); provincial rules (Ontario ESA: up to 8 weeks notice) are more generous. `TAX_SOURCES.md` already says unverified.
- KR: VAT filing every 6 months. General taxpayers file quarterly (with prelim returns); half-yearly is the individual simplified case. Not changed.
- BR: standard VAT 17% is a pre-reform ICMS-type simplification (2026 transition to IBS/CBS); minimum wage BRL 1,621 matches 2026.
- AE and SG: no statutory minimum wage; the data uses a market floor, so candidates ask well above it (228% and 159%). Fine for play, but the "minimum" is not a law there.
- NL: reduced VAT and food both 9% (the real food rate is 9%, reduced 9%): fine. NL employee social 0 because premiums are inside the income-tax bands.
- Employer contribution rates (SE, FR, ES, IT, FI, DK) are rounded averages; not re-derived in this pass.
- A capped contribution table exists only for MX (CALC-02, other agents' area); in the 16 countries here the flat factor is exact.
- `ManagerTeam.teamWeek` applies the on-cost to the summed team wage, not per person (exact for flat-rate countries, which is all of them but MX).
