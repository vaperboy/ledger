# Audit: calculations and money flows (AREA=calculations)

Branch audit/calculations from origin/native-swiftui. Read-only on game code. Original JS source (from `ledger-v1.0.0.zip`, `Ledger/source/src/js`) used as evidence only.

**Status: PARTIAL.** The audit was interrupted by a rate limit and finished in a short pass. Only the areas under "Coverage" were read or probed. Everything under "Not checked" has NOT been audited. Do not read the absence of a finding there as a pass.

## Scope and method
- Read: `Finance/Ledger`, `Payments`, `Annuity`, `CompanyFigures`, `FinanceContext`; `Simulation/Payday`, `MonthEnd`, `GameEngine` (day/week order, staging and release of weekly money); `Businesses/CompanyWeek`, `CompanyCosts`, `Vat`; `Countries/Country`, `Taxes`; `Employees/Labour`, `Wages`; `GameCalendar`; `docs/MONEY_SCALING.md`, `KNOWN_GAPS.md`.
- Probes (throwaway tests in a scratch package outside the repo, not committed): a limited-company cafe bought in UK, US, MX, PL, DE, JP, NO with 5,000,000 units, played 26 weeks day by day with payroll approved. Checked `Ledger.gaps`, the company equity identity, employer-cost factors, labour rules and personal tax at median and 5x median wage.
- Country data (23 countries) dumped and scanned for tax, VAT and employer-contribution structure.

## Coverage checklist
| Item | Result |
|---|---|
| Direct cash mutation outside Ledger (grep for `.cash +=`, `-=`, `=`) | Fine: only `Ledger` writes cash. Other hits are probe copies (`probe.cash += Int32.max`) and company setup `co.cash = 0` before any money exists |
| `Ledger.gaps` after 26 weeks, 7 countries | Empty in every country |
| Company equity identity (equity change = injected capital + share capital + profit) | Holds within about 2k units in all 7 countries, once share capital is counted (see note below) |
| Payday dates, weekend shift, 0-based month use (`lastDay`, `payDate`, `nextPay`, `billDate`, `monthNumber`) | Fine. Every call passes `civil().month - 1`; December rolls to the next year correctly |
| VAT filing months (`monthIndex % freq == freq-1`) for freq 1, 2, 3, 6, 12 | Fine: Dec/Mar/Jun/Sep, Feb/Apr/..., Jun/Dec and Dec filing months come out right |
| Month end and year end order (`advanceWeek`) | Runs on the Monday of the last week of the month, after that week's books. Consistent with the staged-week design |
| Corporate tax accrual, loss carry-forward, settlement 26 weeks after year end | Read; logic consistent. Not numerically probed (the cafe made losses, tax 0) |
| Personal income tax, wage kind: median and 5x median, all 7 probe countries; negative income | Plausible: UK 22.6% / 44.8%, US 16.3% / 31.3%, MX 14.9% / 26.6%, PL 31.6% / 49.5%, DE 44.3% / 58.7%, JP 37.7% / 56.1%, NO 25.1% / 42.3%; negative income gives 0 |
| Labour rules at 5 years' service, redundancy | UK 5 wk notice + 5 wk severance, US 0/0, MX 0 + 35.9 wk, PL 13 + 4.3, DE 8.7 + 0, JP 4.3 + 0, NO 6.8 + 0. Match the data |
| Overtime premium by country | UK 0, US 0.5, MX 1.0, PL 0.5, DE 0.25, JP 0.25, NO 0.4 |
| Money literals scaled | Not re-audited. `MoneyLiteralLintTests` exists |
| Late bills, arrears, supplier cut-off levels | Read in `payBills`; consequences exist (late interest, reputation, supplier cut at 2 and 3 missed months, bankrupt at 4) |
| Late wages | Read in `lateDay` (mood, quits from day 3, reputation at day 7, wage claim at day 14) |
| Overdraft interest and room | Read (F-3) |

