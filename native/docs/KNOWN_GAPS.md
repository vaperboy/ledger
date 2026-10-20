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
* **Screens:** see the checklist; there is no week report screen, no marketing analytics screen, no map, no rich list, no achievements.
* **Premises:** choosing a listing and buying equipment item by item exist in the engine but have no screen; "Fill in what is missing" does it.

## Behaviour that differs from the original on purpose

* **Native is always played day by day** (the original's "day mode"). The old week-at-a-time mode is not offered.
* The original's `wage0` variable in the consumer and mortgage loan limit is undefined; the original therefore uses a fixed floor of
  380 000 base units for income. This is kept (and documented in `Banking.swift`) so loan offers match; it should be fixed
  deliberately when the loan model is tuned.
* Some numbers in the original were frozen before later balance patches (trade demand, capacity, fixed costs). The native game
  stores the final numbers as data (`trades.json`) and uses the formula (`TradeCatalog.calibrate`) only for new trades.

## Candidate corrections (not changed, to keep parity)

* The gym and the restaurant are generous or slow compared with real life (see `BALANCE_PARITY.md`, "Which is closer to real life");
  both engines agree, so they were left for a deliberate balance pass.
* The vendor system (goods quality and cost per supplier), vehicle and equipment brands, and poaching are not ported; they explain
  small differences in quality, staff and courier cash.

## Needs a Mac / Xcode / an Apple account

See `MAC_STEPS.md`: generate the project, run on a simulator and a device, set the bundle id and signing team, add an app icon and
screenshots, run the unit tests in Xcode, archive and upload to TestFlight.

## Saves from the old iPhone app

The old Capacitor app kept its saves in the web view's storage, inside that app. A new app cannot read them. In the old game use
its save-to-file or copy function, then "Bring a save from the web game" on the new start screen. The original text is kept
untouched next to the converted save.
