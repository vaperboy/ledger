# Audit part 3: money flows and consistency

Branch worktree-agent-ad323a5ed812a3001. Tests: `Tests/LedgerTests/HeldMoneyAndFiguresTests.swift` (written, run by CI; only compiled locally).
Not re-checked (already in calculations.md / connectivity.md): ledger gaps, payday dates, VAT filing months, payroll shortfall flow.

## Fixed
| Item | Verdict | Test |
|---|---|---|
| Seven-day held-back money (`pend`) when the player winds up or sells a company mid-week | DEFECT, fixed: the unreleased share stayed in `pend` and landed later in a dead company, and the wind-up estate missed it. New `Finance/HeldMoney.swift` (`remaining`, `settle`); called at the start of `windUpCompany` and `CompanySale.complete` (every sale path: offers, group deals, rival bids, strategic sales, shareholders) | `testWindUpMidWeekSettlesHeldMoneyAndLeavesNoStrayCash`, `testRemainingAndSettleAreConsistent` |
| Bankruptcy and forced sale vs held money | SAFE: both run inside the weekly turn before the week is staged (`pend` is null); the failed company's staged delta self-cancels (cash restored then drained over the seven days). Nothing to settle | covered by existing ledger-gap tests |
| Closing a company for some weeks mid-week | SAFE: company stays live, the release continues | `testClosingMidWeekKeepsTheCompanyAndItsHeldMoney` |
| Company balance sheet debt lines did not add up to total debts: supplier invoices (`payables["inv"]`) were in the total but had no line | DEFECT, fixed: line "Supplier invoices" | `testCompanyFiguresAgreeAcrossScreens` |
| Debts listed three times (`CompanyFigures.debts`, wind-up `billsOf`, bankruptcy) and the last two left out financial-company liabilities (`fm.liab`) | DEFECT, fixed: one `CompanyFigures.billsOwed` used by all | same test |

## Same figure, one source
| Figure | Where computed | Verdict |
|---|---|---|
| Net worth | `Valuation.netWorth` only (Home, Group, Reports, history snapshots, goals) | one source; parts test |
| Cash | `Company.cash` / `GameState.cash`; balance sheet and net worth read them directly. Note: during a week the held-back remainder is in neither (by design, it lands over seven days) | agree |
| Company value | `Valuation.companyValue` (Insights, Reports, Net worth, Failure, sale) | one source |
| Profit and revenue, 12 months | `Insights.companyHealth` and `HoldingModel` both sum `monthlyHistory.suffix(12)`; `yearlyProfitEstimate` annualises the same history; the Finance screen shows year-to-date books (a different, labelled period) | agree for the rolling figure |
| Payroll per month | five formulas on the same base (wage x 12 / 52 x employer factor): `Payday.weeklyWageCost`, `weeklyCostEstimate`, `EventEngine.context`, TeamOverview (gross), accrual in `CompanyCosts.wages` (adds leave uplift and commission) | CALC-06 stays: estimates omit the leave uplift. Not changed (owner decision on one weekly-wage function) |
| VAT owed, tax owed | `vatBalance` and `payables["tax"]`, read by balance sheet, Finance screen, wind-up, bankruptcy | agree; test |
| Debt, loan balance | `CompanyFigures.debts`, `Banking.totalDebt`, net worth `debt` (personal loans only) | agree; test |
| Weekly cost | `FinanceContext.weeklyCost` used by Insights, Failure, Payments, Marketing | one source; test |
| Cash runway | Insights `weeksOfCash` (cash / weekly cost) and `runwayWeeks` (cash / recent monthly loss); Startups has its own `burn` formula | two meanings, both labelled; not unified |

## Read for money flows (no defect found)
Intercompany VAT (`IntercompanySupply.transferVat`: supplier owes, buyer reclaims or books cost if exempt; covered by `IntercompanyTaxTests`), supplier invoices and late interest (`SupplyTerms.weekly`: payable, receivable, interest and cut-off consistent), insurance premium accrual (`CompanyWeek`).