Note on share capital: a limited company's share capital is paid personally by the player and sits in company cash. It was 290,761 units in DE, 30,000 in NO and 14 in UK. This is why a naive "equity = injected" check looks wrong in DE, and why the equity identity is correct.

## Findings (sorted by severity)

| ID | Sev | Status | Summary |
|---|---|---|---|
| CALC-01 | S3 | VERIFIED | Employer on-cost differs between payroll and dismissal/notice quotes |
| CALC-02 | S3 | VERIFIED | Capped employer contributions (Mexico IMSS table) are not applied to actual payroll |
| CALC-03 | S3 | VERIFIED (parity) | Company overdraft interest is a flat 14%, in every country |
| CALC-04 | S3 | INFERENCE | VAT on overhead leaves cash at once while the overhead itself waits for the monthly bill |
| CALC-05 | S3 | INFERENCE | Unpaid VAT penalty of 5% is re-applied to the whole arrears at each filing |
| CALC-06 | S4 | VERIFIED | Payroll estimates ignore the paid-leave uplift that accrual includes |
| CALC-07 | S3 | INFERENCE | Week-to-day staging can drop money if a company or the player disappears mid-week |
| CALC-08 | S3 | OWNER DECISION | Stock "inventory" is a cash float, not consumption |

### CALC-01 (S3, VERIFIED) Employer on-cost differs between payroll and dismissal quotes
Payroll accrual uses `country.employerCostFactor` = 1 + social + pension + injury (`CompanyCosts.swift:55`). Notice paid in lieu uses `employerSocialRate(monthlyWage:)` alone (`Dismissal.swift:68`, `WorldLabour.swift:21`, `Labour.swift` `Termination.payments`). `employerSocialRate` leaves out pension and injury (`Country.swift`).
Numbers from the probe: UK payroll factor 1.18, notice factor 1.15; US 1.13 against 1.09; DE 1.2215 against 1.2115; PL 1.2217 against 1.205; NO 1.166 against 1.141.
Effect: notice and similar quotes understate the employer cost by 2 to 5 points of pay in countries with pension/injury components, and `ContractTalk` and `VehicleRunning` mix the two.
Fix: one function `employerOnCost(monthlyWage:)` = `employerSocialRate(monthlyWage) + employerPension + employerInjury`, used by payroll, dismissal, `ContractTalk` and `VehicleRunning` (which already adds pension/injury itself).

### CALC-02 (S3, VERIFIED) Capped contributions not applied to payroll
For countries with a contribution table (Mexico), `employerSocial` is set to the table evaluated at the median wage (`Country.swift`, end of `init`). Actual payroll multiplies every wage by that fixed factor. At the median it is correct (MX 0.1953). At 10x median the table gives 0.102, at 0.3x it gives 0.1953, but payroll charges 0.1953 for everyone. High earners cost more than the law says and the per-wage rate used in `ContractTalk` and Dismissal disagrees with the books.
Fix: in `CompanyCosts.wages` and `weeklyWageCost` use the per-employee on-cost from the CALC-01 function.

### CALC-03 (S3, VERIFIED parity) Flat 14% overdraft interest
`CompanyWeek.weekEnd`: `interest = -cash * 0.14 / 52`. Same as the original (`engine/company/model.js:461`). It ignores the country's policy rate and loan margin: JP (very low rates) and BR (high rates) pay the same, while term loans use `policyRate + margin`.
OWNER DECISION: keep parity, or use policy rate + a margin so it is country-neutral (MONEY_SCALING and the country-neutrality tests lean that way).

### CALC-04 (S3, INFERENCE) Input VAT on overhead is paid immediately
In `weekEnd`, `Payments.companyPays(fixed, category "oth")` is deferred into the monthly bill in day mode, but the half-VAT on overhead is moved out of cash at once with `Ledger.moveRaw` and credited to `vatBalance`. Cash leaves earlier than the net cost, and the amount is unrounded in `vatBalance` and rounded in cash (sub-unit drift). Fix: add the VAT to the same payable.

