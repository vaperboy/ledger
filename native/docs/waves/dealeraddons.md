# Dealer add-ons (wave note, branch dealeraddons)

Files: `Engine/Sources/Businesses/DealerAddons.swift`, `Resources/dealer_addons.json`, `Engine/Sources/Simulation/DealerAddonActions.swift` (engine reads and actions for the screen), `App/Ledger/Features/Companies/DealerAddonsView.swift`, `Tests/LedgerTests/DealerAddonsTests.swift`.

## Public API
- `DealerAddons.offers(forSale: Double, car: DealerCar, company: Company, state: GameState, data: GameData) -> [DealerAddonOffer]` (take rate, expected income and cost per sale; empty for other trades)
- `DealerAddons.apply(_ s: inout GameState, companyID: Int, sale: DealerSale, data: GameData) -> DealerAddonResult` (call when a car is sold; `saleCompleted == false` means the bank declined and the customer left: do not complete the sale)
- `DealerAddons.weekly(_ s: inout GameState, companyIndex: Int, data: GameData)` (setup reviews, warranty claims, expiries; call once a week per live car dealer)
- `DealerCar(title:ageYears:wear:)`, `DealerSale(key:price:car:)` (key = car or sale id, makes customer choices repeatable)

## To wire (lead)
1. Call `apply` from the sale code of `usedcar` and `cardealer`, and `weekly` from the weekly company loop. `result.demandBoost` is not needed; `offers(...).demandBoost` is a relative lift of the sale chance (included warranty, finance available, cheaper insurance) if the dealers want to use it.
2. Balance sheet: the warranty reserve is `payables["warr"]` (`DealerAddons.reserveKey`). `CompanyFigures.billsOwed` needs `total += p["warr"] ?? 0`, and `companyBalanceSheet` a line "Warranty reserve". Not done here (not my files). Payday only pays the keys wages, rent, other, tax, so the reserve is never paid out as a bill.
3. Embed `DealerAddonsView(engine:company:)` in the company settings/customers screen for trades usedcar and cardealer (`DealerAddons.supports(company)`).
4. SAVE_FORMAT: new company key `dap` (only written once a setup is started, an add-on is set or a sale used one): `on` {wty, loan, ins: 0/1}, `cfg` {inc, xm, xr, lc, ic}, `set` {addon: {ph: review/ok/no, from, ready, paid, why}}, `wty` [warranty records: id, car, wk, until, m, xp, lam, px, left], `pol` [policy records], `fin` [financing records], `st` totals, `n` id counter. Payable key `warr` on the company.

## Rules in numbers (all in dealer_addons.json)
- Warranty: claim events per year = 0.08 + 0.04 per year of age + 0.30 x wear; a claim costs 7 percent of the car price x 0.4..2.2. Reserve = expected claims for the months covered (expense `oth`, liability `warr`). Claims are paid in cash from the reserve (excess is an expense); leftover reserve is released at expiry. Extension take rate = logistic(-0.6 + 2.5 x age worry - 2.5 ln(price / perceived fair price)); perceived fair = max(2.5 percent, expected claims per year x 1.6).
- Loans: bank pays 1 to 3 percent of the financed amount (85 percent of the price) as commission; the customer's rate rises with the commission, so fewer choose it. Share needing finance rises with price; approval falls with price and car age; a declined customer walks away 60 percent of the time (sale lost), else pays cash. No loan record on the dealer's side (customer's loan is the bank's).
- Insurance: insurer's distribution budget is 30 percent of premium: dealer commission 10 to 20 percent, the rest is the customer's discount. Take rate = logistic(-0.6 + 16 x discount): about 0.86 at the default 15 percent, higher with a lower commission. One-time commission on the first-year premium; the policy is a record `DI-year-nnnnn`.
- Setup (fees scaled to the currency, review time = slowest requirement): warranty 2 contracts, 1 week; loans credit intermediary registration (licence) + bank partner agreement + compliance training, 6 weeks, needs reputation 40 and 8 weeks trading; insurance intermediary registration (licence) + insurer agency agreement, 4 weeks, needs reputation 35 and 4 weeks trading. A review can fail (reputation fell); fees are then lost.

## Notes
- The app view sits in `Features/Companies` (the existing folder), not `Features/Company`.
- Tests set `status = .open` directly: the opening checklist of the reworked trades is not this module's business.
