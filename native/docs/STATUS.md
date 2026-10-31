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
   world average needs a rebalance. Country-specific numbers in `Demand.swift`/`Pricing.swift` are now data. The accounting-unit money
   constants (loan base and floor, fines, thresholds) are scaled per country (`MONEY_SCALING.md`), with a lint test against new ones.
6. Premium upgrade brief: done for the screens in the concept and every other screen (new design, Liquid Glass, policies,
   finance screen, company dashboard, inbox, net worth chart). Balance: see `BALANCE_REPORT.md` (no get-rich-quick path; capital-heavy
   trades now return 2 to 15% a year). Tax data was checked against 2025/26 law in October 2026 (`TAX_SOURCES.md`); it stays a
   simplification and is still labelled "Estimate" in the app.
7. A Swift 6.0 toolchain for Linux can be unpacked from Ubuntu's `swiftlang` package (see MAC_STEPS.md) to run the engine tests
   without a Mac; the SwiftUI app still only builds on macOS (CI).
