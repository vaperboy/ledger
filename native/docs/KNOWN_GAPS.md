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
* **Trades:** 56 of 67 can be started. Not started yet: rental (3), finance (3), energy (2), the holding
  company, football clubs, and the salmon farm. (The six project trades are in: plumber, electrician, construction, engineering
  office, event agency, real-estate development; see the next section.) The menu says "Coming in a later update". A legacy save that contains them
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
  * events not ported keep their absence: rival-run energy firms, oil and salmon trade fairs and tenders.
* **Groups and ownership:** managers beyond the basic model, boards and votes, chains, franchises, branches, intercompany supply,
  holding companies, startups, private equity (their values still count in net worth when imported). Luxury and estates are in (see Equipment market and luxury).
* **People:** poaching, promotions, assistant managers (pay talks and paperwork are in).
* **Events:** the 133 events of the event library are in, and 66 of the 79 strategic decisions of round 27e (`ev27`, `Events/StrategicDecisions.swift`) with the country events. Not ported because they need rivals as businesses, listings or private equity:
  `s_acqoffer`, `g_location`, `g_franinq`, `e_merger`, `e_distress`, `t_ipo`, `t_pe`, `t_hostile`, `t_antitrust`, `t_activist`, `t_auction`, `c_JP_succ`, `c_US_vc`. Approximations: `e_execleave` changes the manager's pay and capacity instead of hiring a named replacement;
  `c_UK_rent` raises costs instead of the rent line; the credit-tightening country event moves loan margins for 39 weeks; the original's rule that a store inside a chain answers for itself is not ported.
* **Selling and awards:** a company can be sold whole (`CompanySale`, Money tab of the company). Selling part of your shares, raising funding, founding startups, private equity commitments and stakes in rival groups are not ported.
  Trophies: about 60 of the original's ~90 are in (`Trophies`); missing are those that need acquisitions, markets and country rank, gifts, luxury, startups, private equity, chains, franchises, R&D, review counts, listed holdings and manager tenure; no full-screen celebration, the inbox tells you and the wall shows the date.
  Business awards run at year end but rank by your place on the rich list (the original ranks companies by revenue and growth against rivals); no "fastest growing" award. The rich list is the original's curve (top fortune by country size, rank^-0.75) without rival group owners.
  * events not ported keep their absence: the 50 strategic decisions (ev27), rival-run energy firms, oil and salmon trade fairs and tenders.
* **Groups and ownership:** boards and votes, the CEO and managing director, regional and chain managers (they need chains and shareholders), chains, franchises, branches, intercompany supply,
  holding companies, startups, private equity, luxury and estates (their values still count in net worth when imported).
