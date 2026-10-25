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

* **Trades:** all 67 can be started: the 50 simple-family trades, the six project trades, rental (3), finance (3), energy (2), salmon, the holding company (New company > Holding company) and football clubs.
* **Energy, salmon, holding, football (new):** ported from engine/company/family_energy.js, family_basic.js (salmon), world/deals.js,
  world/football.js and the round-24 files. Not faithful or not ported:
  * the match draw of a league round shuffles the clubs (the original sorts with a random comparison, which cannot be copied);
  * the bundled UK and US surname lists are one name shorter than the original's, so generated club names after the city names differ there
    (clubs, values and ranks are identical; checked by `SpecialTradesDifferentialTests`);
  * holding: listing on the exchange and selling shares to investors are ported (`Startups`, `CompanySale`); the finance manager of the head office is in (`FinanceManager`);
  * football: the original has no "PRO" gating, club investors or rival owners buying clubs (checked), so none exist here; transfers are the three tiers of
    round 24 (no individual players);
  * oil and gas: a manager buys stakes by itself only when the company has a manager (as in the original); the player buys stakes and drills from the
    Plant section; the fictional 78% oil tax is the country data, the exploration refund is the data key `oilRefund` (Norway);
  * the salmon "Stocking density" choice divides the number of smolt by its capacity effect (as the original does), so low density stocks MORE fish
    with less disease. That looks like an inverted rule in the original; kept for parity (see Candidate corrections);
  * the knob effects `k` and `t` of the power plant's source and price choices are not used by the original's weekly model either;
  * rival-run energy firms, oil and salmon trade fairs and tenders, and club investors do not exist in the original, so there is nothing to port.
* **Events:** the 133 events of the event library and all of the strategic decisions of round 27e (`ev27`, `Events/StrategicDecisions*.swift`) with the country events are in. Approximations: `e_execleave` changes the manager's pay and capacity instead of hiring a named replacement;
  `c_UK_rent` raises costs instead of the rent line; the credit-tightening country event moves loan margins for 39 weeks; the original's rule that a store inside a chain answers for itself is not ported.
* **Selling and awards:** a company can be sold whole or in part (`CompanySale`); funding rounds, startups, private equity and stakes in rival groups are in (see below). Trophies are ported (`Trophies`, `TrophiesMore`, incl. chain/franchise ladders); missing: n1, rk, no1, top10 (need market/country rank data) and team56. No full-screen celebration; the inbox tells you and the wall shows the date.
  Business awards run at year end but rank by your place on the rich list (the original ranks companies by revenue and growth against rivals); no "fastest growing" award. The rich list is the original's curve (top fortune by country size, rank^-0.75) without rival group owners.
* **Compliance, finance manager, perks, targets, contracts:** abroad compliance fines, the finance manager, staff perks, manager targets and yearly budget, volume contracts and tenders, sourcing hookups, rival life (strategy, fortune, exit, entrants) and the trophies above are ported (engine only; unbuilt).
* **People:** pay talks, paperwork, managers (search, hire with profit bonus, authority, pay review, proposals, resignation, rival offers, move), assistant managers, boards/CEO/MD/regional posts, promotions, `st28pro`, find-a-successor and the poaching of the best worker are in. Not ported: seasonal-worker hiring by managers; poaching after a course; the assistant's monthly suggestion and basic insurance; owner-attention drift is read in demand only (not in the manager's quality).
* **Customers:** key accounts, reviews, price wars and rivals as businesses are in (see Customers, competition and reputation).
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
* **Premises:** the listing choice (rent, or buy with a mortgage) and item-by-item buying have a screen (Company > Equipment, fleet and premises). Home-trade workshop listings, franchise rent discount and a landlord company receiving the rent are in the engine (`PremisesExtras`); franchise building terms are not.

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
* Tenders: job tenders for the six trades, and volume tenders/contracts for business customers of services, shops and carriers (`VolumeTenders`, `VolumeContracts`). Not ported: farm, factory and furniture tenders.
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

