# Master checklist (single source of truth)

> Open work is tracked in `IMPLEMENTATION_ROADMAP.md` (KEEP / ADAPT / REMOVE / DEFER / ALREADY DONE, with dependencies); hands-on app tests in `HANDS_ON_TEST_PLAN.md`. This file stays the status log.

## CURRENT STATUS (verified, 23 Oct 2026)
- **Engine:** compiles on Swift 6.0.3 (Linux) and macOS CI; full engine suite 279/279 green (`cd native/Engine && swift test`, about 9 min).
- **App:** builds for the iOS simulator in CI (`app-build`); iPhone, iPad and iOS 26 screenshot tours pass. Navigation is Company / Team / Group / Projects / Inbox.
- **Stage 1 mechanics:** every action in the original is covered (engine, screen, or presentation-only); see MISSING_ACTIONS.md. Rival-run energy firms, oil/salmon fairs and club investors do not exist in the original (nothing to port).
- **Stage 2 connections:** de-duplicated stakes/big meeting, holding-routed sale proceeds, per-country loan rates and labour rules, abroad compliance, living rivals, event chains, misconduct and political decisions, cash-stress consequences (late interest, loan arrears/call, VAT overdue).
- **Stage 4 balance (this session):** capital-heavy trades fixed (courier equipment bug, farm fire cap, trade tuning); BalanceGuardTests green. Airline opens and survives (ROI about 4%, large first-year loss).
- **Left, all data/judgement not code:** (1) figures marked unverified in docs/TAX_SOURCES.md (MX corporate/IVA/IMSS, LT VAT, several 2026 minimum wages and notice/severance statutes); (2) Mexican severance is now much more expensive (12.9+ weeks) - check feel; (3) app icon, bundle id, signing, installable build (Apple/user); (4) `tools/parity_map.py` is stale vs the hand-edited parity docs; (5) the `engine-tests` CI job is now strict (pipefail), so a failing test turns CI red; (6) design pass per screen (Stage 3) is user-led.


Status words: **DONE** (logic works and was quick-checked), **PARTIAL** (works, listed gaps), **NOT STARTED**, **BLOCKED** (waits on the user or an outside thing).
"Different names": things that exist in code under another name are counted DONE/PARTIAL, not missing (see `MISSING_ACTIONS.md` for the exact missing ids).

Stages, in order: **1 Finish mechanics → 2 Connect all features → 3 Redesign UI (one screen at a time) → 4 Final testing, bug fixing and realistic balancing.**
No deep tests, no balancing and no screen design before their stage.

## Stage 1 — Finish mechanics

