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

* **Trades:** 56 of 67 can be started (the 50 of the simple families plus residential rentals, commercial property, parking and
  self-storage, insurance company, bank and investment fund). Not started yet: project businesses (6), energy (2), the holding
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

## Rental and finance trades (RentalModel, FinanceModel)

The weekly models, the property actions, insurance products and the finance events are compared with the original on a saved game
(`RentalFinanceDifferentialTests`). What is different or missing:

* **Franchise tenants.** The original offers its franchise brands as tenants of commercial buildings, and a franchisee of yours can
  lease space in a building you own. Franchises are not ported, so tenants are local businesses with made-up names, and the rule
  "a company of yours rents there" never applies.
* **Group lending and group insurance.** The original lets your own bank lend to your other companies at a lower rate (`fm.gb`, the
  loan's `bank` field) and your own insurer insure them. The loan side exists in `Banking` (own-bank funding, "Loans to your group"),
  but there is no screen to choose your insurer and an insurer's `claims`/premium flows from your companies are not booked.
* **A bank or insurer that is bust but has cash.** The original has no insolvency rule for them (only running out of cash fails a
  company). The native game adds one: capital gone (bank: negative equity and negative ratio; insurer: solvency under 0.05 and
  negative cash) for eight weeks and the regulator closes it. Depositors' and policyholders' losses are not modelled, as in the original.
* **Ramp-up is slow, as in the original.** Finance companies have no organic awareness; without marketing an insurer wins about
  1 400 policies in two years and a bank lends a tenth of what its capital allows, so both lose money for years. Plain numbers
  (three seeds, UK, standard set-up, with a modest campaign): the insurer reaches 6 400 policies and 40 M premiums in year three but is
  still 10 M a year short of break-even (it needs roughly 12 000 policies); the bank lends 720 M of 1 600 M possible and loses 5 to 8 M
  a year; the fund earns 3 to 14 M a year in the good seeds and about nothing in the bad one (it follows the share index).
  At full size the economics are in the range one would expect (insurer combined ratio about 100 % at 20 000 policies, bank return on
  equity about 4 to 9 % depending on how fully the capital is lent, fund fee 1.5 % of assets), but no target figure from the
  brief (insurer combined ratio 95 to 100 %, bank ROE 8 to 12 %) is reached in the first three years, and none of the numbers was
  tuned away from the original to reach it. If the game should be easier to start in finance, raise the starting awareness of finance
  companies (`Marketing.swift`, the organic awareness rule that excludes `fin`) rather than touching the models.
* **Rental yields** after three years (UK, 55 % mortgage): residential gross 5.4 %, commercial 8.6 %, parking 8.5 % of property value;
  after mortgage interest and upkeep the equity earns about 1.5 % (residential), 5 % (commercial) and 7 % (parking) a year in cash,
  plus the rise in property values. Parking is below the 10 to 15 % one might expect; that is the original's number.
* The central bank liquidity facility is ported (`bank_liquidity.js`); the insurance product approvals use the `ins_*` documents of
  the native tables (the old `skade`, `bil` ... ids are renamed on import).
* `rn_*` and `f_*` events that only change numbers (demand, rent cuts) are data and work; `f_storm`, `f_run`, `f_default` use the
  later, gentler loan-loss rule of the original (`people/before_hiring.js`).

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
