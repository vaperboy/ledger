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

* **Trades:** 53 of 67 can be started from the trade menu (the salmon farm and the two energy trades are in), and the holding
  company and football clubs have their own entry points (New company > Holding company / Football club). Not started yet:
  project businesses (6), rental (3), finance (3). The menu says "Coming in a later update". A legacy save that contains them
  keeps their data untouched, they just do not run.
* **Energy, salmon, holding, football (new):** ported from engine/company/family_energy.js, family_basic.js (salmon), world/deals.js,
  world/football.js and the round-24 files. Not faithful or not ported:
  * the match draw of a league round shuffles the clubs (the original sorts with a random comparison, which cannot be copied);
  * the bundled UK and US surname lists are one name shorter than the original's, so generated club names after the city names differ there
    (clubs, values and ranks are identical; checked by `SpecialTradesDifferentialTests`);
  * holding: listing on the exchange, selling shares to investors, the finance manager of the head office and the management team (CEO) are not ported;
  * football: the original's "PRO" gating, club investors, and the rival owners buying clubs are not ported; transfers are the three tiers of
    round 24 (no individual players);
  * oil and gas: a manager buys stakes by itself only when the company has a manager (as in the original); the player buys stakes and drills from the
    Plant section; the fictional 78% oil tax is the country data, the exploration refund is the data key `oilRefund` (Norway);
  * the salmon "Stocking density" choice divides the number of smolt by its capacity effect (as the original does), so low density stocks MORE fish
    with less disease. That looks like an inverted rule in the original; kept for parity (see Candidate corrections);
  * the knob effects `k` and `t` of the power plant's source and price choices are not used by the original's weekly model either;
  * events not ported keep their absence: the 50 strategic decisions (ev27), rival-run energy firms, oil and salmon trade fairs and tenders.
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

* Salmon: low stocking density gives more fish and less disease (see above); the 15-month wait without income is covered by the start-up estimate, as in the original.
* The oil-and-gas start-up estimate has no working-capital buffer (the original has none either), so a new company needs cash put in before it can buy a field.

* The gym earns about 28 % more than in the original in the statistical test (see `BALANCE_PARITY.md`).
* Cash at week 26 is lower than the original in every trade tested; cause not yet found.

## Needs a Mac / Xcode / an Apple account

See `MAC_STEPS.md`: generate the project, run on a simulator and a device, set the bundle id and signing team, add an app icon and
screenshots, run the unit tests in Xcode, archive and upload to TestFlight.

## Saves from the old iPhone app

The old Capacitor app kept its saves in the web view's storage, inside that app. A new app cannot read them. In the old game use
its save-to-file or copy function, then "Bring a save from the web game" on the new start screen. The original text is kept
untouched next to the converted save.