| Group | Status | What is left |
|---|---|---|
| Core: RNG, calendar, currency, 23 countries, taxes, VAT, loans, banking, net worth, ledger, saves and web-save import | DONE (unbuilt) | Verified against the original; 3 tax figures unsure (FI, LT, MX) → stage 4 |
| 50 service / venue / retail / production / logistics trades | DONE (unbuilt) | Balance → stage 4 |
| Project trades (6), rental (3), finance (3) | DONE (unbuilt) | Balance → stage 4. Reviews now shared system |
| Energy (2), salmon, holding company, football club | DONE (unbuilt) | Holding listing and share sales exist (batch 4) |
| Reports: weekly, monthly, yearly | DONE (unbuilt) | Year view also shows the personal income tax estimate for the year in progress (`GameEngine.yearInProgress`) |
| Managers, assistant managers, promotions, poaching | DONE (unbuilt) | Boards/CEO/MD/regional, targets and yearly budget (`ManagerTargets`), finance manager, profit bonus on hire, find-a-successor, `st28pro`. Left: see KNOWN_GAPS (seasonal-worker hiring by managers, a few promotion extras) |
| Strategic decisions, trophies, awards, rich list, selling a company | DONE (unbuilt) | All `ev27` decisions, trophies (incl. `TrophiesMore`), awards, rich list, share sales, funding rounds. Left: trophies n1, rk, no1, top10, team56 |
| Equipment market, premises choice, luxury, estates | DONE (unbuilt) | vdisc, premises extras, luxury extras exist and staff perks added. Left: see KNOWN_GAPS |
| Chains, franchises, branches, intercompany supply | DONE (unbuilt) | Supply-from-inside shield and sourcing hookups added (`Sourcing`). Left: rival supply |
| Customers and competition: reviews, key accounts, rivals, price wars, lawsuits, cyber, market map | DONE (unbuilt; engine, flat screens) | Analyst roles (mktan hired in a company, ana in the head office), rival price-fixing calls and fines, group poaching / supplier purchase / bids for your companies, ranking of the biggest companies (feeds awards), price-move forecasts, 6% manager price steps, manager picks IT level, tourist reviews, key accounts share a full shop with a trade profile, weight in the economy. Account supply links (buy an input from a business customer), what a bought rival becomes (merge, close, branch, franchise office), a new site beside a rival, a purchase paid with a loan from your own bank and the answers to a rival's price cut are in (`AccountSupply`, `RivalAbsorb`). Left: see KNOWN_GAPS (vendor choice, national financial players in the ranking) |
| Misc actions: rename, close/reopen, wind up, convert to limited, 3 switches | DONE (unbuilt; engine) | No screen trigger yet → stage 3 |
| Startups, private equity, stakes in other groups, IPO/listing, crisis centre, 13 decisions above | MERGED (engine; unbuilt) | Stale "not merged/not started" corrected from git history; remaining items are only those in KNOWN_GAPS |
| Boards, CEO, head office, meetings, academy, manager and chain gaps above | MERGED (engine; unbuilt) | Reference check on a head-office candidate and a one-manager review (`OfficeChecks`) added; minimal screens for the main office, meetings, courses and layoffs. Remaining items are only those in KNOWN_GAPS |
| Advisers, abroad, company insurance, suppliers, gifts, complaints, staff profile, weather/world, fleet/luxury leftovers | MERGED (engine; unbuilt) | Stale "not merged/not started" corrected from git history; remaining items are only those in KNOWN_GAPS |
| Real-life population, income and demand by city (luxury in LA vs small town) | MERGED (engine; unbuilt) | Stale "not merged/not started" corrected from git history; remaining items are only those in KNOWN_GAPS |
| 27 unowned actions: part-time/seasonal/hours staff types, discount campaigns, trial week, complaint handling, goals, development projects, lending a worker between chain stores | MERGED (engine; unbuilt) | Stale "not merged/not started" corrected from git history; remaining items are only those in KNOWN_GAPS |
| World around you: public image, contacts and favours network, maps screen; software products from your own startup | MERGED (engine; unbuilt) | Stale "not merged/not started" corrected from git history; remaining items are only those in KNOWN_GAPS |
| 27 "other" actions: part-time/seasonal/hours staff types and pay model, discount campaigns, trial week, complaint handling, daily goal / first-step rewards / ambitions, development projects, lending a worker between chain stores, own-car allowance, give up premises, change accountant | DONE (unbuilt; engine + flat app rows) | Ambition perks now applied to loan margin, abroad fees, quality, supply cost and rival prices (batch 4); market-share/world-rank facts exist; pay plan chosen at hire for sellers; screens pacct and registry are covered (Phone > Activity; presentation), month30, paper40 and wx56 stay engine-only read-only screens; tabs demandLevel and route are presentation; real screen design → stage 3 |
| Remaining trophies (need acquisitions, chains, startups, PE, luxury, R&D, listed holdings) | DONE (unbuilt) | Ported in `Trophies`/`TrophiesMore`; left only n1, rk, no1, top10, team56 |

Counts (original has 557 actions; from PARITY_CHECKLIST.md, refreshed after the last 50 actions were checked one by one): 306 engine + screen, 105 engine only, 146 presentation-only (no gameplay), 0 not ported. Screens (105): 92 engine + screen, 7 engine only, 6 presentation, 0 not ported. Company tabs (43): 28 engine + screen, 3 engine only, 12 presentation, 0 not ported. Nothing of this has been compiled yet (no Swift toolchain in the session that wrote the last 50 actions and their minimal screens): the first CI run decides.

