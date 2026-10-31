# Money constants and countries

All amounts in the engine are in the **accounting unit** (about NOK 1 at the reference economy). A country's currency is shown
by dividing by its exchange rate, but a *fixed number of units* means very different things in different countries: 25 000 units
is a few days of rent in Norway, and a fortnight's wages in Mexico. The rule is therefore:

> Any amount a player meets (a limit, a fee, a fine, a threshold) is either **read from the country's data file**, or written at the
> reference economy and **scaled** when it is used.

Two scales exist, and which one applies depends on what the amount is:

| The amount is ... | Scale it with | Example |
|---|---|---|
| a price, fee, fine or deposit (what things cost) | `Currency.scaledPrice(x)` = x times the country's cost index (0.5 + 0.5 x price level), rounded tidily in local money | overdraft limit, minimum loan, fines, group-size threshold, inspection fines floor |
| income-like (what people earn, what a bank assumes you earn) | `Country.medianMonthlyWage` (= reference median wage 56 000 x the country's wage level) or `wageLevel` | consumer loan base, the bank's assumed minimum income |
| the design of a trade (tickets, fixed costs, equipment) | nothing: written at the reference economy and scaled by the price level, wages and rents of the country when a company is set up | `trades.json` |
| a ratio or a technical number | nothing | annuity factor per 100 000, rounding steps, random seeds |

## Changes in this pass

| Where | Before | Now |
|---|---|---|
| `Banking.offer`, consumer loan base | `80000 x wageLevel` | `1.43 months x medianMonthlyWage` (identical numbers, now derived from the median wage) |
| `Banking.offer`, income a bank assumes | `380000 x wageLevel` (the original's undefined `wage0` made it a constant; in the code it had already been made country-dependent, but KNOWN_GAPS still called it unscaled) | `6.8 months x medianMonthlyWage`, same numbers, explicit constant (`Banking.assumedIncomeMonths`) and a test |
| group-size threshold (`group.big`), new games | 5 000 000 for everybody | `scaledPrice(5 000 000)` |
| inspection / audit / food-safety fine floors (`SpecialEvents`) | 6 000, 8 000, 12 000 | `scaledPrice(...)` |
| paperwork and mis-selling fines (`StaffExtras`, booked in `StaffRoutine.applyExtras`) | 6 000 to 40 000 | scaled by the price level |
| unpaid-bills thresholds (`Payday`, `MonthEnd`) | 1 500 | `scaledPrice(1500)` |
| game over for "broke" (`Failure`) | net worth below 10 000 | `scaledPrice(10 000)` |
| event context fallbacks (typical weekly revenue 1 000 / 3 000, equipment 50 000) | fixed | times the country's cost index |
| insurance premium base floors (`CompanyCosts`) | 100 000 / 120 000 | `scaledPrice(...)` |
| fallback manager wage in the capacity model | 50 000 | times the wage level |
| revenue-growth insight guard (`Insights`) | revenue above 1 000 | `scaledPrice(1000)` |

Already scaled before this pass: overdraft limit, minimum loan, abroad fees, authority limits of a new company, deposits and
fit-out, complaint refunds, event cash amounts (`EventEffects.scaled`), late-payment fines, accountant and manager fees in
`Payday`, tax rules, start-up loan (data).

Deliberately **not** scaled (design constants, see `MoneyLiteralLintTests.allowed` for each with its reason): the reference
economy's own numbers, crypto prices (a global asset priced in units), rounding steps, calibration constants of the trades,
role wages compared with the role table, demo data.

The start-up loan is data per country (`start.loan`). It follows the **price level**, not the wage level: it buys about the same
business everywhere (130 000 to 200 000 units per unit of cost index), because the cost of a company follows the price level.
This makes it 6 to 12 months of the median wage in Brazil and Mexico, where wages are low against prices; that is how the data
is built (wage index 20 against a cost index of 62 in Mexico), not an unscaled constant.

## Guarding it

* `MoneyScalingTests.testLimitsAreSensibleMultiplesOfTheLocalWageInEveryCountry` plays a new game in each of the 23 countries and
  checks the start-up loan (per cost index), the consumer-loan offer (0.3 to 8 median wages), the overdraft limit (0.2 to 6) and
  the group threshold.
* `MoneyScalingTests.testLoanIncomeFloorFollowsTheMedianWage`: the bank's floor equals 380 000 x wage level in every country, and a
  new Polish and a new Swiss player get comparable offers in months of wages.
* `MoneyLiteralLintTests` reads the engine's sources and fails on any number of 1 000 or more that is not inside a scaling call and
  not on the allow-list with a reason. Add a new fixed amount the right way (`scaledPrice`) or justify it in the list.
* The SwiftUI app has no money constants (layout numbers only); amounts come from the engine and are formatted with `Currency`.
