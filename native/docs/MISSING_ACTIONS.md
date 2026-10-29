# Missing actions, screens and tabs by area

Hand-edited (not regenerated: `tools/parity_map.py` still lists the ids below as missing, so running `tools/gen_parity.py` would undo this file and PARITY_CHECKLIST.md until it is brought up to date).

**Nothing in the original's 557 actions, 105 screens or 43 company tabs is still marked "Not ported".** The last 50 actions, 28 screens and 7 company tabs were checked one by one against the Swift engine in this pass: 7 groups were real gameplay with no equivalent and were implemented (engine, tests, a minimal screen); the rest were already covered under another name or are presentation.

| Area | Actions | Screens | Company tabs |
|---|---|---|---|
| Not ported (all areas) | 0 | 0 | 0 |
| Presentation only (navigation, sheets, filters; no gameplay) | 146 | 6 | 12 |
| Engine only (logic and tests, no native screen yet) | 105 | 7 | 3 |

Details of "Engine only" are in the Status column of PARITY_CHECKLIST.md; they are the work of stage 2 and 3 (connect and design), not missing rules.

## The last 50 actions

### Implemented in this pass (new engine code, one test file per group)

| Original ids | What it does | Engine | Test | Screen |
|---|---|---|---|---|
| `ch39set`, `ch39off` | Buy an input (cleaning, bread, web ...) from one of your business customers (key accounts) once you know them; 2% below the outside price plus the relationship discount and a quarter of the discount you give them; the saving is booked weekly; the relationship warms. A new own-company supplier for the same input ends it. | `Businesses/AccountSupply.swift`, `GameEngine.buyFromAccount`, `stopBuyingFromAccount`, `accountSupplyCandidates` (saved in `rest["l39"]`) | `AccountSupplyTests` | Company > Chain > Supply from your own companies |
| `rivhow` | What a bought rival becomes: merge into your company (+8% cost, customers and some staff come over), close it (+12% cost, a competition-authority fine possible above 35% share), your branch, or a franchise office (owner stays / new franchisee). | `Businesses/RivalAbsorb.swift`, `GameEngine.absorbRival` | `RivalAbsorbTests` | Company > Market > rival |
| `branchgo` | A new site beside a rival (needs the franchise papers): your name from day one, takes size from that rival every week it is open. | `RivalAbsorb.openBranchNextToRival`, `GameEngine.openBranchNextToRival` | `RivalAbsorbTests` | Company > Market > rival |
| `rivfin27` | Buy a rival with a loan from your own bank (96 months, a quarter of its capital at most, only above its minimum capital ratio); undone if the purchase is refused. | `RivalAbsorb.buyWithOwnBank`, `GameEngine.buyRivalWithOwnBank` | `RivalAbsorbTests` | Company > Market > rival |
| `rm27` | Answer a rival's price cut: match the price (lowest price level minus one until the cut ends), hold prices and spend 3% of weekly sales on a campaign, or add a cheap second brand. | `RivalAbsorb.answerPriceCut`, `GameEngine.answerPriceCut` | `RivalAbsorbTests` | Company > Market > rival |
| `hqref` | Reference check on a main-office candidate: real level and years against the CV. | `Businesses/OfficeChecks.swift`, `GameEngine.referenceCheckCandidate` | `OfficeChecksTests` | Group > Main office |
| `reviewnow` | Review one manager now (free with a performance analyst, else an external review for a fee) and keep the result. | `OfficeChecks.reviewManagerNow`, `GameEngine.reviewManagerNow` | `OfficeChecksTests` | Group > Main office |

### Already covered by an engine function (marked in PARITY_CHECKLIST.md)

