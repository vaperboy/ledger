# Wave: brokers (travel, insbroker, finbroker)

Three new middle-man trades earning commission: `travel` (travel agency), `insbroker` (insurance broker), `finbroker` (mortgage and loan broker). Engine: `Engine/Sources/Businesses/Brokers.swift`, data `Resources/brokers.json`, tests `BrokersTests.swift`.

## For the lead to merge into shared docs
- DECISIONS.md: brokers earn commission paid by the supplier after the event; no stock. Commission terms are data (`brokers.json`): travel packages 8-12 percent, flights and hotels 5-9; insurance first year 10-20, renewal 5-10; finance procuration 0.5-1.0 percent of the loan plus lender and client fees, trail 0.1-0.25 percent a year on the balance.
- SAVE_FORMAT.md: new company key `brk` = { deals: [{i,l,d,x,v,c,f,s,k,t,w}], cohorts: [{l,w,n,P,F,R,ix}], st: {counters} }. A save without it starts empty. No other saved shape changed.
- HANDS_ON_TEST_PLAN.md: start each trade; check opening list (licence, bond or indemnity, CRM, booking or comparison system); place business for a few weeks; travel: commission arrives after the trip date, cancelled bookings pay only a small handling fee; insurance: first-year commission at sale, renewals each 52 weeks, clawback on first-year cancels; finance: declines rise with the policy rate, trail every 13 weeks, clawback on early repayment.

## What is in
- Trades in `trades.json` (family svc, menu order after `estate`), roles `tcons`, `insadv`, `mortadv` (all in SALES_ROLES, so commission only / base plus commission pay plans work), documents `travel_licence`, `travel_bond`, `insurance_intermediary`, `credit_intermediary`, `professional_indemnity` (tables.json DOCS), EQ_KINDS, courses, sales ways, market classes (travel, finbroker), item catalogue titles (travel, insbroker, finbroker), `trade_tuning.json` demandLevel for the three.
- Hook: `CompanyWeek.openWeek` calls `Brokers.week` (7 lines, next to the used car dealer hook), which returns the usual `WeekContext` for `book` and `weekEnd`.
- Money: commissions from generic suppliers go through `book` as revenue on the trade's terms (b2b 0.9 to 0.95, 4 weeks), so they are receivables like any invoice. Clawbacks are paid with `Payments.companyPays` (category cogs). Flights and hotels placed with the player's own `airline` or `hotel` company in the same country: that company pays the commission with `Payments.companyPays` and the agency receives it with `Payments.companyReceives` (same amount, a real transfer). `Ledger.gaps` is empty in every test.
- Demand hooks: finbroker demand follows the policy rate (exp(-14 x (rate - 4 percent))), declines rise with the rate and fall with service quality; travel cancellations rise when the economy is weak; travel sells on the `newyear` season (early booking), finbroker on `spring`.
- Country availability: nothing special coded. Documents use each country's authority and `documents.notNeeded` / fees; a country can ban a trade through `banned`.
- Unlocks: none needed (no new feature gates).
- `Brokers.summary(co, week:)` gives the book at a glance for the UI: policies or loans in force, book value, recurring commission a year, pending commission, customer money held (travel), placed, cancelled, declined, earned, clawed back.

## Two-year probe (UK, owner set-up plus a hired manager, seeds 11 to 13; year 2 profit)
- travel: +0.25M, +0.79M, +0.60M (revenue 2.8M to 4.1M). Year 1 loses 0.9M to 1.3M (commission arrives after the trip).
- insbroker: +0.30M, +0.05M, +0.19M (revenue 2.4M to 4.1M). Book of 2,900 to 4,300 policies, renewals about 1.4M to 2.3M a year, so year 3 is clearly profitable.
- finbroker: +1.35M, +0.33M, -0.04M (revenue 1.7M to 4.9M), lumpy because a mortgage pays 25k.
No clamps on results.

## Limits and follow-ups
- Customer deposits and balances are not separate cash flows: the agency passes them on, and only the commission is booked. The deposit and balance stage shows as `customerMoneyHeld` (what the bond protects). If a real trust account is wanted, it is a liability on the company.
- The own airline or hotel is not given extra demand from the booking.
- Item records (real products) are another agent's foundation: the catalogue entries are titles only.
- `staff_expenses.json` and `staff_perks.json` role lists do not include `tcons`, `insadv`, `mortadv` yet (shared files, add-only if wanted).
- TradeCatalogTests counts changed to `>=` (72 trades, 69 on the menu).
