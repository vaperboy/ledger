# Engine reads for the new look (27 Oct 2026)

For the UI agents. Mockups: `native/design/new-look-2026-10/`. Every read is a `GameEngine` method; models are plain `Equatable, Sendable` structs. Money is in the company's or player's own currency units (format with the usual `Currency`). Nothing below changes the game except the one action marked ACTION. Tests: `NewLookEngineReadsTests`.

## Payroll alert (Bank app red bubble)
| Call | Returns | Notes |
|---|---|---|
| `payrollAlerts()` | `[PayrollAlert]` (`companyID, companyName, amount, dateText, reason, isLate`) | Owner-run payroll that is late, or due and not covered by the "Approve routine payroll" rule (which approves by itself only if the company's cash covers it). Gone once a manager or accountant runs payroll, or the owner approves. |
| `resolvePayrollAlert(companyID:)` ACTION | `PayrollAlertOutcome` (`.approved`, `.paidLate(paid:short:)`, `.notNeeded(String)`) | Calls the existing `approvePayroll` (coming pay day) or `runLatePayrollNow` (late). Same path as the Inbox message. |

## Bank app (BankAccounts, BankAccount)
| Call | Returns |
|---|---|
| `bankAccounts()` | `BankAccounts`: `rows: [BankAccountRow]` (personal, investments, then each live company: `id: BankAccountID, kind, name, detail, balance, savings?, savingsRate?, loanCount, hasAlert, alertNote`), `total`, `dueWithin30Days`, `isCovered`, `alertCount` (the Bank icon bubble) |
| `bankAccount(_ id: BankAccountID)` | `BankAccountDetail?`: `balance, available, overdraftLimit, overdraftUsed, overdraftRate, monthChange, alert: PayrollAlert?, upcoming: [Obligation]` (payroll, rent and supplier bills, invoices, tax, loan instalments; `Obligation.kind` is new), `recent: [BankTransaction]`, `savings, savingsRate, deposits: [DepositInfo]` (personal only), `loans: [BankLoan]`, `statements: [BankStatementEntry]` |
| `bankTransactions(_ id, limit:)` | `[BankTransaction]` ("View all") |
| `bankStatement(_ id, kind: ReportKind, reportID:)` | `BankStatement?` (week, month, year: opening, closing, lines, in/out); nil until a period has closed |

`BankAccountID` is `.personal`, `.investments` or `.company(Int)`. Loans are never an account: personal loans are on `.personal`, a company's on `.company(id)`. Company accounts have no savings or deposits in the engine, so those are empty there; the investments account has no overdraft, loans or bills.

## Trade picker, company set-up (PickA, CreateA)
| Call | Returns |
|---|---|
| `tradePickerRows(cityID:countryCode:)` | `[TradePickerRow]`: `name, sector` (the filter chip), `startUpCost` (exact, at the size the city carries), `demand: DemandLevel` (.high/.medium/.low from `CityMarket.demandIndex`; no margin), `staffMin, staffMax`, `blocked`, `isFunded`. Home city and country by default. |
| `startUpCostBreakdown(tradeID:cityID:legalForm:premises:)` | `StartUpCostBreakdown?`: `lines` (Registration and licences, Fit-out and equipment, Deposit and first month, plus Property purchase / Waiting for a licence only when the trade has them) adding up to `total`; `shareCapital` (extra, locked in a limited company). `premises` nil = the standard place the picker prices (same total as the row); a `NewCompanyPlan.Pick` = that rented or bought place. |
| `monthlyFixedCostEstimate(tradeID:cityID:legalForm:premises:)` | `MonthlyFixedCostEstimate?`: `lines` (Rent or Mortgage payment, Running costs, Accounting, Wages), `total`, `staffCount` |

Existing and unchanged: `newCompanyPlan`, `startCompanyChoosingPremises`, `tradeAffordability`.

## Hiring (Hiring, Negotiation)
| Call | Returns |
|---|---|
| `hiringSearchOptions()` | `[HiringSearchOption]` (Job ad, Network, Agency: `mode, fee, applicantsMin, applicantsMax, note`). `fee` is 0: searches are free today (`Hiring.searchFee`); the screen should say so, not invent a price. |
| `hiringBoard(companyID:role:personIDs:)` | `HiringBoard`: `marketMonthly` (+ `marketYearly`), `searches`, `applicants` |
| `applicant(personID:companyID:)` | `Applicant?`: `claimedSkill, claimedExperienceYears, resume, askMonthly/askYearly, marketMonthly/marketYearly, askVersusMarket` (+0.03 = "3% above market"), `seems` ("Eager", "Steady", "Proud": from age, CV and ask only), `referencesChecked`, `trialSkill` (after a paid trial week) |

Run a search with the existing `searchWorkers(companyID:role:mode:)` and pass the returned people's ids to `hiringBoard`. Skill shown is the claim; true skill, lies and character are never in these models. Talk terms and hire stay the existing negotiation calls.

Owner fixes (27 Oct 2026): tenders show "Your cost est." and "Rivals bidding" again (owner reversed the hiding): `Tender.rivals` is public again, `ProjectTenders.costEstimate(_:_:data:)` (list-price value times the trade's materials + subcontractor share, the same share `startJob` uses, no random overrun; nil for volume tenders) and `ProjectTenders.rivalScale(_:)` (None / A few / Several / Many from the real rival count) feed `ProjectBoard.TenderRow.costEstimate` and `.rivals` (a word, never a number). The Projects > Bids tender card shows Budget, Your cost est., Rivals bidding (fee and scoring stay in the bid panel). Test: `TenderInfoTests`. Patience is never a number in the UI: `PatienceWords.feeling(left:of:)` (HiringView.swift) maps the engine value to Relaxed / Getting impatient / Close to walking away (wording only). Candidate checks offer a paid trial week (`startTrialWeek`, one quarter of the market wage) instead of an interview. Add-ons show set-up cost only, no running cost. Bank > Bills: only payroll and loan rows have a button; rent, supplier bills, invoices, tax and VAT show "Leaves on its date" (`Obligation.kind`).