## Stage 2 — Connect all features (NOT STARTED)

- **De-duplicate systems ported twice by parallel agents** (keep one, delete the other, repoint callers): big meeting and co-owner buy-back (`ManagerStakes.swift` vs `Events/BigMeeting` + `Events/Shareholders`; dividend policy key `dp27` is now only set via `Shareholders.setPolicy`, its quarterly payout must be checked); promotion talk (`ManagerPeople` vs boards agent version); any second review/market/rival code paths.

- DONE: country codes moved out of code into data (lint `CountryNeutralityTests` passes): `Countries/Resources/country_traits.json` (hemisphere, data-protection law, storm names, manager titles, paper names, group words, franchise brand origins; read via `CountryTraits` / `Country.traits`) and `Events/Resources/country_events.json` (country news items and which country each hand-written country decision belongs to; `CountryEvents`). Keep new country-specific content in these files, never in Swift.

- Wiring audit: every engine action is reachable from the game (engine API or Inbox decision); every weekly/monthly model is called from the turn; no orphan code; new weekly random streams do not disturb the main stream.
- Save format: version migration for all new state (reports, rivals, reviews, chains, luxury, equipment, decisions queue); old saves still load.
- ~~Scale the remaining reference-level money amounts per country (bank/insurer capital, premium bases, developer land price, default rental price, rental loss bookings, caretaker wage)~~ DONE: scaled with `Currency.scaledPrice` / the wage level, removed from the `MoneyLiteralLintTests` allow-list; RentalFinance, Project and SpecialTrades differential tests still pass. Trade-catalog traits (`capital`, `premium`, `price`) are still written at the reference level.
- Engine text formatting (no "£220 k", no NBSP) at the source.
- Refresh `PARITY_CHECKLIST.md` and `MISSING_ACTIONS.md` after each merge; refresh STATUS/KNOWN_GAPS.
- Full CI compile of everything merged since the last passing app build (CI last saw commit e7dc1b0: engine tests passed, app build had 2 errors that are fixed in later commits, later merges unbuilt on CI).

## Stage 3 — Redesign UI, one screen at a time (NOT STARTED)