* **Pay and tax rules abroad:** the country data has no statutory minimum wage, overtime law or notice period (wages come from role tables; overtime is the original's 1.5x in `DailyTrade`; severance is 0.5/1/2 months by tenure). Employer social, corporate tax with loss carry-forward, VAT and owner-salary withholding use the company's own country; the player's yearly personal assessment (dividends, gains, sole-trader income) uses the home country by design (`CompanyCountryRulesTests`).

## Candidate corrections (not changed, to keep parity)

* The gym and the restaurant are generous or slow compared with real life (see `BALANCE_PARITY.md`, "Which is closer to real life");
  both engines agree, so they were left for a deliberate balance pass.
* The vendor system (goods quality and cost per supplier) is partly in (`Suppliers`, `Sourcing`); poaching is ported (`Rivals`); they explain
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
* **Equipment buying file:** supplier relationship discounts (`vdisc`, `Suppliers`), per-person equipment rules, own-car mileage, courier fuel by van size, taxi class and the work-car choice are ported (`PersonalEquipment`, `PremisesExtras`). Not ported: picture drawings.
* **Quick setup** still buys the standard item at the standard price (the original's `mgrCat` picks the best standard-class brand); it was left alone so the balance does not move.
* **Leasing** is for vehicles and machines of 100 000 or more (as the original); returning leased equipment is a plain end of the lease.
* **Luxury:** items, rates, uses, risks and estate yields are data (`Resources/luxury.json`). Pieces live in `rest["lux"]` like the original's `S.lux`, so imported saves keep working. Company cars and jets sit in the company's assets as `luxBV`.
* **Not ported from lifestyle/estates:** the margin call on a loan against the collection (the loan itself is offered against `Luxury.collateral`), the vineyard's effect on demand in your restaurants, museum lending provenance, Ledger Pro gating of estates, and the photographs. Fame, jet fee, serious buyers and the yacht dinner are in (`LuxuryExtras`, `Luxury.fameBonus`). The original has no "family office"; none is invented.
* **Tests:** `MarketTests` (catalogue is stable, premises, buy new/used/lease/finance/subscribe, sell, luxury buy/charter/sell, company car, books balance). Not run: the full suite, and the app screens (only `swiftc -parse`).

## Chains, franchises, branches and supply between your companies

* Ported: chain registration and the checklist, new stores (set up with the standard package, run on the chain's rules), chain rules and a store's own rules, brand marketing, buying discounts, shared awareness, monthly pay floor, reach; franchising out; being a franchisee; master franchise; supply between your own companies at market, cost + 10% or cost. Checked with `ChainsTests` (books balance); no differential tests against the original. The screens were only syntax-checked (`swiftc -parse`).
* Brands are made from the game seed and the trade and country with a hashed random stream, not the original's; the same game always shows the same brands, but they are not the original's brands.
* "Someone to look after franchisees" also counts a manager in every store of a chain of three or more, because chain chiefs, a managing director and boards are not ported.
* Ported since: price requests and group loans, the 3-week opening wait, the 25% own-bank cap, board with seats and votes, supply-from-inside protection (`Sourcing`). Not ported: store managers asking to leave the chain price (partial), a franchisee's location in your own building and the building 15% under market, opening next to a rival's best site (branch screen), rival supply (`rivalSupply`).
* As in the original, intercompany sales carry no VAT; each company's profit tax follows from its own books. Master franchise fee is in the franchisor's currency.
## Customers, competition and reputation


## Startups, funding, private equity, listings (this branch)

* Ported: `Events/Startups`, `Funding`, `PrivateEquity`, `Shareholders`, `BigMeeting`, `GroupDeals`, `Ventures`, partial sales and buyer talk in `CompanySale`, the 13 decisions in `StrategicDecisionsCorporate`, trophies listed/su1/sux/pe1/pe2.
* Not faithful or left: the earlier software startup is folded into the SaaS sector; a social app's marketing boost; investors you hosted; Ledger Pro gating (no Pro tier); market share for the competition authority is your sales against the market size, not the market map. The finance manager (`FinanceManager`), layoff screens (`rfset`, `loset`, `logo`) and the yearly manager review are ported at engine level.
## Boards, executives, head office, meetings, academy (ManagerTeam, ManagerBoards, ManagerMeetings, ManagerPromotions, ManagerProposals, ChainHierarchy, Headquarters, Academy)

* Ported: see `MASTER_CHECKLIST.md`. Effects of the team are cached on the company (`tm`, `mgrLift`, `mdCoach`, `drift56`, `boss56`, `brdLaw`, `brdMkt`) each week and read by demand, capacity, marketing, quits, fines and manager quality.
* Not faithful: fame is a simplified formula (no foreign countries); head office candidates come from the manager generator with the role's pay, not worker search; holders (co-owners) exist only when given as shares in a promotion, since funding rounds are not ported, so owner votes and director elections are rare; the "loan" vote is not forced on the loan action (use `boardVote` first); manager duties `sec`/`ins` are stored but do nothing; a dividend policy is stored but no quarterly dividend is paid; the finance manager does not lower loan margins; course prices use the country cost index only.
* Not ported: `grp27` (profile of a rival group, depends on rival groups' UI), board pack report preference of a promoted manager. (Supply-from-inside protection is in: `Sourcing`.)
## Company tabs, misc screens, fleet and luxury leftovers (branch worktree-agent-a62df16577d42dde6)

| Id | What it is in the original | Native |
|---|---|---|
| advisers / insurance | accountant, law firm, insurer choice (own group firms too), policies | `Advisers`, `GameEngine.chooseAdviser`, `toggleInsurancePolicy`; premium factor, claim haggling, own insurer income |
| abroad | open a subsidiary in another country | `Abroad`, `expandAbroad`; foreign_entity document and the compliance fines (`AbroadComplianceTests`) |
| complaints, staffProfile | complaint list and answers; person detail, mood, warnings, courses, dismissal, layoffs, commission | `Complaints`, `StaffProfile` |
| supply (vdisc) | supplier owners, relationship discounts, board deals, goods and repair supplier | `Suppliers`; discount applies to goods cost and equipment price. Auto pick uses a seed from company and half-year, not the shared random stream |
| give28 | gifts, sponsorships, foundation | `Giving` |
| amb27 | ambitions with tiers and perks | `Ambitions`. Perks are wired into loan margin, abroad fee, quality, supply cost and rival prices; market-share and world-rank facts exist |
| paper40 / pr28 | local paper front page, interviews, public image numbers | `Press` |
| wx56 | storm warnings and damage, securing, tourist news, forecast | `WeatherEvents` (weather effects were already in `Weather`) |
| month30 | monthly results | `MonthView` |
| store13, res36, brand56, fr56, img31(screen), pro59 | presentation screens or in-app purchase | skipped; no new logic |
| net31, img31 data, pk58, tg58, fs58, nem28, top28, st28 | contacts and favours, staff perks and hosting, targets and budgets, first steps, nemesis, Top 50, staff stories | `WorldAround`, `StaffPerks`, `ManagerTargets`, `OpeningChecklist`, `Stories`: all ported (engine; unbuilt) |
| fleet / premises / luxury leftovers | car per agent, van per three cleaners, own car mileage, courier fuel, taxi class, hiring car choice, home-trade workshop listings, franchise rent discount, landlord company rent, fame, rest, jet fee, serious buyer, yacht dinner, tax-office check, margin call, own wine | `PersonalEquipment`, `PremisesExtras`, `LuxuryExtras`. `Luxury.fameBonus` and `Luxury.offerBonus` must be called from the head-office fame and rival offer code. Yacht dinner guests are suppliers only (no contacts network yet) |
* **Reviews** are one system (`Reviews`): stars follow quality and reputation, the average of stored reviews is the rating; project trades review per finished job, every other trade weekly. Tourists write from their own country where the trade has foreign visitors (flag, "on holiday here"). Not ported: the "heard about you at home" line (needs national media campaigns abroad). Owner replies do not exist in the original.
* **Key accounts** share a full shop with the walk-ins (demand added, everyone gets the same share of the capacity); the day-by-day trade has no account volume, so the accounts are added to the week's total. Each account runs a trade (`KeyAccounts.profile`): once you know them (relationship 22 and up) the screen says you can buy from them. Not ported: the actual supply-chain link to an account (`L39`, `custSuppliers`).
* **Rivals** live inside the market record (`mk[key].riv`) and set the market price index like the original. Rival owners call about a matched price cut or to ask what is up, with the illegal price-fixing answers (8% fine when found out, `Rivals.collusionWeek`). Rival groups: undercut, open next door, buy a rival, marketing push, raise prices, go abroad, **poach your manager** (match, retention bonus, let go), **buy your supplier** (goods cost 6% more for everyone who buys there; vendor choice is not ported, so each company has one default goods supplier), **bid for your company** (accept, ask for more, refuse; outside owners can sell without you), distress and collapse. The **ranking of the biggest companies** (`CompanyRanking`: you, the groups, the rivals you face, and the register's crowd as a size curve) feeds the awards (business of the year, new "Fastest growing") instead of the rich list. Not ported: national banks, insurers and funds as ranked names; crowd firms as named rows beside you.
* **Market map:** the market analyst is hired like any worker (role `mktan`, offered on companies with a market; `MarketMap.analystHireVerdict`), the data analyst into the head office (`MarketMap.hireDataAnalyst`, paid monthly from `MarketMap.weekly` until the head-office branch pays its staff). With them the ranges and monthly reports apply, and a market analyst's report or the data analyst's company report can be ordered. The "weight in the economy" block (loans, jobs, regulator attention) is in (`MarketMap.weight`). The analyst report leaves out the brand-lift estimate and the two-month forecast (marketing outlook not ported).
* **Price moves:** percent price change, discount campaigns (with the fine for a fake discount), price wars, the forecast boxes (customers at first and later, margin; a gut feeling or the data analyst's range) and managers moving prices in 6% steps are ported.
* **Lawsuits** (settle or court, court dates for big cases, lost by default) and **cyber attacks** (IT security levels, backups, training, fraud, ransomware, leak, outage) are ported; a manager picks the IT level, backups and training at each month end unless you chose a level yourself (then yours stands until you hand it back). The per-duty switches of the original (`mgrDuty`) and the chain override are not ported: a manager always looks after it.
* **World around you:** rivals remember you (mood, temperament, grudges, lunch). Public image, people you know (managers, press, bank, council, lawyer, investor, rival owners), favours and promises (ask, return, keep, call in; a banker friend cuts your loan rate, a lawyer halves a fine) and the maps (ownership tree, presence by city, circles of influence) are in as engine read models and one flat screen (Phone > World around you). Not ported: interviews and giving back (the press group of the image stays neutral), suppliers as contacts, a politician sorting a missing permit, "the week in numbers".
* **Software of your own** is built on a web-development company (`SoftwareProducts`: coders, your hours, beta then live, customers and revenue, model and price; your own companies use it in place of a bought licence and the producer is paid). `SoftwareProducts.step` is the whole weekly model on a bare record so the startup branch can host the same product. There is no startup yet, no screen to start or steer a product, and no check of your free hours before coding yourself.
* **Supplier terms (stage 3):** the late-payment rule of a country is read from `commerce.latePayment` in its data (`margin` over the policy rate, or a fixed `annual` rate); no country entry has one yet because the statutes could not be checked in the build session (no network), so every country uses the game default of 2% a month, the same rate the monthly bills already used. Terms exist for outside goods (cash on delivery, month end, 30, 60 days; repairs stay on the monthly bill), own-company supply (weekly, 14, 30 days) and business customers (the trade's own terms, some late). Business customers are now invoiced one by one instead of paid at the till. Price talks cover outside goods and repair suppliers only. A chain rule binds a franchised unit only if its agreement carries `supStd` for the input (nothing writes it yet, so franchised units are free today).

* **Money and supply (fix/money-supply):** (1) Delivery as a service: the outside courier is a generic market service whose cost per delivery is the share of the delivered orders in `supply_kinds.json` and whose reliability is `rel` in the add-on's data (`sales_ways.json`); it has no capacity limit of its own, only the reliability. The shares (8-12% of delivered orders) and `rel` 0.9 are game design values, not sourced. The delivery cost is carved out of the existing app fee (the all-in fee is unchanged), so the only balance change is that undelivered orders bring no customers. Parcel delivery covers every trade whose equipment list has a delivery vehicle (bakery and hardware added). (3) Intercompany tax: same-country sales between your companies carry VAT at the supplier's rate and trade (reclaimed by a registered buyer, a cost for one below the threshold; none in sales-tax countries, where a sale for resale is not taxed). The VAT credit the buyer already took on the outside purchase that the own supply displaces is not reversed. Cross-border supply between your companies does not exist (suppliers must be in the buyer's country), so cross-border VAT/customs and transfer-pricing documentation or penalties (beyond the arm's-length cap `priceFactor`) are not modelled. (5) Short-paying an own supplier flags it after `ownLate.flagAfterWeeks` and cuts the share it delivers by `ownLate.capacityFactor` (design values). (6) Franchise supplier locks: only food trades (cafe, restaurant, foodtruck, bakery) of brand tier 2+ fix the goods supplier (`franchise_standards.json`, design values; the approved supplier is one of the store's outside candidates picked by the brand); no real brand contract is quoted, and `knobStd` is still not written by any brand. (7) The late-payment rate stays the game default (2% a month); no country entry added because no source was verified.
