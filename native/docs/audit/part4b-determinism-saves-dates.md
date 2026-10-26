# Audit part 4b: determinism, saves, dated events

Tests: `native/Engine/Tests/LedgerTests/DeterminismSavesDatesTests.swift` (CI runs them; `LEDGER_DATES_WEEKS=26` shortens the dates run).

| # | Area | Finding | Status |
|---|---|---|---|
| 1 | Determinism | Float sums and loops over stored dictionaries (Swift dictionary order differs between two dictionaries with the same content) were not order-stable. Now in key order: worker bonus mean (`WorkerBonus`), equipment wear and upkeep loop (`CompanyCosts`), equipment book value and weekly cost estimate (`CompanyFigures`), campaign spend (`Marketing` x2, `Franchising`), net worth of stocks, crypto and funds (`Valuation`), team head wages (`ManagerTeam`), football sponsors, equipment health (`EquipmentMarket`), campaign end notes (`Marketing`), rival groups list (`RivalGroups.all`), chain knob changes (`Chains`), group management wage payments (`ManagerTeam`). | Fixed |
| 2 | Determinism | Two rich games (chain, franchisor, franchise unit, luxury, equipment, loan, deposit, startup) with the same seed and actions are equal as whole states every week for 40 weeks, exactly. | Test passes |
| 3 | Saves | A rich game saved and loaded equals the live game, and both play 30 more weeks identically (compared every week). Saving again changes nothing. | Test passes |
| 4 | Old saves | The four golden saves (original game, before reports, rivals, reviews, chains, luxury, equipment, decisions queue) load, play a year, books do not gain gaps, reports start by themselves, and the result saves and loads. Envelope migration 1 to 2 is stepwise; a newer file is refused. Weekly reports are capped at 26 kept. | Test passes |
| 5 | Dates | 3 years, 3 companies, Brazil (VAT monthly) and UK (VAT quarterly): 36 payrolls per company on the 25th (Friday before on a weekend), plus one "Payday" message on exactly those days; 36 bill runs on the last day of each month; 36 month closes in the right weeks; VAT only in filing months and once each (106 of 108 monthly filings for companies with VAT, 12 quarterly); 2 loans x 36 instalments, one per month close, the 36 month loan gone after 36; 3 year ends with the personal tax assessment and company tax falling due 26 weeks later and paid at the first month close from then; deposit pays out in its end week; fixed-term worker asked before and leaves in the end week. | Test passes, no defect found |

## Not covered (no date mechanism found, or needs a larger set-up)

| Item | Note |
|---|---|
| Insurance renewal | Premiums are charged weekly; there is no yearly renewal date in the engine. Nothing to test. |
| Key account expiry | Key accounts have no end date in `KeyAccounts`; they end by behaviour (late payment, lost), not by date. |
| Supplier terms expiry | Supplier invoices have due dates (`sinv`, covered by `SupplierTermsTests`); negotiated prices have a cool-off, no yearly renewal. |
| Tenant lease expiry (`RentalModel.expireLeases`) and franchise unit term end (`Franchising`, `end`) | Week-based (`week >= until` / `end`); read, not played here. Both need an owned property or a franchisor with units. Suggest a follow-up test. |
| Staff contract expiry other than fixed term | None found. |

## Notes for the owner (not changed)

* A month is closed at the start of the week that contains its last Monday-to-Sunday days (`advanceWeek` increments the week first, then `isMonthEnd(week)`), so a month's books close up to six days before the month's last day. This is how the original worked; bills and payroll use real dates.
* The week-count rounding in `Banking.collectMonthlyInstalments` (`weeks / 4.33`) gives 36 instalments for a 36 month loan in the tested run; other start weeks were not tried.
* In the UK run only the cafe ever had a VAT balance (barber and bakery stayed at 0, probably zero-rated or under the threshold); in the Brazil run all three had one. Not checked whether that is intended.
