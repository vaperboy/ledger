# Known gaps, unverified behaviour, and what needs a Mac

Honest list. Nothing here is hidden behind a "done".

## Not verified by running it

* **The SwiftUI app (`native/App`) has never been run on a device or simulator by the author** (this work was done in a Linux
  container without Xcode). It is checked in two ways only: every file is syntax-checked with `swiftc -parse`, and the GitHub
  workflow `.github/workflows/native-ios.yml` builds it with Xcode on macOS. See the workflow's last run for whether it compiles.
  Layout, spacing, animations, haptics and iPad behaviour are **unseen**.
* The Swift engine (`native/Engine`) *is* built and tested on Linux and on macOS (the workflow's `engine-tests` job).
* No App Store / TestFlight build, signing, icons (the app icon slot is empty) or screenshots yet.

## Not ported (the native game is a subset of the original)

The original is 48,000 lines of JavaScript with 105 screens, 557 actions and 179 extension pipelines. See
`PARITY_CHECKLIST.md` for every item. In short:

* **Trades:** 50 of 67 can be started. Not started yet: project businesses (6), rental (3), finance (3), energy (2), the holding
  company, football clubs, and the salmon farm. The menu says "Coming in a later update". A legacy save that contains them
  keeps their data untouched, they just do not run.
* **Groups and ownership:** managers beyond the basic model, boards and votes, chains, franchises, branches, intercompany supply,
  holding companies, startups, private equity, luxury and estates (their values still count in net worth when imported).
* **People:** poaching, promotions, assistant managers (pay talks and paperwork are in).
* **Events:** the 133 events of the event library are in; the 50 "strategic" decisions (`ev27`) and the country-specific ones are not.
* **Customers:** key accounts (business customers), reviews as a screen, price wars, rivals as businesses.
* **Equipment:** brand catalogue, used market, leasing, subscriptions, software licences; only standard equipment at the standard price.
* **Reports (weekly, monthly, yearly):**
  * A report closes when the seventh day of the last week of the period is over, just before the weekly turn, so the staged week money has all been released. Month and year end follow the engine's own `isMonthEnd` / `isYearEnd`, not the calendar day.
  * Saves from before reports have no earlier snapshot: the first week after loading only starts the books, and the first month or year report is marked "partial". Nothing is invented for earlier time. Save envelope version is now 2 (the migration adds empty report lists).
  * The player's account is classified by statement label (`ReportCounters`); anything unlabelled shows as "Everything else". Company cash is split into owner money, loans and a remainder; it is not a full cash-flow statement.
  * A company created during a period has no starting reputation or value, so its change shows as zero for that period.
  * Customers and capacity come from each company's weekly figures; trade types the native engine does not model yet report only what their books hold.
  * The engine sums some floats in dictionary order, so two runs of one seed agree to about 1e-9, not bit for bit. A report is an exact function of the state.
  * The app screens (Reports, Home prompt, Company > Finances) were only syntax-checked (`swiftc -parse`); they have not been compiled or run.
* **Screens:** see the checklist; no marketing analytics screen, no map, no rich list, no achievements.
* **Premises:** choosing a listing and buying equipment item by item exist in the engine but have no screen; "Fill in what is missing" does it.

## Behaviour that differs from the original on purpose

* **Native is always played day by day** (the original's "day mode"). The old week-at-a-time mode is not offered.
* The original's `wage0` variable in the consumer and mortgage loan limit is undefined; the original therefore uses a fixed floor of
  380 000 base units for income. This is kept (and documented in `Banking.swift`) so loan offers match; it should be fixed
  deliberately when the loan model is tuned.
* Some numbers in the original were frozen before later balance patches (trade demand, capacity, fixed costs). The native game
  stores the final numbers as data (`trades.json`) and uses the formula (`TradeCatalog.calibrate`) only for new trades.

## Candidate corrections (not changed, to keep parity)

* The gym earns about 28 % more than in the original in the statistical test (see `BALANCE_PARITY.md`).
* Cash at week 26 is lower than the original in every trade tested; cause not yet found.

## Needs a Mac / Xcode / an Apple account

See `MAC_STEPS.md`: generate the project, run on a simulator and a device, set the bundle id and signing team, add an app icon and
screenshots, run the unit tests in Xcode, archive and upload to TestFlight.

## Saves from the old iPhone app

The old Capacitor app kept its saves in the web view's storage, inside that app. A new app cannot read them. In the old game use
its save-to-file or copy function, then "Bring a save from the web game" on the new start screen. The original text is kept
untouched next to the converted save.