* **People:** pay talks, paperwork, managers (search, hire, authority, pay review, proposals, resignation, rival offers, move), assistant managers,
  promotions and the poaching of the best worker are in. Not ported: a manager's proposals to buy equipment, vehicles and premises; the profit bonus
  and shares, duties/authority/report choices and analyst report in the promotion talk; promoting a manager to a chief post; poaching after a course;
  the manager's own promotions-from-within and the assistant's monthly suggestion and basic insurance; owner-attention drift is read in demand only (not in the manager's quality).
* **Events:** the 133 events of the event library are in; the 50 "strategic" decisions (`ev27`) and the country-specific ones are not.
* **Customers:** key accounts (business customers), reviews as a screen, price wars, rivals as businesses.
* **Equipment:** the market is in (see Equipment market and luxury). Quick setup still buys the standard class at the standard price, as before.
* **Reports (weekly, monthly, yearly):**
  * A report closes when the seventh day of the last week of the period is over, just before the weekly turn, so the staged week money has all been released. Month and year end follow the engine's own `isMonthEnd` / `isYearEnd`, not the calendar day.
  * Saves from before reports have no earlier snapshot: the first week after loading only starts the books, and the first month or year report is marked "partial". Nothing is invented for earlier time. Save envelope version is now 2 (the migration adds empty report lists).
  * The player's account is classified by statement label (`ReportCounters`); anything unlabelled shows as "Everything else". Company cash is split into owner money, loans and a remainder; it is not a full cash-flow statement.
  * A company created during a period has no starting reputation or value, so its change shows as zero for that period.
  * Customers and capacity come from each company's weekly figures; trade types the native engine does not model yet report only what their books hold.
  * The engine sums some floats in dictionary order, so two runs of one seed agree to about 1e-9, not bit for bit. A report is an exact function of the state.
  * The app screens (Reports, Home prompt, Company > Finances) were only syntax-checked (`swiftc -parse`); they have not been compiled or run.
* **Screens:** see the checklist; no marketing analytics screen, no map, the rich list, achievements and company sale screens were only syntax-checked (`swiftc -parse`).
* **Premises:** choosing a listing and buying equipment item by item exist in the engine but have no screen; "Fill in what is missing" does it.
* **Screens:** see the checklist; no marketing analytics screen, no map, no rich list, no achievements.
* **Premises:** the listing choice (rent, or buy with a mortgage) and item-by-item buying have a screen (Company > Equipment, fleet and premises). Not yet: the home-trade workshop listings (R37), franchise building terms, a landlord company receiving the rent.

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
## Project businesses: what is and is not faithful

Ported: the hours model of `trades_in_hours.js` (requests by day, oldest job first, 30/40/30 milestones, receivables with the
usual chance of non-payment, overruns, delay and defect events), the event agency's dated bookings, referrals and rebookings,
the developer (zoning, building, sales, construction loan repaid from 70% of sales, work in progress as an asset), tenders for jobs.

* **Calibration (deliberate):** each job trade has a `priceFactor` and `demandFactor` in `ProjectModel.specs`. Without them the
  original's own numbers lose money for a small construction firm and an engineering office (see BALANCE_PARITY). They are the
  only knobs; everything else is the original's formula.
* Reviews are a counter and a star sum (no texts, no review screen); the tender "needs N stars" rule uses them after 5 reviews.
* Tenders: only job tenders for the six trades. The original's volume contracts (business customers) are not ported.
* The old contract-backlog model (`FAM.project.custom` before hours) is dead code in the original for every job trade, so it is
  not ported; jobs from tenders enter the hours model, as in the original.
* Developer: no "other assets" screen line; `fm.assets` (work in progress) counts in the company's value as in the original.
  The auto-start by a manager is ported; the player starts projects from Company > Projects.
* Capacity of an engineering office with an empty support role differs from the original on purpose (see the parity test).
* A tender's winner is decided from a seed made of the tender, as in the original; the rivals are not businesses.

## Behaviour that differs from the original on purpose

* **Native is always played day by day** (the original's "day mode"). The old week-at-a-time mode is not offered.
* The original's `wage0` variable in the consumer and mortgage loan limit is undefined; the original therefore used a fixed floor of
  380 000 base units for income for every country. Fixed on purpose: the floor is 6.8 months of the country's median wage
  (`Country.medianMonthlyWage`), see `MONEY_SCALING.md`. Other fixed money amounts were scaled in the same pass and a lint test bans new ones.
* Capital-heavy trades, the 2026 tax figures and the start-up loan follow the real world, not the original: see `BALANCE_REPORT.md`
  (trade tuning in `trade_tuning.json`; the parity tests skip those trades) and `TAX_SOURCES.md` (every changed figure).
* Some numbers in the original were frozen before later balance patches (trade demand, capacity, fixed costs). The native game
  stores the final numbers as data (`trades.json`) and uses the formula (`TradeCatalog.calibrate`) only for new trades.

## Candidate corrections (not changed, to keep parity)

* The gym and the restaurant are generous or slow compared with real life (see `BALANCE_PARITY.md`, "Which is closer to real life");
  both engines agree, so they were left for a deliberate balance pass.
* The vendor system (goods quality and cost per supplier) and poaching are not ported (equipment and vehicle brands are); they explain
  small differences in quality, staff and courier cash.

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

## Equipment market and luxury (EquipmentMarket, Luxury)

* **Brands:** `Resources/equipment_brands.json` holds the maker names and rules; the catalogue (3 classes per brand, price factor, rating, output, reliability) follows `eqCat`/`vehCat` with the same seeded draws. Output (`perf`) and reliability (`rel`) of the brands bought feed the existing capacity and breakdown models.
* **Not ported from the buying file:** supplier relationship discounts (`vdisc`: price is always the list price), the equipment each person needs (`PER` rules: a car per estate agent, a van per three cleaners; the screen shows the trade's standard count instead), own-car mileage for agents, courier/trucking fuel by van size, taxi class demand, the hiring screen's work-car choice, picture drawings.
* **Quick setup** still buys the standard item at the standard price (the original's `mgrCat` picks the best standard-class brand); it was left alone so the balance does not move.
* **Leasing** is for vehicles and machines of 100 000 or more (as the original); returning leased equipment is a plain end of the lease.
* **Luxury:** items, rates, uses, risks and estate yields are data (`Resources/luxury.json`). Pieces live in `rest["lux"]` like the original's `S.lux`, so imported saves keep working. Company cars and jets sit in the company's assets as `luxBV`.
* **Not ported from lifestyle/estates:** the fame and rest perks of homes and jets, the lower fee for starting abroad with a jet, serious car/watch offers, the yacht dinner, the tax-office check on an oversized company car, the margin call on a loan against the collection (the loan itself is offered against `Luxury.collateral`), the vineyard's effect on demand in your restaurants, the castle's fame, museum lending provenance, Ledger Pro gating of estates, and the photographs. The original has no "family office"; none is invented.
* **Tests:** `MarketTests` (catalogue is stable, premises, buy new/used/lease/finance/subscribe, sell, luxury buy/charter/sell, company car, books balance). Not run: the full suite, and the app screens (only `swiftc -parse`).

## Chains, franchises, branches and supply between your companies

* Ported: chain registration and the checklist, new stores (set up with the standard package, run on the chain's rules), chain rules and a store's own rules, brand marketing, buying discounts, shared awareness, monthly pay floor, reach; franchising out; being a franchisee; master franchise; supply between your own companies at market, cost + 10% or cost. Checked with `ChainsTests` (books balance); no differential tests against the original. The screens were only syntax-checked (`swiftc -parse`).
* Brands are made from the game seed and the trade and country with a hashed random stream, not the original's; the same game always shows the same brands, but they are not the original's brands.
* "Someone to look after franchisees" also counts a manager in every store of a chain of three or more, because chain chiefs, a managing director and boards are not ported.
* Not ported: store managers asking to leave the chain price, bosses deciding requests and moving money between sister stores (group loans), chain board with seats and votes, the price-percent step of a store, the 'opens in 3 weeks' wait for a new store (it opens when its paperwork and team are ready), a franchisee's location in your own building and the building 15% under market, prospects hosted at a perk, 'supply from inside' protection against outside supplier events, the 25%-of-capital limit on lending from your own bank, opening next to a rival's best site (branch screen), rival supply (`rivalSupply`).
* As in the original, intercompany sales carry no VAT; each company's profit tax follows from its own books. Master franchise fee is in the franchisor's currency.
## Customers, competition and reputation

* **Reviews** are one system (`Reviews`): stars follow quality and reputation, the average of stored reviews is the rating; project trades review per finished job, every other trade weekly. Not ported: tourists writing from their own country, owner replies (the original has none).
* **Key accounts** buy from the capacity the walk-ins leave over (the original adds them to the demand and shares a full shop; the day-by-day trade has no account volume). The account's trade profile (what it sells, so you could buy from it) is not ported.
* **Rivals** live inside the market record (`mk[key].riv`) and set the market price index like the original. Rival calls about matched price cuts (and the illegal price-fixing choice) are not ported. Rival groups: undercut, open next door, buy a rival, marketing push, raise prices, go abroad, distress and collapse are ported; **bids for your companies, poaching your manager, buying your suppliers and the ranking of the biggest companies are not**.
* **Market map:** the analyst roles (market analyst in a company, data analyst in the head office) are not hireable yet, so every market is shown at the "feeling" level (words) until those roles exist; the code for ranges and monthly reports is in and tested only through the roles being absent. The "weight in the economy" block is not ported.
* **Price moves:** percent price change, discount campaigns (with the fine for a fake discount) and price wars are ported; the forecast boxes (customers and margin) and managers moving prices in small steps are not.
* **Lawsuits** (settle or court, court dates for big cases, lost by default) and **cyber attacks** (IT security levels, backups, training, fraud, ransomware, leak, outage) are ported; a manager does not pick the IT level.
* **World around you:** rivals remember you (mood, temperament, grudges, lunch). Public image, the network of contacts and favours, and the maps screen are not ported. Software products of your own startup are not ported.

## Startups, funding, private equity, listings (this branch)

* Ported: `Events/Startups`, `Funding`, `PrivateEquity`, `Shareholders`, `BigMeeting`, `GroupDeals`, `Ventures`, partial sales and buyer talk in `CompanySale`, the 13 decisions in `StrategicDecisionsCorporate`, trophies listed/su1/sux/pe1/pe2.
* Not faithful or left: the earlier software startup is folded into the SaaS sector; a social app's marketing boost; the finance manager of a holding who negotiates raises; investors you hosted; the yearly manager review and the "replace the manager" owners' demand; Ledger Pro gating (no Pro tier); market share for the competition authority is your sales against the market size, not the market map; rival-based decisions and group bids need the Competition data (`rest["mk"].riv`, `rest["g27"]`) and a foreign group for the auction must already exist. Layoff screens (`rfset`, `warnstaff`, `loset`, `logo`) and `hfin` are not part of this area.