### CALC-05 (S3, INFERENCE) VAT penalty compounding
`MonthEnd.closeMonth`: at each filing, when VAT could not be paid, 5% of the whole unpaid amount (which already contains the previous penalty and 1% monthly interest) is added again. Check against the original `vatOver` rule before changing.

### CALC-06 (S4, VERIFIED) Payroll estimates omit the leave uplift
`CompanyCosts.wages` multiplies staff pay by `1 + leaveWeeks/52*0.3`. `Payday.weeklyWageCost`, the approval reminder estimate, `PayrollReads` and `FinanceReport` do not. The "about X" in the approval message is a little low. Fix: use one weekly-wage function.

### CALC-07 (S3, INFERENCE) Staged weekly money has no owner if the company disappears
`stageWeek` removes each company's weekly cash change from the company and `releaseDay` adds it back in seven slices only `if state.companyIndex(id) != nil`. If a company is sold, closed or goes bust in those seven days, its remaining staged amount is never returned. `Ledger.gaps` would not notice, because the removal was booked to the ledger flow. Not reproduced, so INFERENCE. Fix: on sale or bankruptcy, release the remaining staged amount first.

### CALC-08 (S3, OWNER DECISION) Inventory purchases are not consumption
`stockHandle` moves cash for `step` of stock and gives it back when stock falls (negative `step`), while cost of goods is booked and paid separately as a payable. Stock is a pre-payment float that earns its cost back, not a cost. Same as the original, but it means stock-heavy trades tie up cash and then release it. Question: intended?

## OWNER DECISION list
1. CALC-03: keep the original flat 14% overdraft interest, or tie it to the country's policy rate?
2. CALC-08: is the inventory float (cash out for stock, cash back when stock shrinks, cost paid separately) intended?
3. CALC-01/02: confirm that notice in lieu should carry the full employer on-cost (social, pension, injury), as payroll does.

## Verified fine
- Cash is changed only through `Ledger`; `Ledger.gaps` empty after 26 weeks in UK, US, MX, PL, DE, JP, NO.
- Company equity matches injected capital plus share capital plus profit within 2k units in 7 countries.
- Payday and bill-date calendar arithmetic, including weekend shift, December rollover and 0-based month handling (the fixed Payday bug has no siblings in the files read).
- VAT filing months for 1, 2, 3, 6 and 12 month filers.
- VAT collected on sales, VAT-free exempt companies, sales-tax countries (US) charging consumers only, VAT correction on defaulted invoices.
- Payroll shortfall flow: pays up to cash plus overdraft room, back pay, owner salary withheld until staff are paid.
- Loss carry-forward and tax settlement logic by reading.
- Labour termination formulas match the data in the probe countries.

## Not checked (open)
Loans, early repayment, amortisation, consumer and mortgage offers (`Banking`, `Annuity` read only for the formula); personal finance and personal tax assessment, wealth, inheritance, advance tax; dividend tax and shield numbers; intercompany VAT and `IntercompanySupply` money; leases, mortgages and rent beyond what is listed; supplier terms and invoices (`SupplyTerms`); insurance claims and breakdown/repair costs; bank, insurer, rental, energy, salmon, football and holding models; investments, funds, crypto; inflation index application and exchange-rate display rounding; Dismissal.quote against payroll; minimum-wage enforcement at hiring; overtime pay in `DailyTrade`; report numbers (P&L, balance sheet, cash flow) and consistency across Home, Company, Team, Group, Reports and Money; save/load round trip equality and same-seed determinism (KNOWN_GAPS says two runs agree to about 1e-9, not bit for bit); very large numbers; corporate tax with a profitable company (the probe cafe lost money in all 7 countries); US/CA-style differences beyond sales tax.

## Open data gaps
- No statutory minimum wage and overtime law for some countries (KNOWN_GAPS lists this; the Labour data covers the probe countries).
- Tax rates in the data were not compared with real-world 2026 figures here (`TAX_SOURCES.md` covers sources).
