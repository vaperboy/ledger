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
Repairs, leases beyond the line above, project, rental, finance, energy, salmon, holding and club weekly models, bonuses, perks and commission postings were not read in this pass.