**UI grouping rules (binding for Stage 3; never invent a tab because the HTML game had one):**
- **Management = one Team / People surface.** Store manager, assistant, regional, chain, chief and department head are rows in one list with a role + scope badge (store | chain | region | group). No tab or root screen called Assistant, Regional, Chief or Managers-vs-Assistants. Hire, promote, fire and pay are sheets or rows on that list, not sibling tabs. Distinct engine role ids still show as one list.
- **Status (unbuilt, no Swift toolchain in the cloud session):** company section is now "Team"; `CompanyTeamRoster` lists MD, department heads and regional manager (role + scope badge, search/hire/authority/let go) under the manager and assistant cards. Still to do: fold manager/assistant cards into the same list; chain/group posts now have rows too (`ExecutivePosts`: group MD on Group, chain CEO / chain manager / regional managers in the company's Chain section; unbuilt).
- **Group = ownership and structure only** (chains, franchises, boards, stakes). A region chief or chain manager lives under Group, in that chain's people (or links into Team with scope=chain). No parallel "Regional managers" area.
- When unsure: people go under Team, structure goes under Group. No third place.
- **Navigation status (unbuilt):** tabs are Company (home summary + company list), Team (one cross-company people list, scope filter), Group (holdings, chains, ExecutivePosts, Money as a section), Projects (company projects/tenders + ventures), Inbox; former Phone pages are a sheet behind the "More" toolbar button on Company and Group.

Current screens are **first versions**, functional only. Ivory Ledger style is chosen (`design/STYLE_IVORY_LEDGER.md`); other four styles are kept in `design/mockups` for later purchase.
- Designed and shipped in Ivory Ledger (first pass, to be reviewed): Home, Group, company overview, Bank, Money overview, Settings, Inbox, Start.
- First-version, undesigned: company sections (Projects, Properties, Book, Plant, Fish, Holding, Club, Chain, Franchise, Customers, Market, Equipment, Team/manager), Reports, Achievements, Rich list, Luxury, market/reviews/rivals, franchise brands, sale.
- Screens that do not exist yet: none are "not ported" any more. Four read-only screens (monthly results, your rival, the business paper, weather and tourists) and the tabs abroad, advisers and insurance have engine logic but no native screen; the Group tab now has a minimal Main office and People you buy from section, Company > Team has warnings, courses and layoffs, and Company > Market > rival has the purchase choices and the price-cut answers (all first versions).
- Each screen with more than one or two choices gets its own design pass with you.

## Stage 4 — Final testing, bug fixing, realistic balancing (NOT STARTED / BLOCKED)

- BLOCKED until you confirm: balance retune (capital-heavy trades were tuned before the rent fix; kiosk 51%, hardware 62%, grocery 40%, carrepair 44%, shipping 36%; new trades too profitable: salmon 86%, fund 197%, electrician 40%; finance trades lose money early; courier cash −9–15%).
- Full engine test suite (126+ tests; 1 known failure: kiosk return) and deep probes; compare the other 42 trades with the original; gym/restaurant realism flags.
- Demand realism check across all 23 countries once the population/demand branch is merged.
- iPad screenshot tour failure (deferred, iPhone first); iPhone screenshot review of all new screens.
- Tax: confirm FI, LT, MX figures.
- BLOCKED on you / Apple: app icon, bundle id, signing, installable build.


## Stage 1 batch 3 (engine only; nothing compiled, no Swift toolchain in the cloud session)
- DONE (unbuilt): finance manager and which holdings it covers (`FinanceManager.swift`); manager targets and yearly budget (`ManagerTargets.swift`, hooks in Demand, QualityModel, GameEngine); staff perks, hosting a rival, lending luxury (`StaffPerks.swift`); nemesis, Top 50, staff stories (`Stories.swift`); sourcing repair-discount hookup and supply-from-inside shield (`Sourcing.swift`); business-customer volume contracts (`VolumeContracts.swift`, receivables, default/cancel risk).
- Already existed, map was stale: board deal vote, move office, supplier variety/concentration/fix, vdisc, layoffs, yacht dinner, fame/jet/serious-buyer luxury extras.
- Left out: volume tenders for services/shops/carriers, successor-search shortcut, promoting juniors (`st28pro`), managed-holding skill in funding raises, platform fees/memberships/peak seasons, quality-promise cost uplift.
- Next: build and run `swift test` on a Mac; fix compile errors from this batch first.

## Stage 1 batch 4 (engine only; unbuilt)
- DONE (unbuilt): volume tenders for 24 service/shop/carrier trades (`VolumeTenders.swift`, one port kept after two parallel ones); ways to sell money side (`SalesWays.swift`: platform commission, memberships, referrals, call-out, add-ons, peak-season warning); quality-promise 3% cost uplift; 20 more trophies + chain/franchise ladders (`TrophiesMore.swift`); ambition perks on loan margin, quality, supply cost, rival prices, abroad fee, market-share/world-rank facts; finance-manager skill in funding raises; `st28pro`; find-a-successor (`ManagerModel.findSuccessor`); manager hire with profit bonus (removed duplicate bonus payout in ChainHierarchy).
- Corrected as stale: all `ev27` strategic decisions exist; rival energy firms, oil/salmon fairs, club investors and football PRO gating do not exist in the original (nothing to port); holding listing/share sales exist.
- Left out: trophies n1, rk, no1, top10 (need market/country rank data), team56 (can now use `teamSlots`); seasonal-worker hiring by managers; farm, factory and furniture tenders; bank-deposit-share ambition milestone; dominator perk keeps price paid unchanged (original raises it; looks like a bug).
- Risks to check on a Mac: new weekly random draws (tenders) may move golden tests; `resign()` now posts an ask message (check the Inbox UI handles it); all of batches 3-4 are uncompiled.

## Stage 1-2 waves 5-6 (engine + navigation; ALL UNBUILT, no Swift toolchain in the cloud session)
- DONE (unbuilt): financial fixes (resale loss booked, unpaid-bills bankruptcy path, repay from savings, late interest on bills, supplier cash-only/stop-orders, loan arrears/freeze/call/bankruptcy, VAT overdue penalty, landlord rent timing, per-country loan rate); demand fixes (southern seasons, inflation hold, no instant rival respawn); living rivals (strategy, fortune, exit, delayed entrant, expansion, hiring pressure, strength in demand, rate factor for rate-sensitive trades); de-duplicated buy-back/big meeting (ManagerStakes deleted), holding-routed sale proceeds, same-country dealer plant; abroad compliance fines; 12 event chains (`Aftermath`); misconduct + political influence decisions (`Misconduct`); seasonal hiring; leased-vehicle upkeep fix; navigation Company/Team/Group/Projects/Inbox.
- Verified by trace as already correct: revenue vs receivables vs cash, payroll/tax accrual, depreciation, double entry, lease rates (match original), stockouts (original has no extra penalty), opening-hours trait (unused in original).
- Left: board seats/stakes have no standalone Group view; iPad company table; policy rate on consumer demand only for rate-sensitive trades; FX on repatriation (not in original); minimum wage/hours/income tax traced in the tax-country pass (data has no statutory minimum wage, see TAX_SOURCES; owner-salary withholding, severance and VAT/corporate tax now follow the company's own country, `CompanyCountryRulesTests`); airline lease economics follow the original (balance question for stage 4).
- MUST DO on a Mac: build, `swift test`, fix compile errors, re-baseline golden tests (random streams changed by removing duplicate big-meeting weekly, tenders, rivals), then UI polish and balance (stage 4).

## RESOLVED: toolchain (Swift 6.0.3 installed at /opt/swift in the cloud session after the network allowlist change)
- No Swift toolchain on the cloud host and the sandbox proxy denies swift.org (403). Needs the user to add `download.swift.org` / `swift.org` under Allowed domains (cloud environment settings > Network access), or to run on a Mac: `cd native/Engine && swift test`, then build the app in Xcode (needs Swift 5.10+; `nonisolated(unsafe)` is used).
- Until then every Swift change from the web session is unbuilt: only hand-compiled by reviewer passes.

## UI pass (23 Oct 2026): six category agents + final audit, all merged
- Verified on CI (macOS app-build, engine tests, iPhone / iPad / iOS 26 screenshot tours all green on the merged branch): navigation shell (shared route destinations, More menu, sidebar, start screen with real save summary, game-over run summary), Company (finances as Summary/Accounts/Loans/Owners/Settings, overview leads with what needs you, staff roster and profile, company lifecycle in Settings), Group (structure, chain pages, boards, head office), Team (needs-you / posts to fill / manager performance, one management list, shared candidate-hire component), Money and projects (bank terms, ventures workflows, acquisitions, expand abroad, software), Inbox and phone (urgency groups, consequences before answering, transactions and bills reports, weather and paper), final consistency audit (iPad toolbar leak, money text, plurals, one authority picker, one hire row).
- Rules for all screen work: docs/DESIGN_RULES.md. Screen inventory and status: docs/SCREEN_MIGRATION_INVENTORY.md (counts there predate this pass).
- CI: engine tests run as a release build on macos-15 (the debug balance probe grew until the runner killed the process; the probe now drains an autorelease pool per day); app-build runs in parallel with engine-tests.
- Left: Back from a Projects/Inbox/Home company link returns to the Company list, not the originating tab; payroll mode and insurance screens; dead views (MoneyView, GroupSummary, HireOptionsMenu, CompanyFranchise, Ring, MiniBars, ScreenHeader, AmbientLight) DONE: deleted, with the unused engine actions, the second first-steps tracker and the envelope migration step (see audit/reachability.md); engine-written message text can show "£11 k" (Currency.short format is pinned by golden tests); money overview 'Cash available' is a different quantity from Home 'Cash'; balancing deliberately not done (car dealer structural loss, high seed variance in several trades; see BALANCE_REPORT).
