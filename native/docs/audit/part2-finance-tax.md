# Audit part 2: finance and tax

Merged (DONE). Method: read the code path and the 23-country data, then add short tests that CI runs (not run in full locally).
Not re-checked: everything already listed as verified in `calculations.md`.

| Item | Verdict | Test |
|---|---|---|
| Corporate tax, profitable limited company, 23 countries: accrual = rate x (profit - loss carried), loss used up, payable booked, taxDue set, paid exactly on the due week (26 weeks after year end), not before, ledger gaps empty | Passes in all 23 countries (run locally) | `CorporateTaxProfitableTests` |
| Loan offer, rate, annuity, monthly re-working, finishing on time | Fine by reading; amortises to zero in term | `PersonalFinanceAuditTests.testConsumerLoan...` |
| Early repayment (partial, full, over-large amount) | Fine; cash and balance move by the amount, loan removed | same |
| Mortgage offer (1.6 x net worth, 40% income room) | Plausible, no defect found; no property link checked | none |
| Savings interest (policy - 1.2%, floor 0.5%), fixed deposits (simple interest, rate rises with term), overdraft interest (policy + country margin, +2 points personal) | Fine by reading; interest on savings and deposits is added to the taxable base | none |
| Credit score and band margins | Fine by reading | none |
| Personal income tax, wealth tax, dividend tax with shield, gains and interest tax at year end | Matches country data in all 23 countries | `testYearEndPersonalTaxMatchesCountryRulesInAll23Countries` |
| Stocks, funds, crypto: buy/sell fees, spread, gains base, loss reduces gains | Fine; round trip on crypto loses about 2.4% | `testStockAndCryptoFeesAndGainsTaxBase` |
| Inflation index | Behaviour noted (see U1) | none |
| FX: rates in accounting units, drift clamped 0.8 to 1.25, euro countries move together, home currency fixed | Fine by reading | none |
| Currency formatting of very large numbers | Defect, fixed (D1) | none (one-line guard) |

## Defects fixed
- D2: `Brokerage.buy` left the buy fee out of the cost base, so a crypto round trip under-stated its loss for tax by 0.4% of the amount. Cost now includes the fee.
- D1: `Currency.grouped` crashed (Int64 overflow) for amounts above about 9.2e18. Now capped.

## Unsure items for the owner (not changed)
- U1: `inflationIndex` = (1 + current inflation)^(weeks/52). When inflation changes, the whole price level (wages, rent, costs) jumps retroactively instead of the index growing from its past path (for example 2.5% to 5% after 20 years raises the index by about 60% at once). Same as the original; a stored cumulative index would be the fix, but it touches every consumer.
- U2: Capital gains and savings interest are taxed at the dividend rate in every country. Real life differs (UK CGT 24% vs dividends up to 35.75%; Switzerland has no private capital gains tax but the data gives 20%; Australia has a 50% discount; Netherlands taxes assumed return).
- U3: Corporate tax is settled 26 weeks after year end everywhere. Real deadlines differ by country (for example UK 9 months and 1 day, US 3.5 months, Germany by quarterly prepayments).
- U4: Loss carry-forward is unlimited in time and amount. Real rules cap it (Germany 1M + 60% above, France 1M + 50%, US 80% of income, Japan 10 years, Mexico 10 years).
- U5: Canada corporate rate 12.2% looks like the small-business rate, not the general rate (about 26.5%).
- U6: Broker minimum fee (29) and minimum purchase (100) are fixed accounting units, not scaled by price level (trivial in every country).
- U7: Tax rates in the data were not re-compared with 2026 sources here. Corporate rates looked right on a quick pass (NO 22, SE 20.6, PL 19, LT 17, DE 30, UK 25, FR 25, ES 25, NL 25.8, US 26, JP 30, BR 34, IE 12.5, SG 17, AE 9).
- U8: The buy fee is not added to the cost base of a position, so the gain is slightly overstated for tax.