| Original ids | Engine function | Status |
|---|---|---|
| `acctmeet`, `acctdrop` | `meetAccount`, `dropAccount` | Engine + screen |
| `hfin` | `toggleHoldingFinanceManager` | Engine + screen |
| `hirehq` | `hireOffice` | Engine + screen (new Main office section) |
| `lx56din` | `hostYachtDinner` | Engine only |
| `md56`, `md56give` | `setManagerDuty` (and `leaveCyberToManager`) | Engine only |
| `ownpick`, `provpick` | `chooseOwnAdviser`, `chooseAdviser` | Engine only |
| `p11duty` | the duties are part of `offerPromotion` terms | Engine + screen |
| `pwgo`, `pwgo7`, `pwend` | `startPriceWar`, `endPriceWar` | Engine + screen |
| `reviewall` | `runManagerScorecards` | Engine + screen (Main office) |
| `riv31meet`, `rivmeet`, `rivbuy`, `rivclose`, `rivoffer` | `meetRival`, `buyRival`, `offerForRival` | Engine + screen |
| `sw33t` | `setWayToSell` | Engine + screen |
| `vmeet` | `lunchWithSupplier` | Engine + screen (People you buy from) |
| `warnstaff` | `warnStaff` | Engine + screen (Company > Team) |

### Presentation only (sheets, tabs, form fields, navigation; the gameplay behind them is in the table above or in the earlier mappings)

`acad36`, `acadc`, `acadco`, `acads`, `coursesheet` (pick a course: the course itself is `sendOnCourse`), `b14go`, `bk13ok` (dismiss a pop-up), `cv56meet`, `hq56t`, `hqcandopen`, `hqmode`, `hqtab`, `provsheet`, `pwlen`, `pwpick`, `rv56`, `rvf`, `rvmore`, `rvopen`, `sc56` (scroll to a heading).

## The 28 screens that were not ported

Which of them hold gameplay, and whether the current app reaches it:

| Screen | Gameplay | Now |
|---|---|---|
| `academy` | courses for staff and yourself | **new:** Company > Team > a person's menu > Send on a course |
| `staffman` | written warning, courses, layoffs | **new:** Company > Team (person menu, Lay off the weakest) |
| `hq`, `hqhire`, `office`, `heads` | rent an office, hire group staff, paperwork, references | **new:** Group > Main office (`heads` is only a title helper: presentation) |
| `meet` | call a meeting with all managers | **new:** Group > Main office > Call a meeting |
| `suppliers` | lunch with suppliers, a board deal for goods | **new:** Group > People you buy from |
| `branch`, `rivmoves` | new site beside a rival, answer a price cut | **new:** Company > Market > rival |
| `hqmk` | the team list | Team tab (already) |
| `bmeet11`, `bmeet12`, `board11`, `board12`, `boards12` | boards, votes, board meeting | Group > Boards (already) |
| `anrep11`, `map31`, `net31`, `world` | analyst report, maps, contacts and favours, the economy | Phone > World around you, Stats (already) |
| `org56` | organisation chart | Group > Management and the Team tab (already) |
| `pacct` | personal account statement | Phone > Activity (already) |
| `meetings`, `registry` | inbox title, list of companies linking to Setup | presentation |
| `month30`, `nem28`, `paper40`, `wx56` | read-only: monthly results, your rival, the business paper, weather and tourists | **Engine only**: the data is in the engine (`MonthView`, `Stories`, `Press`, `weatherForecast`), no native screen. No decision is hidden in them, so no screen was added in this pass; stage 3 |

Company tabs: `rivalsCard` (Company > Market > Rivals) and `ana` (insights, market analyst) are reachable; `demandLevel` and `route` are helpers (presentation); `abroad`, `advisers` and `insurance` are **Engine only** (the engine has `expandAbroad`, `chooseAdviser`, `toggleInsurancePolicy`; no native tab yet).

## Genuinely unported, and why

* Nothing is marked "Not ported" any more. What is left is listed in the Engine only rows: the three company tabs above, four read-only screens, 105 actions without a native control, and the open items in KNOWN_GAPS.md.
* Differences from the original in the new code: a company's own key accounts are not offered to itself as a supplier; the rival merge hires from the labour market in the main random stream (same as the original); the price-cut answer finds its demand effect by its size (the engine does not tag it); a purchase paid from your own bank is undone as a whole if the purchase is refused (the original keeps the loan).
* No Swift toolchain was available while this was written: nothing here has been compiled or run. The new tests (`AccountSupplyTests`, `RivalAbsorbTests`, `OfficeChecksTests`) and the new screens (`GroupOffice.swift`, edits to `CompanyChain`, `CompanyMarket`, `CompanyTeam`, `GroupView`) need a first CI run.