## Unsure, for the owner (not changed)
1. Leased vehicle payments (`CompanyWeek`, category "oth") carry no VAT, while overhead carries half-VAT. Intended?
2. Insurance premiums carry no VAT (usual for insurance in many countries, wrong in some).
3. `financeOverview` leaves holding companies out of cash and taxes; net worth counts them (through the holding's value). Intended?
4. A closed or sold company's seven-day remainder is now settled into cash before liquidation; a sale price is fixed by the offer, so the buyer's gain or loss of that remainder is not priced.

## Not audited
Repairs, leases beyond the line above, project, rental, finance, energy, salmon, holding and club weekly models, bonuses, perks and commission postings were not read in this pass (see part 3b below).

---

# Part 3b: repairs, leases, vehicles, special models, bonuses, perks, commission

Branch worktree-agent-a2e144f76b512b20b. Test: `Tests/LedgerTests/SpecialModelMoneyTests.swift` (one seeded game per model: construction, developer, rental, bank, insurer, fund, power, salmon, football club, holding with a cafe; 52 weeks, `Ledger.gaps` empty, the 26 weekly reports add up to the books of the group and of each company). Passed locally. Reports are differences of the books, so "report = books" holds wherever a posting uses a books category; the check is that no money is lost between them.

| Item | Verdict |
|---|---|
| Repairs and breakdowns (`EquipmentUnits`, `SupplyTerms.payRepairs`) | SAFE: cash and books `oth` through `Payments`, or booked at once with an invoice on repair terms; gaps empty. No VAT on repairs (unsure 1) |
| Vehicle leases, fuel, motor insurance, vehicle tax (`VehicleRunning`, `CompanyWeek`) | SAFE: one path; fuel in cost of sales for fuel trades, own line otherwise (no double count); lease payments `oth`, no upkeep on leased vehicles. The mileage double count from the stage-2 audit is gone (only `PersonalEquipment` books it) |
| Manager target bonuses (monthly, year-end) were paid straight from cash with no employer charges, while profit bonus, worker bonuses and commission carry `employerCostFactor` | DEFECT, fixed: added to `bnPend` and paid through payroll (`CompanyCosts.wages`): same charges, same payable, same books line. Paid on payday instead of the day it is judged |
| Holding company interest on its own cash: trade data had VAT "std" and 20% business share, so interest was charged VAT (cash created, VAT owed) and 20% of it was invoiced with a 1.2% chance of default | DEFECT, fixed in `trades.json` (`hold`: vat "zero", b2b 0, as the bank and insurer already are). Test `testHoldingYearAndNoVATOnItsOwnInterest` |
| Project (milestones, receivables, bad debts) | SAFE: `payJob` cash = amount x (1+VAT) x cash share, the rest is a receivable in `book` (default chance, VAT reclaimed on write-off). Retention is not modelled, only milestones 30/40/30 |
| Rental (rent, vacancy, mortgage, valuation) | SAFE for cash and gaps: mortgage cash in/out through `Ledger`, interest in `int`; revaluation goes to `reval`, not the books; a sale books the gain over current value as `rev` or `loss` |
| Finance (premiums, claims, deposits, loan book, fees) | SAFE: new loans and deposits move cash without P&L; loan losses `loss` with the book reduced; performance fee `rev`; storm claims `loss` |
| Energy (build, revenue, hedge, depletion) | SAFE: capex through `Payments` with no category, depletion booked `dep`, discovery sale `rev` |
| Salmon cohorts and harvest | SAFE for cash and gaps. Smolt expensed as `cogs` when stocked, revenue only at harvest, so profit is lumpy (unsure 4) |
| Holding dividends up and down, tax group | SAFE in the test year (gaps empty, reports agree); dividends via `Payments.payDividend` |
| Football (wages, transfers, prize money) | SAFE for cash and gaps. Signing fees are capex amortised in `dep`; prize money and transfer income are `rev` |
| Staff perks | SAFE for posting: `wages`, weekly, once (employer charges: unsure 5) |
| Commission | SAFE: accrued in `CompanyCosts.wages` with `employerCostFactor`, in `wages` once |
| Worker bonus plans | SAFE: `bnPend` through payroll |
| Own companies as suppliers, cars, perks, commission (stage-2 batches) | Partly landed: `VehicleRunning` (2B/2E), `PayPlans`, `WorkerBonus` (3C, 4B), `StaffPerks` with role groups (3A). Not re-audited line by line |

## Unsure, for the owner (not changed)
1. Repairs, own-line fuel, leases and premises upkeep carry no VAT, while overhead carries half-VAT (same question as item 1 above).
2. Rental: property tax is part of the cost of sales, so the input-VAT reclaim in `CompanyWeek.book` is also applied to it (property tax has no VAT). Small; only for a VAT-registered rental company in a standard category (parking).
3. Football: players' and coaches' wages are in cost of sales (`cogs`), so a club's wages line in reports is zero. A sold player's remaining book value is not written off.
4. Salmon: smolt cost is expensed at stocking instead of held as stock until harvest.
5. Perks bypass employer charges (benefits in kind); depends on country rules.
6. Retention on project payments is not modelled (design question, not a posting defect).
