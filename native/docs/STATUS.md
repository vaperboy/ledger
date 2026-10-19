# Status (paused)

**Done and tested (55 engine tests pass on Linux; engine tests and the SwiftUI app build passed on macOS CI at the last checked commit):**
engine, saves and legacy import, the SwiftUI app (Home, Companies, Group, Phone, Inbox, start screen), docs, CI with a screenshot job,
and the Norway clean-up: neutral ids with save migration, per-country company-name endings, listed companies and city data,
no currency exempt from drift, no fallbacks to a default country, no brand names, lint tests that keep it that way.

**Not done / missing:**
1. The screenshot CI run was never read, so **nobody has seen the app running**. Check the artifacts of the latest `native-ios.yml` run first, then fix layouts.
2. The latest Norway clean-up commit has not been seen on CI yet (run it once).
3. Balance: gym +28 %, bakery +24 %, restaurant -21 % revenue against the original, cash at week 26 lower everywhere (`BALANCE_PARITY.md`).
4. Not ported: 17 of 67 trades (project, rental, finance, energy, holding, club, salmon), key accounts, assistants, poaching, the 50 strategic
   decisions, brand catalogue and used market for equipment, managers/boards/chains/franchises, most of the original's 105 screens and 557 actions (`PARITY_CHECKLIST.md`).
5. Norway: the price baseline constants still equal the original's authoring level (they are tuning constants, not a country); a rebase to a
   world average needs a rebalance. Country-specific numbers in `Demand.swift`/`Pricing.swift` are now data. A few accounting-unit money
   constants (loan base, small thresholds) are still unscaled per country.
6. Premium upgrade brief: **partly done** (see CHANGELOG "Premium upgrade"). Done: Finance & taxes screen, company dashboard, policies,
   inbox tabs, Home "Coming up", estimate labelling. Not done: verified tax/fee data per country (everything is labelled *Estimate*),
   registration and licence cost lists per country in the UI, acquisition integration costs, competitor behaviour, economic cycles,
   personal-asset running costs, further growth-realism tuning (marketing already saturates, valuation is profit-based, capacity and hiring
   delays exist; manager effect not re-examined). The UI of this round was written without a Swift toolchain in the authoring sandbox
   and is only checked by CI; read the CI result before trusting it.
