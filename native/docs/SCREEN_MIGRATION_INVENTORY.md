# Screen migration inventory (original HTML game -> native SwiftUI)

Read-only audit of commit `a8f6298` (native-swiftui), 23 Oct 2026. Original source: `Game.zip` -> `Ledger/source/src/js` (screens registry `V`,
`ui/core/base.js:17`; router `go()` base.js:368). Native: `native/App/Ledger` (71 Swift files), engine `native/Engine`.
Four passes, each checked in source; anything only checked by name/grep is marked UNVERIFIED in the tables. No code was changed by the audit.
Note: section 3 describes the app as audited; the Team tab, section deep links, holding roster and Inbox links were changed right after (see MASTER_CHECKLIST).

Category key: **A** generic reusable template (list/detail/form/confirm sheet/KPI+rows), **B** reusable specialist template (hiring flow, board/meeting,
market/rival cards, finance book, catalogue), **C** individually designed special screen, **D** verified obsolete/duplicate (evidence cited;
"missing from native" is never D). Status: Done / Partial / Missing / Unreachable (engine exists, no route).

> **Status note (23 Oct 2026):** the Done/Partial/Missing counts below predate the UI pass. What is still to do, and why, is tracked in `IMPLEMENTATION_ROADMAP.md`; what has been tried by hand is in `HANDS_ON_TEST_PLAN.md`. This file stays the screen inventory; update its status columns only.

## Summary

| | Rows | A | B | C | D | Done | Partial | Missing | Unreachable | n/a |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Main, phone and feature screens (section 1) | 115 | 71 | 29 | 11 | 4 | 69 | 32 | 13 | 0 | 1 |
| Company tabs, sub-pages and family pages (section 2) | 71 | 48 | 12 | 7 | 4 | 31 | 25 | 7 | 4 | 4 |
| **Total** | **186** | **119** | **41** | **18** | **8** | **100** | **57** | **20** | **4** | **5** |

D (8, with evidence): `mkt36` alias of `V.market()`; `registry` phone app never routed; `pickco` only self-referenced; `hubs.js` title stub
overwritten; OPS `biz` page never routed; old `money.js` owner/books/tx bodies overridden by `R6FIN`; old instant-offers sell branch replaced by
`R7DEAL.sell`; DEAL_SUB value/sell/close duplicate FIN_SUB.

Actions (557 original ids, verified by grep + headless run of the original): 339 covered with UI, 7 covered but partial, 46 engine-only (no UI),
147 presentation-only, 7 not ported, 11 out of scope (Ledger Pro store, skins). Content ids not missing: events 133, country events 29,
strategic decisions 36, trophies 106, ambition milestones 63, luxury 45, documents 77, roles 97, trades 67, countries 23. Missing ids:
23 of 34 marketing channels (prime-time TV per country), tender trades `cons`/`farm`, 4 of 5 life stories.

## Major gaps

1. **Reachability:** engine actions with no screen: close/reopen/wind up/rename/convert a company, rename chain, owner salary, credit check,
   auto stock, inflation hold, insurance and advisers, expand abroad, giving back/foundation, own software product, payroll mode/run, sale talk,
   permit applications (46 engine-only ids).
2. **Partial company pages:** accounts lack balance sheet, cash flow and tax tabs; loans fixed 60-month term without repay sheet; no staff profile
   page; hiring without candidate detail, worker reference check or wage negotiation; setup checklist rows not actionable; campaign planner without
   length/age targeting; how-you-sell changeover is a field write (no cost, capacity penalty or document check).
3. **Missing original systems:** trade unlocks and life stories (all 67 trades open on day one), prime-time TV channels (engine code dead),
   deal of the week, manager focus plans, pay-day change, crisis centre, org chart, payroll and bills page, transactions list, sell unpaid
   invoices, brand reach, personal rival (nem28/riv31) screen, business paper, weather and tourists screens, game-over run summary, save slots,
   start screen age/city/story.
4. **Silent/dead UI:** ~24 buttons drop the engine's result or refusal; "Team →" insight link uses `CompanySection(rawValue: "Staff")` (raw value is
   "Team") so it never renders; "Found: sector" button has identical branches; 2 unreachable views (`MoneyView`, `EmpireCard`).
5. **Duplicate logic:** dismissal (`Hiring.fire` used, `StaffProfile.dismiss` with warnings/unfair-dismissal rules unreachable); severance booking
   copied in Hiring and ManagerPeople; `Satisfaction.answerComplaint` dead copy of `Complaints.answer`; four copies of the lunch/meeting rule;
   executive-search fee defined three times; candidate-hire list re-implemented ~7 times in the app, authority picker 3 times, ~30 hand-written
   confirmation dialogs.
6. **Pipeline order** differs from the original (month/year end after chains, ventures, rivals) with no differential test; effect unverified.

## Recommended implementation order

1. Route the 46 engine-only actions that are gameplay (company lifecycle, insurance/advisers, abroad, owner salary, payroll, permits) into their
   one home screen; fix the silent buttons and the "Team →" link. Engine already exists, lowest risk, biggest reachability gain.
2. Unify duplicates before building on them: one dismissal path (route `Hiring.fire` through the `StaffProfile.dismiss` rules), one severance
   booking, one candidate-hire template, one confirm sheet, one authority picker (templates A/B used by the rest).
3. Complete the Partial company pages (accounts tabs, loans, staff profile, hiring detail, setup checklist, campaign planner, how-you-sell).
4. Port the missing systems in gameplay order: trade unlocks + life stories, prime-time TV, manager focus plans, pay-day change, crisis centre,
   payroll/bills and transactions pages, deal of the week, tenders `cons`/`farm`, org chart, personal rival, paper/weather screens.
5. Add a differential test for month/year-end ordering, then the C screens' design pass (home, company overview, start, game over, maps).

## 1. Original main, phone and feature screens

### How the original routes screens (checked in source)
- Registry = the object `V` (ui/core/base.js:17). A screen is `V.<id> = function(p)`; title in `V.titles.<id>`, header in `V.heads.<id>`. Later files wrap an earlier screen with `pipeView('V.x', V.x, n)` + `addStep` (documented in STRUCTURE.txt "RULES" 3); such wrappers are NOT extra screens. Load order: src/manifest.txt.
- Navigation: `go(n,p)` (base.js:368) -> `ALIAS` (base.js:289: office/group/dealroom -> hq tab; world/worldhub -> news), `PHONE_APPS` (base.js:296, phone stack `phoneGo`), `ROOT` main tabs home/cos/hq/meet (base.js:265), else pushes on `ui.stack` with section from `SEC_OF` (base.js:267). Actions are `ACT.<id>` (data-a="..."). Sheets/pop-ups via `openSheet`.
- Main tabs `SECS` (base.js:263): Home, Companies, Group(hq), Phone, Inbox(meetings). Phone grid `PHAPPS` (mockup.js:179 + private_equity.js:140 + pro.js:136).
- `render()` (base.js:547) picks `V.menu` (saves.js:102) if `ui.menu`, else `V.start` if no game, `V.over` if `S.over`, else the shell.
- ~100 distinct registry ids; 115 rows below (embedded panels and company sub-pages are listed because each has its own title/data/actions; a few rows group closely related ids).
- Native shell: 5 tabs Company/Team/Group/Projects/Inbox (Core/GameStore.swift:14, Features/Root/RootView.swift:68) plus a "More" sheet (Features/Phone/PhoneView.swift) with 9 destinations (GameStore.swift:22). No router for arbitrary ids; deep links via `store.openCompanyID/moneySection/phoneDestination/companySection`.

Category key: A generic template, B specialist template, C individually designed, D verified obsolete/duplicate. Status: Done / Partial / Missing / Unreachable.

### Table

| # | id | file:line | purpose | required data | actions (ACT.*) | deps | cat | native counterpart | status | missing functionality |
|---|----|-----------|---------|---------------|-----------------|------|-----|--------------------|--------|-----------------------|
| 1 | start | ui/screens/start.js:48 | New-game setup: name, age, country, city, story; pro-locked countries | S null; CO/country data; PRO | startgame, setcountry, age56, ccsheet, citysheet, storysheet, loadfile, menuback, sheetclose | menu, pro59 | C | Features/Start/StartView.swift | Partial | No age, city, story/background choice; no pro-locked-country sheet (GameStore.swift:100 newGame takes only name+country). Has import-from-web-save (not in original). |
| 2 | menu | features/player/saves.js:102 | Main menu: continue, multiple save slots, load file, new game, Ledger Pro | R56saves slots, S.over, S.player | menucont, menuload, menunew, loadfile, prostore | start, home | C | StartView.swift (Continue/New game/import) | Partial | Single save only (no slot list/load slot; `slot` grep hits only unrelated code); no Pro button. |
| 3 | over | ui/screens/mockup.js:366 | Game over summary + focus plan / new game | S.over, cos, npcs, stats, inbox, lastRep | focusplan, newgame | start | C | Features/Root/GameOverView.swift | Partial | Only reason + week + peak net worth; no run summary/stats/"focus plan". |
| 4 | home | ui/screens/mockup.js:139 (wraps: sales/daily_sales.js:331, tidier_screens_and_monthly_bills.js:148 popups) | Dashboard: net worth, cash, companies, advance day/week, suggestions, goals | S.cash, cos, hist, player, country | nextday, untilneeded, paysrc56, phapp, tab, go, prostore | bank, cos, invest, newbiz, stats, fs58, amb27, give28 cards | C | Features/Home/HomeView.swift (+FirstStepsCard, GoalsCard, SuggestionCard, ComingUpCard) | Done | Pop-ups-on-Home (problems, "show when used" gating) not replicated: UNVERIFIED how alerts surface (Inbox decisions instead). |
| 5 | phonehome | ui/screens/mockup.js:180 | Phone app grid | PHAPPS, SEEN57 | phapp | all phone apps | A | Features/Phone/PhoneView.swift ("More" list) | Done | Different structure (list of 9 rows); "show when used" gating (show_when_used.js) not ported. |
| 6 | cos | ui/screens/companies_list.js:60 | Companies list (filter, sold) | S.cos, founded | cofilter, cosold, go | newbiz, holdings, found36 | A | Features/Companies/CompaniesView.swift | Done | Sold/closed filter: UNVERIFIED. |
| 7 | newbiz | ui/screens/companies_list.js:135 | Choose a trade / category | BD, S.chains, country | setcat, proask, go | newco, franchises, found36 | A | Features/Phone/NewCompanyView.swift (Choose a trade) | Done | Pro-gating (proask) absent. |
| 8 | newco | ui/screens/companies_list.js:177 (wrap hiring_place_swipe_luxury.js:44) | New-company form: city, legal form, size, premises, brand/franchise, start cost | S.cash, loans, country, fbApps, ui.nc | ncgo, brandpick, brandopen, brandapply, branduse | franchises, brandneg, co | A | NewCompanyView.swift (TradeDetailView) | Partial | Share-capital/limited-form step covered; premises choice at setup and swipe-card place picker (hiring_place_swipe_luxury) UNVERIFIED. |
| 9 | brandneg | ui/screens/companies_list.js:398 | Franchise meeting with a brand (negotiate terms) | S.fbApps, week | negstep, negsend, negsign, brandfacts | newco | B | Features/Companies/FranchiseBrandsView.swift (BrandMeetingView) | Done | - |
| 10 | franchises | ui/screens/companies_list.js:503 | Brands looking for franchisees (join) | S.fbApps | brandapply, brandopen, brandstart | newco | A | FranchiseBrandsView.swift (FranchisesView, StartFranchisedView) | Done | - |
| 11 | fr56 | ui/screens/group_tab.js:75 | Group: your franchise brands, units, join a brand | frBrands(), canFranchise | (go) | franchises, co deal/grow | A | Companies/CompanyFranchise.swift (FranchisorCard) + ChainsGroupSection | Partial | No dedicated Group page; surfaced per company/chain section. |
| 12 | frtalk56 | features/company/franchise_talks.js:76 | Talk with a franchise applicant | applicant state | frt56ed, frt56go, back | fr56 | B | CompanyFranchise.swift (FranchiseTalkView) | Done | - |
| 13 | found36 | features/screens/fewer_places.js:92 -> foundedPage (features/player/selling_startups_and_crisis.js:377) | "Your startups" list | S.founded | (see foundedPage) | cos, newbiz | A | Features/Phone/VenturesView.swift (startups) | Partial | UNVERIFIED: VenturesContent lists startups to invest in / Big meeting; player's own founded startups page not confirmed. |
| 14 | holdings | features/world/rivals_holdings_software.js:295 | List holding companies | S.cos type hold | go | newhold, co | A | GroupView.swift ("Holding companies" section) | Done | - |
| 15 | newhold | features/world/rivals_holdings_software.js:302 | New holding company (pick companies, publish) | S.cash, cos, pool | nhco, nhgo, nhpub | holdings | A | CompanyHolding.swift (NewHoldingView) | Done | "nhpub" (publish/list) UNVERIFIED. |
| 16 | co | ui/company/view.js:136 (wraps: rivals_holdings_software.js:335, newcomer_premises_one_line.js:112) | Company page with tabs Overview / Clients / Staff / Money / More; route() maps legacy t/s | getCo(p.id), BD, co.mgr, group | cotab, codeal, cofin, cosub, autoset, promoboss, promogo | co sub-pages 17-37 | C | Companies/CompanyDetailView.swift (SectionTabs) | Partial | See sub-pages; native tab set differs (Overview/Team/Finances/Operations/Marketing/Customers/Market/Setup + family sections). |
| 17 | co:ov (CT.ov) | ui/company/view.js route default | Company overview KPIs/alerts (DASH56 company_dashboards.js) | co books, alerts | opendec, autoset | co | C | CompanyDetailView.swift (CompanyOverview) | Done | - |
| 18 | co:cli (salesTab) | ui/company/view.js:route 'cli' | Sales tab: marketing, prices, customers, rivals | co demand, prices | setmkt, pm16camp | cust, rivals, prices | A | CompanyMarketing.swift, CompanyCustomers.swift, CompanyMarket.swift | Partial | Prices sub-page: price-change/discounts in CompanyMarket; UNVERIFIED parity of every price control. |
| 19 | co:st (staffTab) | ui/company/view.js route 'st'; ui/company/people.js | Staff: workers, manager banner, hire entry | co.staff, npcs | cotab, askmgr, oa59meet, hirego | hire, mgrhire | A | CompanyTeam.swift, CompanyTeamRoster.swift, TeamView.swift | Done | - |
| 20 | co:money (moneyTab) | ui/company/view.js route 'money'; ui/company/money.js | Money tab list of fin pages | co books | cofin | fin pages 28-32 | A | CompanyMoney.swift | Done | - |
| 21 | co:more (companyTab) | ui/company/view.js:107 | Company "Manage" list: supply, assets, expand, boards, docs, insurance, close | OPS_SUB/DEAL_SUB | cosub, codeal, cofin | ops/deal pages | A | CompanyOperations.swift / CompanySetupSection | Partial | No Close down / documents / insurance rows (see 26-27, 34). |
| 22 | ops:people | ui/company/view.js:276 (people.js) | People and manager page | co.mgr, staff | mgr actions | hqhire, mgrhire | B | CompanyManagement.swift, CompanyTeam.swift | Done | - |
| 23 | ops:assets | ui/company/view.js:277 (assets.js) | Premises and equipment, fleet, shop | co.eq, premises | buyeq etc | shop | A | CompanyEquipment.swift (CompanyEquipmentScreen) | Done | - |
| 24 | ops:marketing / prices | ui/company/view.js:278-279 | Marketing; Prices | co.mkt, prices | setmkt | co:cli | A | CompanyMarketing.swift / CompanyMarket.swift | Done | - |
| 25 | ops:time/upkeep/choices/special/biz | ui/company/view.js:280-287 | Staffing and owner time; stock/upkeep; business choices; special | co.flags, owner hours | opssub setters | - | A | CompanyOperations.swift, CompanyOtherSections.swift, CompanyLabourCard.swift | Partial | "Special" per-trade choices UNVERIFIED; stock policy lean/normal/safe: UNVERIFIED. |
| 26 | ops:ins | ui/company/view.js:284 | Company insurance products | co.ins | insurance acts | - | A | none (insurance only for insurer book / cyber) | Missing | No screen to buy/choose company insurance (CompanyFinanceBook/CompanyCustomers mention insurance only for fin family and cyber). |
| 27 | ops:docs | ui/company/view.js:285 | Documents and permits (docNeeds/docOk, applydoc) | co docs | applydoc | registry | A | partly CompanySetupSection ("Before opening") | Partial | After-opening permit/document page absent (grep "Documents|permit" only in NewCompany/Franchise views). |
| 28 | fin:books | ui/company/money.js:7 | Accounts: balance, P&L week/month/year/last year | co.books | books, ccheck | res36 | A | CompanyMoney.swift + PnLTable (Reports) | Done | - |
| 29 | fin:value / sell | ui/company/money.js:8-9 (deals.js:6) | Ownership & value; sell company or shares | companyValue, offers | sellco, sale* | sale, saletalk | A | CompanyOwnership.swift, CompanySaleSection.swift | Done | - |
| 30 | fin:owner | ui/company/money.js:10 | Move money / owner salary | cash, loans | cinject, cofin, cosub | payself | A | CompanyMoney.swift (Move money) | Done | - |
| 31 | fin:loans / legal | ui/company/money.js:11-12 | Loans; accountant and legal form | loans, co.form | loan acts, convert | bank | A | CompanyMoney.swift (Borrow), CompanyOtherSections.swift (accountant) | Partial | Convert to limited form: engine only per MASTER_CHECKLIST "no screen trigger" (grep "Convert to" only in NewCompanyView). |
| 32 | fin:tx / close | ui/company/money.js:13-14 | Transactions list; Close down | co.log | cofin s=close | res36 | A | none for close; transactions only as Activity (personal) | Missing | No close down / wind up / reopen / rename UI (MASTER_CHECKLIST: "no screen trigger yet"); no per-company transaction list. |
| 33 | deal:supply | ui/company/deals.js:8 | Suppliers (+ own-group supply chain) | co.sup, agree | vmeet, ch27k | chain27 | A | CompanySourcing.swift, CompanyChain.swift (CompanySupply) | Done | - |
| 34 | deal:cust / rivals / reach / insight | ui/company/deals.js:9,12,11,15 | Business customers; competitors; chain & reach; insight analytics | key accounts, rivals | acctmeet, acctdrop | rival, market | A | CompanyCustomers.swift, CompanyMarket.swift, CompanyChain.swift | Partial | "Insight and analytics" page: KNOWN_GAPS says no marketing analytics screen. |
| 35 | deal:grow / sell | ui/company/deals.js:10,13 | Expand (branch, chain, franchise, abroad); sell | co | codeal grow | store13, chain12, branch | A | CompanyChain.swift (GrowIntoChain), CompanyFranchise.swift | Partial | Abroad expansion screen UNVERIFIED. |
| 36 | mgmt56 | ui/company/headquarters.js:116 | Company HQ: overview/manager/assistant/team | co.mgr, asst, TEAM56 | hq56t | hqmk, mgrhire | B | CompanyManagement.swift + CompanyTeamRoster.swift | Done | Merged into Team per MASTER_CHECKLIST grouping rules. |
| 37 | hqmk | ui/screens/group.js:125 | Main-office team screen (desks, paperwork) | office, npcs | hqas, hqtick, plopen | office | B | Companies/GroupOffice.swift (HeadOfficeSection) | Done | - |
| 38 | hq | ui/screens/group_tab.js:96 | Group tab: You / Group / Main office pages | OLD alias map | hqtab | group, office, 20+ rows | C | Companies/GroupView.swift | Partial | Native Group = Holdings + Money only; "You" page (people, image, trophies, awards, giving) lives in More sheet. |
| 39 | group | ui/screens/group.js:9 | Management structure per company (embedded in hq) | group.ceo/regional, npcs | fireceo, fireregional | mgmt56 | A | ExecutivePosts.swift | Done | - |
| 40 | office | ui/screens/group.js:95 | Main office (hire desks, rent, right hand) | office | hirehq, officepop | hqhire, hqmk | B | GroupOffice.swift | Done | - |
| 41 | hqhire | ui/screens/hiring.js:219 | Hire for main office (search, candidate, offer) | netCD, npcs | hqsearch, hqcandopen, hqoffer, hqstep56 | office | B | GroupOffice.swift (search/Offer/Check references) | Done | - |
| 42 | hire | ui/screens/hiring.js:49 | Find workers flow (terms, candidates, references, offer) | npcs, netCD | hsearch, hrole, candopen, candpass, offer7, hstep56, hk54s | co:st | B | CompanyTeam.swift (Find workers) + HireOptionsMenu | Partial | Multi-step flow collapsed into one list; reference check on workers UNVERIFIED. |
| 43 | mgrhire | ui/screens/hiring.js:132 | Management hire (any role: shortlist, ask, refs, offer) | cash, npcs | mgrask, mgrref, moffer56, mstep56 | hqhire | B | CompanyManagement.swift, ExecutivePosts.swift | Done | - |
| 44 | managers | ui/screens/review.js:13 | Manager reviews/scorecards (embedded in hq grp) | cos, npcs, office | reviewnow, reviewall | office | A | GroupOffice.swift ("Manager reviews") | Done | - |
| 45 | suppliers | ui/screens/group.js:42 | Group suppliers (deals every company buys through) | S.agree, vr | vmeet | deal:supply | A | GroupOffice.swift (SuppliersGroupSection) | Done | - |
| 46 | dealroom | ui/screens/group.js:180 | Deal room: hold in/out, inject, new holding | cos | holdin, holdout, injhold, newhold | holdings | A | CompanyHolding.swift / HostingSection (MoneyPeopleActions.swift) | Partial | UNVERIFIED parity of holdin/holdout/injhold. |
| 47 | boards12 | features/company/shelf_stock_chains_boards.js:425 | Boards list: seats, right hand, emergency | S.chains boards | lh12fire, price, stock | board12, bmeet12 | B | GroupBoards.swift (BoardsGroupSection) | Done | - |
| 48 | board12 | features/company/shelf_stock_chains_boards.js:392 | One board | cash, npcs | - | boards12 | B | GroupBoards.swift | Done | - |
| 49 | bmeet12 | features/company/shelf_stock_chains_boards.js:550 | Board meeting: vote, emergency | S.pend, inbox | bd12yes, bd12no, emg12, emg12pick, emg37 | board12 | B | GroupBoards.swift (What the board says) + Inbox decisions | Partial | Emergency (emg12/emg37) flow via inbox: UNVERIFIED. |
| 50 | chain12 | features/company/shelf_stock_chains_boards.js:186 | Chain page: stores, rules, lend, hire | S.chains, lh | ch12rule, ch12join, ch12lend, ch12fire | store13 | B | CompanyChain.swift (ChainOverview, StoreRules) | Done | - |
| 51 | store13 | features/company/chain_registration_and_boards.js:56 | Open a new store in a chain | cash, country, group | ns13go, ch12new, bd13find | chain12 | A | CompanyChain.swift ("New store") | Done | - |
| 52 | chain27 | features/company/intercompany_supply.js:178 (wrap small_team_and_rewards.js:302) | Supply chain between own companies | S.l27 | ch27set, ch27off, ch27k | deal:supply | A | CompanyChain.swift (CompanySupply) | Done | - |
| 53 | org56 | features/company/org_chart.js:131 | Organisation chart | S.chains, group, npcs | go | chain12, boards12 | A | none | Missing | No org chart (grep OrgChart/Organisation: none). Roles are in Team list per grouping rules. |
| 54 | own27 | features/company/owner_investors.js:265 | Co-owners/investors: buy-out, policy | S.cash, npcs | own27buy, own27pol | co | A | CompanyOwnership.swift | Partial | Dividend policy and shareholders present; buy-back (own27buy) UNVERIFIED. |
| 55 | payroll29 | features/company/payday.js:403 | Payroll and bills (approve run, mode) | npcs, co.pay | pr29run, pr29ok, pr29mode | payself, res36 | A | none (auto-payroll toggle in SettingsView) | Missing | No payroll approval/bills screen; only policy switch "Approve routine payroll for me". |
| 56 | payself | features/sales/realistic_odds.js:152 (wrap payday.js:518) | Pay yourself / owner salary | cos, loans | cinject, cofin, cosub, primary | co | A | CompanyMoney.swift (Move money) | Partial | Salary-setting UI UNVERIFIED. |
| 57 | shop | features/company/realistic_buying.js:742 (wrap rivals_holdings_software.js:506) | Equipment/vehicle/software shop | S.econ, npcs | shopbuy, shopq, shopsel, shopvc, shopcls, ownsw | ops:assets | A | CompanyEquipment.swift (EquipmentShopView) | Done | Own software (ownsw) UNVERIFIED. |
| 58 | sale | features/player/selling_startups_and_crisis.js:38 (wrap rivals_holdings_software.js:200) | Sell or raise money: offers, broker, funding rounds, pitch | S.sales, fundOffers, deferred | salemode, saleacc/dec/ctr, pitch, fundacc/dec/ctr, salewd | saletalk | B | CompanySaleSection.swift, CompanyOwnership.swift (pitchToInvestors) | Done | Deferred payments UNVERIFIED. |
| 59 | saletalk | features/world/rivals_holdings_software.js:210 (wrap salary_talks.js:42) | Haggle with a buyer (chat) | S.sales, office | saleq, salecounter, saleacc, saledec7 | sale | B | CompanySaleSection.swift ("Counter +8%") | Partial | Chat-style talk reduced to one counter button. |
| 60 | bigmeet | features/player/selling_startups_and_crisis.js:394 | Big meeting: stakes/offers, accept/counter/walk | S.bigOff, loans | bigacc, bigctr, bigwalk | meetings | B | VenturesView.swift ("Big meeting") + GroupBoards.swift | Done | - |
| 61 | crisis | features/player/selling_startups_and_crisis.js:634 | Crisis centre (distress options, forced sale) | S.over, week | msgpick | sale | B | none (grep: engine VentureActions only) | Missing | No crisis centre screen. |
| 62 | staffman | features/player/selling_startups_and_crisis.js:474 (wrap staff_stories_and_nemesis.js:130) | Staff member profile: course, raise, warn, fire, logo | npcs, seed | coursesheet, doraise, firestaff, warnstaff, logo | academy | A | CompanyTeam.swift, CompanyOtherSections.swift (StaffContractMenu) | Partial | Profile stories/nemesis lines UNVERIFIED; "logo" absent. |
| 63 | academy | features/screens/restyled_screens.js:149 | Academy: courses for staff | cos, npcs | acads, acadc, acadco, docourse | staffman | A | CompanyTeam.swift (sendOnCourse) | Done | - |
| 64 | pr11 | features/people/worker_roles_and_promotions.js:422 | Promotion overview | week | p11talk, go | anrep11, p11talk | B | CompanyManagement.swift (PromotionSheet) | Done | - |
| 65 | p11talk | features/people/worker_roles_and_promotions.js:448 | Promotion talk (role, duty, offer) | cos, npcs, office | p11offer, p11set, p11duty, p11back | pr11 | B | PromotionSheet in CompanyManagement.swift | Done | - |
| 66 | anrep11 | features/people/worker_roles_and_promotions.js:616 | Analyst report (find manager, tab) | cos, group | mfind11 | pr11 | A | DataAnalystCard (Phone/WorldView.swift) | Partial | Report screen not ported as such; analyst ranges shown in market views. |
| 67 | tg58 | features/people/targets_and_budgets.js:332 | Manager targets and budget | npcs | tg58go | mgmt56 | A | CompanyPeopleActions.swift (CompanyTargetsCard) | Done | - |
| 68 | pk58 | features/people/perks_and_hosting.js:139 | Perks, hosting, lending a piece | cos, sales | pk58hgo, pk58host, pk58lend, pk58lgo, pk58t, phapp | lux | A | CompanyPeopleActions.swift (CompanyPerksCard), MoneyPeopleActions.swift (HostingSection, LendPieceSection) | Done | - |
| 69 | meet | features/people/manager_search_and_meetings.js:131 | Call a meeting (group/manager meetings, proposals) | inbox, npcs | mprop, mtgo2, tmgo | hire | B | GroupOffice.swift ("Call a meeting with all managers") | Partial | Single-manager proposals (mprop) UNVERIFIED. |
| 70 | meetings | ui/screens/mockup.js:186 | Inbox tab: threads (msgs), email (mail), week report, big meeting, luxury offers | S.inbox, lastRep, bigOff, lux | mtab, openmsg, weekrep, msgpick, msglater | msgs, mail, weekreport | C | Features/Inbox/InboxView.swift (MessageCard) | Done | Tabs All/Decisions/Risks/Updates replace threads/email split. |
| 71 | msgs / mail | ui/screens/home.js:195,199 | Thread list/conversation; email list/view (Inbox sub-tabs) | S.inbox | thread, msgpick, msglater | meetings | A | InboxView.swift | Done | Chat-bubble conversation form not replicated. |
| 72 | weekreport | features/screens/menus_and_week_report.js:31 (replaces mockup.js:375 head; wrap trades_in_hours.js:557) | Week report: net worth change, per company, alerts, finance | S.lastRep, wk31, al30 | wr35co, wr35s, fin31, repdone, al30go, al30later, cash41in, sellinv | month30 | C | Features/Reports/ReportsView.swift | Done | Alerts block (al30) covered by Inbox/Home: UNVERIFIED. |
| 73 | month30 | features/screens/tidier_screens_and_monthly_bills.js:64 | Monthly results per company | S.al30, econ, day | al30go, al30later | res36 | A | ReportsView.swift (month period) | Done | - |
| 74 | res36 | features/screens/fewer_places.js:66 | Results: months/accounts/transactions/bills tabs | co | res36t | month30, payroll29 | A | ReportsView.swift + CompanyMoney (P&L) | Partial | Transactions and Bills tabs missing. |
| 75 | reports | features/screens/restyled_screens.js:121 | Reports and timing (all companies) | cos, npcs | - | weekreport | A | ReportsView.swift (ReportsScreen/ReportsContent) | Done | - |
| 76 | bank | ui/phone/phone.js:28 (wrap small_team_and_rewards.js:312) | Bank app: accounts, deposit, transfer, personal loans | cash, sav, loans, credit | btab, depsheet, depgo, trsheet, trgo, trset, perloan, perloango, repaysheet | pacct, invest, tax | B | Phone/BankView.swift (BankContent) | Done | Transfer sheet between accounts UNVERIFIED. |
| 77 | tax | ui/phone/phone.js:161 | Tax authority (embedded in Bank tab) | cos, tax | - | bank | A | Phone/FinanceView.swift (Tax summary, By tax) | Done | - |
| 78 | pacct | ui/phone/personal_account.js:28 | Personal account statement | cash, log | pa56, paysrc56, trsheet | bank | A | Phone/ActivityView.swift | Done | - |
| 79 | invest | ui/phone/invest.js:7 | Stocks, crypto, funds, fund manager | inv, stocks, crypto, fm | trade, buyasset, sellasset, fmhire, fmadd, fmwd, fmfire | - | B | Phone/InvestView.swift (InvestContent, TradeSheet), MoneyPeopleActions.swift (FundManagerCard) | Done | - |
| 80 | startups | ui/phone/invest.js:132 | Invest in startups | S.startups | sudeal, sugo, suhelp, susell | invest | A | Phone/VenturesView.swift | Done | - |
| 81 | pe56 | features/world/private_equity.js:116 | Private equity (buy, sell) | week | pe56go, pe56sell | invest | A | VenturesView.swift | Done | - |
| 82 | lux | features/screens/hiring_place_swipe_luxury.js:344 (wrap features/player/lifestyle.js:182; base ACT only in mockup.js:326) | Aurum luxury shop: cars, jets, watches, art, homes, estates; manage/sell | S.lux, cash | lxbuy, lxgo, luxsell, lx56, lx56co, lx56din | pk58 | C | Phone/LuxuryView.swift | Done | - |
| 83 | news (+world, paper40) | ui/screens/mockup.js:169 (V.world phone.js:187 embedded; paper40 staff_stories_and_nemesis.js:295) | News headlines, Economy block, local paper | S.news, econ, idx | phapp | rivals, top28 | A | Phone/NewsView.swift, StatsView.swift (The economy) | Partial | Business paper (paper40) and economy block in News: not ported; economy shown in Stats. |
| 84 | stats | ui/phone/stats_meetings.js:6 (wrap rival_groups.js:811) | Stats: history, area reports, goals on/off | hist, stats, areports | arep, gaon, gaoff | office | A | Phone/StatsView.swift | Done | Area reports (arep): UNVERIFIED. |
| 85 | reviews / rvdetail | features/world/market_map_and_reviews.js:491; ui/phone/reviews.js:21 (+worker_roles_and_promotions.js:237) | Customer reviews list and detail | cos reviews | rvf, rvopen, rvmore | mktdetail | A | Companies/CompanyMarket.swift, CompanyCustomers.swift (MarketView "Reviews") | Partial | KNOWN_GAPS: review counters only for project trades; no review texts screen for others: UNVERIFIED. |
| 86 | market / mktdetail | features/world/market_map_and_reviews.js:378,412 | Market map and market detail (shares, rivals) | mm26, econ | mkt26hire, mkt26rep | rival | B | CompanyMarket.swift (MarketView, MarketDetailView) | Done | - |
| 87 | mkt36 | features/screens/fewer_places.js:88 | Group row "Market" | = V.market() | - | market | D | n/a | Done (via #86) | Obsolete alias: `V.mkt36 = () => V.market ? V.market() : ''` (fewer_places.js:88) just calls V.market; head also copied from market (line 87). |
| 88 | rivals | features/world/rivals_holdings_software.js:44 (wrap staff_stories_and_nemesis.js:227, rival_groups.js) | Rivals app: per company rivals list | rivalsOf | pr28int | rival, nem28, top28 | B | CompanyMarket.swift | Done | - |
| 89 | rival | features/world/rivals_holdings_software.js:61 (wrap market_map_and_reviews.js:460) | Rival detail: buy, meet, branch next to, price war | rivalsOf | rivbuy, rivmeet, pk58hgo, branchgo, pwgo7 | branch, pricewar | B | CompanyMarket.swift (RivalSheet) | Done | - |
| 90 | pricewar | features/world/rivals_holdings_software.js:99 (wrap startup_sectors.js:328) | Start/end a price war | cos | pwpick, pwgo7, pwend | rival | B | CompanyMarket.swift (PriceWarSheet) | Done | - |
| 91 | pricemoves | features/sales/price_moves_and_lawsuits.js:280 | Price moves, campaigns, lawsuits | chains | pm16camp, pm16end, setmkt, plopen, ch16rp | pricewar, branch | B | CompanyMarket.swift (Price moves) | Partial | Lawsuit screen/flow UNVERIFIED (Lawsuits.swift engine exists). |
| 92 | branch | features/world/rivals_holdings_software.js:163 | New site (branch) | cos | branchgo, applydoc | co | A | CompanyMarket.swift (absorb .branch / openBranchNextToRival) | Partial | Plain "new site" form missing; only next-to-rival path. |
| 93 | rivmoves | features/world/rival_groups.js:583 | Rival moves feed | rs, r27me | - | grp27 | A | CompanyMarket.swift ("Week m: text") | Done | - |
| 94 | grp27 | features/world/rival_groups.js:542 | Rival group page (industries, country, world) | rs | - | rival | B | CompanyMarket.swift (Groups part of MarketView) | Done | - |
| 95 | riv31 | features/world/world_around_you.js:143 | Your rival (personal rival, meet) | nem28, pr28, credit | riv31meet | net31 | B | none (no nemesis UI; Businesses/Stories engine) | Missing | No personal-rival screen. |
| 96 | nem28 | features/people/staff_stories_and_nemesis.js:216 | Your rival / nemesis card | S.nem28 | go | grp27 | A | none | Missing | Same as riv31. |
| 97 | top28 | features/people/staff_stories_and_nemesis.js:306 | Top 50 list | cos, inbox | go | grp27 | A | Phone/WorldView.swift (RankingView "Biggest companies") | Done | - |
| 98 | paper40 | features/people/staff_stories_and_nemesis.js:295 | The business paper (front page) | R28.frontPage | go | news | A | none | Missing | No paper/front page screen. |
| 99 | img31 | features/world/world_around_you.js:215 | Public image | cash, net31, startups | fav31 | net31 | A | Phone/WorldView.swift (WorldAroundView "Seen as") | Done | - |
| 100 | net31 | features/world/world_around_you.js:399 | People you know, favours | player contacts | fav31ask, fav31call, fav31keep, net31p | riv31 | A | WorldAroundView (People, Favours) | Done | - |
| 101 | map31 | features/world/world_around_you.js:450 | Maps: ownership, presence, influence | cos, country, wk31 | fin31 | co | C | WorldAroundView (What you own / Where you are / Circles) | Partial | Lists, not a map; KNOWN_GAPS "no map". |
| 102 | trophies28 | features/player/moments_and_trophies.js:175 (wrap world_around_you.js:69) | Trophy wall | S.hof28, ach28 | tw28 | awards56 | A | Phone/AchievementsView.swift (+TrophiesPreview) | Done | Missing trophies n1, rk, no1, top10, team56 (KNOWN_GAPS). |
| 103 | awards56 | features/player/goals_and_awards.js:155 | Business awards | npcs, over | away56 | trophies28 | A | AchievementsView.swift, RichListView.swift | Partial | Awards rank by rich list not revenue (KNOWN_GAPS). |
| 104 | amb27 | features/player/ambitions.js:188 | Choose ambition path | week | amb27pick | home | A | Home/GoalsCard.swift (display only) | Partial | Picking an ambition path: UNVERIFIED (card shows milestones only). |
| 105 | fs58 | features/player/first_steps.js:88 | First steps rewards | - | fs58claim, fs58off | home | A | Home/FirstStepsCard.swift | Done | - |
| 106 | give28 | features/player/giving_and_goals.js:89 | Giving back: foundations, charity | cash, player | found28, gc28 | - | A | none (engine Businesses/Giving.swift) | Missing | No giving-back screen. |
| 107 | pro59 | features/player/pro.js:135 | Ledger Pro purchase/restore | country | prostore, prorestore | start, settings | A | none | Missing | No IAP/StoreKit (grep). Likely intentionally out of scope: UNVERIFIED decision. |
| 108 | settings | ui/phone/phone.js:227 | Settings: new game, privacy, welcome, pro link | settings | newgame2, privacy, wel59, prolink | start | A | Phone/SettingsView.swift | Done | Privacy/welcome screens absent (not game features). |
| 109 | clubs | ui/screens/club.js:13 | Football clubs market: find, buy, found, sponsor, hire | country, week | clubfind, clubbuy, clubfound, clubspon, clubhire, clubfire, clubofferx | co | A | CompanyClub.swift (ClubMarketView) | Done | - |
| 110 | cy56 | features/world/cyber_attacks.js:185 | IT security | npcs | cy56set, cy56tr, cy56bk, md56give | co | A | CompanyCustomers.swift (cyber section) | Done | - |
| 111 | tnd56 | features/sales/public_tenders.js:209 | Public tenders (bid) | npcs | tnd56go, tnd56re | co | A | CompanyContracts.swift, CompanyProjects.swift | Done | - |
| 112 | wx56 | features/world/weather_and_tourism.js:262 | Weather and tourists | country, seed | go | co | A | none (weather only in CompanyEnergy text) | Missing | No weather/tourism screen (engine Weather.swift exists). |
| 113 | registry | ui/phone/phone.js:211 | Registry: permits per company | liveCos, docNeeds | go | newbiz, co | D | n/a | Missing (obsolete) | Dead: no entry in PHAPPS (mockup.js:179; private_equity.js:140; pro.js:136), no `go('registry')`/`n:'registry'` anywhere (grep of ui/ and features/ finds only base.js:313 PHONE_APPS + its own definition). Content duplicates co docs page (ops:docs). |
| 114 | pickco | ui/phone/phone.js:8 | "Choose company" interstitial | list of cos | pickgo | - | D | n/a | Missing (obsolete) | Dead: `pickco` is referenced nowhere except its own definition/ACT.pickgo (phone.js:7-17); no go('pickco')/n:'pickco'. |
| 115 | hubs (V.titles.hq='HQ') | ui/screens/hubs.js:5 | Title only, no screen | - | - | - | D | n/a | n/a | File is 7 lines; sets a title overwritten by group_tab.js:93 (`V.titles.hq = 'Group'`, loaded later per manifest 85 vs 156). |

### Notes
- Totals: 115 rows; category A 71, B 29, C 11, D 4 (rows 87, 113, 114, 115); status Done 69 (incl. D row 87), Partial 32, Missing 13 (incl. D rows 113-114, which are obsolete), n/a 1 (row 115), Unreachable 0. Rows 17-37 are sub-pages routed through `V.co` (ui/company/view.js route()/page()), counted separately because they have their own data and actions. Pipeline wrappers (V.home:2, V.co:3, V.bank, V.lux, V.newco, V.stats, V.rivals, V.rival, V.sale, V.saletalk, V.payself, V.staffman, V.trophies28, V.weekreport, V.pricewar, V.shop, V.chain27, V.rvdetail, V.res36 fallbacks) are folded into the base row.
- Not screens but reachable overlays (not rowed): start sheets (ccsheet, citysheet, storysheet), bank sheets (depsheet, trsheet, repaysheet), `coursesheet`, `PRO.sheet`, pop-ups from `showPop` (tidier_screens...:148), `bkView` bankruptcy notice (chain_registration_and_boards.js), toast/confirm.
- No native screen is Unreachable: every Swift view found is referenced (FranchisesView, BrandMeetingView, StartFranchisedView, ClubMarketView, RankingView etc. each have a caller; grep of `\bName(` outside own struct).
- Native-only screens with no original counterpart: ProjectsView tab (company projects hub), TeamView tab (cross-company people), Start paste-import. (UNVERIFIED whether originals had an equivalent aggregate.)
- Evidence for D rows is limited to `registry`, `pickco`, `mkt36`, and the hubs title; everything else "missing in native" is NOT claimed obsolete.
- Everything marked UNVERIFIED was not opened line by line in the Swift file; only struct names, section titles and caller greps were read for it.

### Table

| # | id | file:line | purpose | required data | actions (ACT.*) | deps | cat | native counterpart | status | missing functionality |
|---|----|-----------|---------|---------------|-----------------|------|-----|--------------------|--------|-----------------------|
| 1 | start | ui/screens/start.js:48 | New-game setup: name, age, country, city, story; pro-locked countries | S null; CO/country data; PRO | startgame, setcountry, age56, ccsheet, citysheet, storysheet, loadfile, menuback, sheetclose | menu, pro59 | C | Features/Start/StartView.swift | Partial | No age, city, story/background choice; no pro-locked-country sheet (GameStore.swift:100 newGame takes only name+country). Has import-from-web-save (not in original). |
| 2 | menu | features/player/saves.js:102 | Main menu: continue, multiple save slots, load file, new game, Ledger Pro | R56saves slots, S.over, S.player | menucont, menuload, menunew, loadfile, prostore | start, home | C | StartView.swift (Continue/New game/import) | Partial | Single save only (no slot list/load slot; `slot` grep hits only unrelated code); no Pro button. |
| 3 | over | ui/screens/mockup.js:366 | Game over summary + focus plan / new game | S.over, cos, npcs, stats, inbox, lastRep | focusplan, newgame | start | C | Features/Root/GameOverView.swift | Partial | Only reason + week + peak net worth; no run summary/stats/"focus plan". |
| 4 | home | ui/screens/mockup.js:139 (wraps: sales/daily_sales.js:331, tidier_screens_and_monthly_bills.js:148 popups) | Dashboard: net worth, cash, companies, advance day/week, suggestions, goals | S.cash, cos, hist, player, country | nextday, untilneeded, paysrc56, phapp, tab, go, prostore | bank, cos, invest, newbiz, stats, fs58, amb27, give28 cards | C | Features/Home/HomeView.swift (+FirstStepsCard, GoalsCard, SuggestionCard, ComingUpCard) | Done | Pop-ups-on-Home (problems, "show when used" gating) not replicated: UNVERIFIED how alerts surface (Inbox decisions instead). |
| 5 | phonehome | ui/screens/mockup.js:180 | Phone app grid | PHAPPS, SEEN57 | phapp | all phone apps | A | Features/Phone/PhoneView.swift ("More" list) | Done | Different structure (list of 9 rows); "show when used" gating (show_when_used.js) not ported. |
| 6 | cos | ui/screens/companies_list.js:60 | Companies list (filter, sold) | S.cos, founded | cofilter, cosold, go | newbiz, holdings, found36 | A | Features/Companies/CompaniesView.swift | Done | Sold/closed filter: UNVERIFIED. |
| 7 | newbiz | ui/screens/companies_list.js:135 | Choose a trade / category | BD, S.chains, country | setcat, proask, go | newco, franchises, found36 | A | Features/Phone/NewCompanyView.swift (Choose a trade) | Done | Pro-gating (proask) absent. |
| 8 | newco | ui/screens/companies_list.js:177 (wrap hiring_place_swipe_luxury.js:44) | New-company form: city, legal form, size, premises, brand/franchise, start cost | S.cash, loans, country, fbApps, ui.nc | ncgo, brandpick, brandopen, brandapply, branduse | franchises, brandneg, co | A | NewCompanyView.swift (TradeDetailView) | Partial | Share-capital/limited-form step covered; premises choice at setup and swipe-card place picker (hiring_place_swipe_luxury) UNVERIFIED. |
| 9 | brandneg | ui/screens/companies_list.js:398 | Franchise meeting with a brand (negotiate terms) | S.fbApps, week | negstep, negsend, negsign, brandfacts | newco | B | Features/Companies/FranchiseBrandsView.swift (BrandMeetingView) | Done | - |
| 10 | franchises | ui/screens/companies_list.js:503 | Brands looking for franchisees (join) | S.fbApps | brandapply, brandopen, brandstart | newco | A | FranchiseBrandsView.swift (FranchisesView, StartFranchisedView) | Done | - |
| 11 | fr56 | ui/screens/group_tab.js:75 | Group: your franchise brands, units, join a brand | frBrands(), canFranchise | (go) | franchises, co deal/grow | A | Companies/CompanyFranchise.swift (FranchisorCard) + ChainsGroupSection | Partial | No dedicated Group page; surfaced per company/chain section. |
| 12 | frtalk56 | features/company/franchise_talks.js:76 | Talk with a franchise applicant | applicant state | frt56ed, frt56go, back | fr56 | B | CompanyFranchise.swift (FranchiseTalkView) | Done | - |
| 13 | found36 | features/screens/fewer_places.js:92 -> foundedPage (features/player/selling_startups_and_crisis.js:377) | "Your startups" list | S.founded | (see foundedPage) | cos, newbiz | A | Features/Phone/VenturesView.swift (startups) | Partial | UNVERIFIED: VenturesContent lists startups to invest in / Big meeting; player's own founded startups page not confirmed. |
| 14 | holdings | features/world/rivals_holdings_software.js:295 | List holding companies | S.cos type hold | go | newhold, co | A | GroupView.swift ("Holding companies" section) | Done | - |
| 15 | newhold | features/world/rivals_holdings_software.js:302 | New holding company (pick companies, publish) | S.cash, cos, pool | nhco, nhgo, nhpub | holdings | A | CompanyHolding.swift (NewHoldingView) | Done | "nhpub" (publish/list) UNVERIFIED. |
| 16 | co | ui/company/view.js:136 (wraps: rivals_holdings_software.js:335, newcomer_premises_one_line.js:112) | Company page with tabs Overview / Clients / Staff / Money / More; route() maps legacy t/s | getCo(p.id), BD, co.mgr, group | cotab, codeal, cofin, cosub, autoset, promoboss, promogo | co sub-pages 17-37 | C | Companies/CompanyDetailView.swift (SectionTabs) | Partial | See sub-pages; native tab set differs (Overview/Team/Finances/Operations/Marketing/Customers/Market/Setup + family sections). |
| 17 | co:ov (CT.ov) | ui/company/view.js route default | Company overview KPIs/alerts (DASH56 company_dashboards.js) | co books, alerts | opendec, autoset | co | C | CompanyDetailView.swift (CompanyOverview) | Done | - |
| 18 | co:cli (salesTab) | ui/company/view.js:route 'cli' | Sales tab: marketing, prices, customers, rivals | co demand, prices | setmkt, pm16camp | cust, rivals, prices | A | CompanyMarketing.swift, CompanyCustomers.swift, CompanyMarket.swift | Partial | Prices sub-page: price-change/discounts in CompanyMarket; UNVERIFIED parity of every price control. |
| 19 | co:st (staffTab) | ui/company/view.js route 'st'; ui/company/people.js | Staff: workers, manager banner, hire entry | co.staff, npcs | cotab, askmgr, oa59meet, hirego | hire, mgrhire | A | CompanyTeam.swift, CompanyTeamRoster.swift, TeamView.swift | Done | - |
| 20 | co:money (moneyTab) | ui/company/view.js route 'money'; ui/company/money.js | Money tab list of fin pages | co books | cofin | fin pages 28-32 | A | CompanyMoney.swift | Done | - |
| 21 | co:more (companyTab) | ui/company/view.js:107 | Company "Manage" list: supply, assets, expand, boards, docs, insurance, close | OPS_SUB/DEAL_SUB | cosub, codeal, cofin | ops/deal pages | A | CompanyOperations.swift / CompanySetupSection | Partial | No Close down / documents / insurance rows (see 26-27, 34). |
| 22 | ops:people | ui/company/view.js:276 (people.js) | People and manager page | co.mgr, staff | mgr actions | hqhire, mgrhire | B | CompanyManagement.swift, CompanyTeam.swift | Done | - |
| 23 | ops:assets | ui/company/view.js:277 (assets.js) | Premises and equipment, fleet, shop | co.eq, premises | buyeq etc | shop | A | CompanyEquipment.swift (CompanyEquipmentScreen) | Done | - |
| 24 | ops:marketing / prices | ui/company/view.js:278-279 | Marketing; Prices | co.mkt, prices | setmkt | co:cli | A | CompanyMarketing.swift / CompanyMarket.swift | Done | - |
| 25 | ops:time/upkeep/choices/special/biz | ui/company/view.js:280-287 | Staffing and owner time; stock/upkeep; business choices; special | co.flags, owner hours | opssub setters | - | A | CompanyOperations.swift, CompanyOtherSections.swift, CompanyLabourCard.swift | Partial | "Special" per-trade choices UNVERIFIED; stock policy lean/normal/safe: UNVERIFIED. |
| 26 | ops:ins | ui/company/view.js:284 | Company insurance products | co.ins | insurance acts | - | A | none (insurance only for insurer book / cyber) | Missing | No screen to buy/choose company insurance (CompanyFinanceBook/CompanyCustomers mention insurance only for fin family and cyber). |
| 27 | ops:docs | ui/company/view.js:285 | Documents and permits (docNeeds/docOk, applydoc) | co docs | applydoc | registry | A | partly CompanySetupSection ("Before opening") | Partial | After-opening permit/document page absent (grep "Documents|permit" only in NewCompany/Franchise views). |
| 28 | fin:books | ui/company/money.js:7 | Accounts: balance, P&L week/month/year/last year | co.books | books, ccheck | res36 | A | CompanyMoney.swift + PnLTable (Reports) | Done | - |
| 29 | fin:value / sell | ui/company/money.js:8-9 (deals.js:6) | Ownership & value; sell company or shares | companyValue, offers | sellco, sale* | sale, saletalk | A | CompanyOwnership.swift, CompanySaleSection.swift | Done | - |
| 30 | fin:owner | ui/company/money.js:10 | Move money / owner salary | cash, loans | cinject, cofin, cosub | payself | A | CompanyMoney.swift (Move money) | Done | - |
| 31 | fin:loans / legal | ui/company/money.js:11-12 | Loans; accountant and legal form | loans, co.form | loan acts, convert | bank | A | CompanyMoney.swift (Borrow), CompanyOtherSections.swift (accountant) | Partial | Convert to limited form: engine only per MASTER_CHECKLIST "no screen trigger" (grep "Convert to" only in NewCompanyView). |
| 32 | fin:tx / close | ui/company/money.js:13-14 | Transactions list; Close down | co.log | cofin s=close | res36 | A | none for close; transactions only as Activity (personal) | Missing | No close down / wind up / reopen / rename UI (MASTER_CHECKLIST: "no screen trigger yet"); no per-company transaction list. |
| 33 | deal:supply | ui/company/deals.js:8 | Suppliers (+ own-group supply chain) | co.sup, agree | vmeet, ch27k | chain27 | A | CompanySourcing.swift, CompanyChain.swift (CompanySupply) | Done | - |
| 34 | deal:cust / rivals / reach / insight | ui/company/deals.js:9,12,11,15 | Business customers; competitors; chain & reach; insight analytics | key accounts, rivals | acctmeet, acctdrop | rival, market | A | CompanyCustomers.swift, CompanyMarket.swift, CompanyChain.swift | Partial | "Insight and analytics" page: KNOWN_GAPS says no marketing analytics screen. |
| 35 | deal:grow / sell | ui/company/deals.js:10,13 | Expand (branch, chain, franchise, abroad); sell | co | codeal grow | store13, chain12, branch | A | CompanyChain.swift (GrowIntoChain), CompanyFranchise.swift | Partial | Abroad expansion screen UNVERIFIED. |
| 36 | mgmt56 | ui/company/headquarters.js:116 | Company HQ: overview/manager/assistant/team | co.mgr, asst, TEAM56 | hq56t | hqmk, mgrhire | B | CompanyManagement.swift + CompanyTeamRoster.swift | Done | Merged into Team per MASTER_CHECKLIST grouping rules. |
| 37 | hqmk | ui/screens/group.js:125 | Main-office team screen (desks, paperwork) | office, npcs | hqas, hqtick, plopen | office | B | Companies/GroupOffice.swift (HeadOfficeSection) | Done | - |
| 38 | hq | ui/screens/group_tab.js:96 | Group tab: You / Group / Main office pages | OLD alias map | hqtab | group, office, 20+ rows | C | Companies/GroupView.swift | Partial | Native Group = Holdings + Money only; "You" page (people, image, trophies, awards, giving) lives in More sheet. |
| 39 | group | ui/screens/group.js:9 | Management structure per company (embedded in hq) | group.ceo/regional, npcs | fireceo, fireregional | mgmt56 | A | ExecutivePosts.swift | Done | - |
| 40 | office | ui/screens/group.js:95 | Main office (hire desks, rent, right hand) | office | hirehq, officepop | hqhire, hqmk | B | GroupOffice.swift | Done | - |
| 41 | hqhire | ui/screens/hiring.js:219 | Hire for main office (search, candidate, offer) | netCD, npcs | hqsearch, hqcandopen, hqoffer, hqstep56 | office | B | GroupOffice.swift (search/Offer/Check references) | Done | - |
| 42 | hire | ui/screens/hiring.js:49 | Find workers flow (terms, candidates, references, offer) | npcs, netCD | hsearch, hrole, candopen, candpass, offer7, hstep56, hk54s | co:st | B | CompanyTeam.swift (Find workers) + HireOptionsMenu | Partial | Multi-step flow collapsed into one list; reference check on workers UNVERIFIED. |
| 43 | mgrhire | ui/screens/hiring.js:132 | Management hire (any role: shortlist, ask, refs, offer) | cash, npcs | mgrask, mgrref, moffer56, mstep56 | hqhire | B | CompanyManagement.swift, ExecutivePosts.swift | Done | - |
| 44 | managers | ui/screens/review.js:13 | Manager reviews/scorecards (embedded in hq grp) | cos, npcs, office | reviewnow, reviewall | office | A | GroupOffice.swift ("Manager reviews") | Done | - |
| 45 | suppliers | ui/screens/group.js:42 | Group suppliers (deals every company buys through) | S.agree, vr | vmeet | deal:supply | A | GroupOffice.swift (SuppliersGroupSection) | Done | - |
| 46 | dealroom | ui/screens/group.js:180 | Deal room: hold in/out, inject, new holding | cos | holdin, holdout, injhold, newhold | holdings | A | CompanyHolding.swift / HostingSection (MoneyPeopleActions.swift) | Partial | UNVERIFIED parity of holdin/holdout/injhold. |
| 47 | boards12 | features/company/shelf_stock_chains_boards.js:425 | Boards list: seats, right hand, emergency | S.chains boards | lh12fire, price, stock | board12, bmeet12 | B | GroupBoards.swift (BoardsGroupSection) | Done | - |
| 48 | board12 | features/company/shelf_stock_chains_boards.js:392 | One board | cash, npcs | - | boards12 | B | GroupBoards.swift | Done | - |
| 49 | bmeet12 | features/company/shelf_stock_chains_boards.js:550 | Board meeting: vote, emergency | S.pend, inbox | bd12yes, bd12no, emg12, emg12pick, emg37 | board12 | B | GroupBoards.swift (What the board says) + Inbox decisions | Partial | Emergency (emg12/emg37) flow via inbox: UNVERIFIED. |
| 50 | chain12 | features/company/shelf_stock_chains_boards.js:186 | Chain page: stores, rules, lend, hire | S.chains, lh | ch12rule, ch12join, ch12lend, ch12fire | store13 | B | CompanyChain.swift (ChainOverview, StoreRules) | Done | - |
| 51 | store13 | features/company/chain_registration_and_boards.js:56 | Open a new store in a chain | cash, country, group | ns13go, ch12new, bd13find | chain12 | A | CompanyChain.swift ("New store") | Done | - |
| 52 | chain27 | features/company/intercompany_supply.js:178 (wrap small_team_and_rewards.js:302) | Supply chain between own companies | S.l27 | ch27set, ch27off, ch27k | deal:supply | A | CompanyChain.swift (CompanySupply) | Done | - |
| 53 | org56 | features/company/org_chart.js:131 | Organisation chart | S.chains, group, npcs | go | chain12, boards12 | A | none | Missing | No org chart (grep OrgChart/Organisation: none). Roles are in Team list per grouping rules. |
| 54 | own27 | features/company/owner_investors.js:265 | Co-owners/investors: buy-out, policy | S.cash, npcs | own27buy, own27pol | co | A | CompanyOwnership.swift | Partial | Dividend policy and shareholders present; buy-back (own27buy) UNVERIFIED. |
| 55 | payroll29 | features/company/payday.js:403 | Payroll and bills (approve run, mode) | npcs, co.pay | pr29run, pr29ok, pr29mode | payself, res36 | A | none (auto-payroll toggle in SettingsView) | Missing | No payroll approval/bills screen; only policy switch "Approve routine payroll for me". |
| 56 | payself | features/sales/realistic_odds.js:152 (wrap payday.js:518) | Pay yourself / owner salary | cos, loans | cinject, cofin, cosub, primary | co | A | CompanyMoney.swift (Move money) | Partial | Salary-setting UI UNVERIFIED. |
| 57 | shop | features/company/realistic_buying.js:742 (wrap rivals_holdings_software.js:506) | Equipment/vehicle/software shop | S.econ, npcs | shopbuy, shopq, shopsel, shopvc, shopcls, ownsw | ops:assets | A | CompanyEquipment.swift (EquipmentShopView) | Done | Own software (ownsw) UNVERIFIED. |
| 58 | sale | features/player/selling_startups_and_crisis.js:38 (wrap rivals_holdings_software.js:200) | Sell or raise money: offers, broker, funding rounds, pitch | S.sales, fundOffers, deferred | salemode, saleacc/dec/ctr, pitch, fundacc/dec/ctr, salewd | saletalk | B | CompanySaleSection.swift, CompanyOwnership.swift (pitchToInvestors) | Done | Deferred payments UNVERIFIED. |
| 59 | saletalk | features/world/rivals_holdings_software.js:210 (wrap salary_talks.js:42) | Haggle with a buyer (chat) | S.sales, office | saleq, salecounter, saleacc, saledec7 | sale | B | CompanySaleSection.swift ("Counter +8%") | Partial | Chat-style talk reduced to one counter button. |
| 60 | bigmeet | features/player/selling_startups_and_crisis.js:394 | Big meeting: stakes/offers, accept/counter/walk | S.bigOff, loans | bigacc, bigctr, bigwalk | meetings | B | VenturesView.swift ("Big meeting") + GroupBoards.swift | Done | - |
| 61 | crisis | features/player/selling_startups_and_crisis.js:634 | Crisis centre (distress options, forced sale) | S.over, week | msgpick | sale | B | none (grep: engine VentureActions only) | Missing | No crisis centre screen. |
| 62 | staffman | features/player/selling_startups_and_crisis.js:474 (wrap staff_stories_and_nemesis.js:130) | Staff member profile: course, raise, warn, fire, logo | npcs, seed | coursesheet, doraise, firestaff, warnstaff, logo | academy | A | CompanyTeam.swift, CompanyOtherSections.swift (StaffContractMenu) | Partial | Profile stories/nemesis lines UNVERIFIED; "logo" absent. |
| 63 | academy | features/screens/restyled_screens.js:149 | Academy: courses for staff | cos, npcs | acads, acadc, acadco, docourse | staffman | A | CompanyTeam.swift (sendOnCourse) | Done | - |
| 64 | pr11 | features/people/worker_roles_and_promotions.js:422 | Promotion overview | week | p11talk, go | anrep11, p11talk | B | CompanyManagement.swift (PromotionSheet) | Done | - |
| 65 | p11talk | features/people/worker_roles_and_promotions.js:448 | Promotion talk (role, duty, offer) | cos, npcs, office | p11offer, p11set, p11duty, p11back | pr11 | B | PromotionSheet in CompanyManagement.swift | Done | - |
| 66 | anrep11 | features/people/worker_roles_and_promotions.js:616 | Analyst report (find manager, tab) | cos, group | mfind11 | pr11 | A | DataAnalystCard (Phone/WorldView.swift) | Partial | Report screen not ported as such; analyst ranges shown in market views. |
| 67 | tg58 | features/people/targets_and_budgets.js:332 | Manager targets and budget | npcs | tg58go | mgmt56 | A | CompanyPeopleActions.swift (CompanyTargetsCard) | Done | - |
| 68 | pk58 | features/people/perks_and_hosting.js:139 | Perks, hosting, lending a piece | cos, sales | pk58hgo, pk58host, pk58lend, pk58lgo, pk58t, phapp | lux | A | CompanyPeopleActions.swift (CompanyPerksCard), MoneyPeopleActions.swift (HostingSection, LendPieceSection) | Done | - |
| 69 | meet | features/people/manager_search_and_meetings.js:131 | Call a meeting (group/manager meetings, proposals) | inbox, npcs | mprop, mtgo2, tmgo | hire | B | GroupOffice.swift ("Call a meeting with all managers") | Partial | Single-manager proposals (mprop) UNVERIFIED. |
| 70 | meetings | ui/screens/mockup.js:186 | Inbox tab: threads (msgs), email (mail), week report, big meeting, luxury offers | S.inbox, lastRep, bigOff, lux | mtab, openmsg, weekrep, msgpick, msglater | msgs, mail, weekreport | C | Features/Inbox/InboxView.swift (MessageCard) | Done | Tabs All/Decisions/Risks/Updates replace threads/email split. |
| 71 | msgs / mail | ui/screens/home.js:195,199 | Thread list/conversation; email list/view (Inbox sub-tabs) | S.inbox | thread, msgpick, msglater | meetings | A | InboxView.swift | Done | Chat-bubble conversation form not replicated. |
| 72 | weekreport | features/screens/menus_and_week_report.js:31 (replaces mockup.js:375 head; wrap trades_in_hours.js:557) | Week report: net worth change, per company, alerts, finance | S.lastRep, wk31, al30 | wr35co, wr35s, fin31, repdone, al30go, al30later, cash41in, sellinv | month30 | C | Features/Reports/ReportsView.swift | Done | Alerts block (al30) covered by Inbox/Home: UNVERIFIED. |
| 73 | month30 | features/screens/tidier_screens_and_monthly_bills.js:64 | Monthly results per company | S.al30, econ, day | al30go, al30later | res36 | A | ReportsView.swift (month period) | Done | - |
| 74 | res36 | features/screens/fewer_places.js:66 | Results: months/accounts/transactions/bills tabs | co | res36t | month30, payroll29 | A | ReportsView.swift + CompanyMoney (P&L) | Partial | Transactions and Bills tabs missing. |
| 75 | reports | features/screens/restyled_screens.js:121 | Reports and timing (all companies) | cos, npcs | - | weekreport | A | ReportsView.swift (ReportsScreen/ReportsContent) | Done | - |
| 76 | bank | ui/phone/phone.js:28 (wrap small_team_and_rewards.js:312) | Bank app: accounts, deposit, transfer, personal loans | cash, sav, loans, credit | btab, depsheet, depgo, trsheet, trgo, trset, perloan, perloango, repaysheet | pacct, invest, tax | B | Phone/BankView.swift (BankContent) | Done | Transfer sheet between accounts UNVERIFIED. |
| 77 | tax | ui/phone/phone.js:161 | Tax authority (embedded in Bank tab) | cos, tax | - | bank | A | Phone/FinanceView.swift (Tax summary, By tax) | Done | - |
| 78 | pacct | ui/phone/personal_account.js:28 | Personal account statement | cash, log | pa56, paysrc56, trsheet | bank | A | Phone/ActivityView.swift | Done | - |
| 79 | invest | ui/phone/invest.js:7 | Stocks, crypto, funds, fund manager | inv, stocks, crypto, fm | trade, buyasset, sellasset, fmhire, fmadd, fmwd, fmfire | - | B | Phone/InvestView.swift (InvestContent, TradeSheet), MoneyPeopleActions.swift (FundManagerCard) | Done | - |
| 80 | startups | ui/phone/invest.js:132 | Invest in startups | S.startups | sudeal, sugo, suhelp, susell | invest | A | Phone/VenturesView.swift | Done | - |
| 81 | pe56 | features/world/private_equity.js:116 | Private equity (buy, sell) | week | pe56go, pe56sell | invest | A | VenturesView.swift | Done | - |
| 82 | lux | features/screens/hiring_place_swipe_luxury.js:344 (wrap features/player/lifestyle.js:182; base ACT only in mockup.js:326) | Aurum luxury shop: cars, jets, watches, art, homes, estates; manage/sell | S.lux, cash | lxbuy, lxgo, luxsell, lx56, lx56co, lx56din | pk58 | C | Phone/LuxuryView.swift | Done | - |
| 83 | news (+world, paper40) | ui/screens/mockup.js:169 (V.world phone.js:187 embedded; paper40 staff_stories_and_nemesis.js:295) | News headlines, Economy block, local paper | S.news, econ, idx | phapp | rivals, top28 | A | Phone/NewsView.swift, StatsView.swift (The economy) | Partial | Business paper (paper40) and economy block in News: not ported; economy shown in Stats. |
| 84 | stats | ui/phone/stats_meetings.js:6 (wrap rival_groups.js:811) | Stats: history, area reports, goals on/off | hist, stats, areports | arep, gaon, gaoff | office | A | Phone/StatsView.swift | Done | Area reports (arep): UNVERIFIED. |
| 85 | reviews / rvdetail | features/world/market_map_and_reviews.js:491; ui/phone/reviews.js:21 (+worker_roles_and_promotions.js:237) | Customer reviews list and detail | cos reviews | rvf, rvopen, rvmore | mktdetail | A | Companies/CompanyMarket.swift, CompanyCustomers.swift (MarketView "Reviews") | Partial | KNOWN_GAPS: review counters only for project trades; no review texts screen for others: UNVERIFIED. |
| 86 | market / mktdetail | features/world/market_map_and_reviews.js:378,412 | Market map and market detail (shares, rivals) | mm26, econ | mkt26hire, mkt26rep | rival | B | CompanyMarket.swift (MarketView, MarketDetailView) | Done | - |
| 87 | mkt36 | features/screens/fewer_places.js:88 | Group row "Market" | = V.market() | - | market | D | n/a | Done (via #86) | Obsolete alias: `V.mkt36 = () => V.market ? V.market() : ''` (fewer_places.js:88) just calls V.market; head also copied from market (line 87). |
| 88 | rivals | features/world/rivals_holdings_software.js:44 (wrap staff_stories_and_nemesis.js:227, rival_groups.js) | Rivals app: per company rivals list | rivalsOf | pr28int | rival, nem28, top28 | B | CompanyMarket.swift | Done | - |
| 89 | rival | features/world/rivals_holdings_software.js:61 (wrap market_map_and_reviews.js:460) | Rival detail: buy, meet, branch next to, price war | rivalsOf | rivbuy, rivmeet, pk58hgo, branchgo, pwgo7 | branch, pricewar | B | CompanyMarket.swift (RivalSheet) | Done | - |
| 90 | pricewar | features/world/rivals_holdings_software.js:99 (wrap startup_sectors.js:328) | Start/end a price war | cos | pwpick, pwgo7, pwend | rival | B | CompanyMarket.swift (PriceWarSheet) | Done | - |
| 91 | pricemoves | features/sales/price_moves_and_lawsuits.js:280 | Price moves, campaigns, lawsuits | chains | pm16camp, pm16end, setmkt, plopen, ch16rp | pricewar, branch | B | CompanyMarket.swift (Price moves) | Partial | Lawsuit screen/flow UNVERIFIED (Lawsuits.swift engine exists). |
| 92 | branch | features/world/rivals_holdings_software.js:163 | New site (branch) | cos | branchgo, applydoc | co | A | CompanyMarket.swift (absorb .branch / openBranchNextToRival) | Partial | Plain "new site" form missing; only next-to-rival path. |
| 93 | rivmoves | features/world/rival_groups.js:583 | Rival moves feed | rs, r27me | - | grp27 | A | CompanyMarket.swift ("Week m: text") | Done | - |
| 94 | grp27 | features/world/rival_groups.js:542 | Rival group page (industries, country, world) | rs | - | rival | B | CompanyMarket.swift (Groups part of MarketView) | Done | - |
| 95 | riv31 | features/world/world_around_you.js:143 | Your rival (personal rival, meet) | nem28, pr28, credit | riv31meet | net31 | B | none (no nemesis UI; Businesses/Stories engine) | Missing | No personal-rival screen. |
| 96 | nem28 | features/people/staff_stories_and_nemesis.js:216 | Your rival / nemesis card | S.nem28 | go | grp27 | A | none | Missing | Same as riv31. |
| 97 | top28 | features/people/staff_stories_and_nemesis.js:306 | Top 50 list | cos, inbox | go | grp27 | A | Phone/WorldView.swift (RankingView "Biggest companies") | Done | - |
| 98 | paper40 | features/people/staff_stories_and_nemesis.js:295 | The business paper (front page) | R28.frontPage | go | news | A | none | Missing | No paper/front page screen. |
| 99 | img31 | features/world/world_around_you.js:215 | Public image | cash, net31, startups | fav31 | net31 | A | Phone/WorldView.swift (WorldAroundView "Seen as") | Done | - |
| 100 | net31 | features/world/world_around_you.js:399 | People you know, favours | player contacts | fav31ask, fav31call, fav31keep, net31p | riv31 | A | WorldAroundView (People, Favours) | Done | - |
| 101 | map31 | features/world/world_around_you.js:450 | Maps: ownership, presence, influence | cos, country, wk31 | fin31 | co | C | WorldAroundView (What you own / Where you are / Circles) | Partial | Lists, not a map; KNOWN_GAPS "no map". |
| 102 | trophies28 | features/player/moments_and_trophies.js:175 (wrap world_around_you.js:69) | Trophy wall | S.hof28, ach28 | tw28 | awards56 | A | Phone/AchievementsView.swift (+TrophiesPreview) | Done | Missing trophies n1, rk, no1, top10, team56 (KNOWN_GAPS). |
| 103 | awards56 | features/player/goals_and_awards.js:155 | Business awards | npcs, over | away56 | trophies28 | A | AchievementsView.swift, RichListView.swift | Partial | Awards rank by rich list not revenue (KNOWN_GAPS). |
| 104 | amb27 | features/player/ambitions.js:188 | Choose ambition path | week | amb27pick | home | A | Home/GoalsCard.swift (display only) | Partial | Picking an ambition path: UNVERIFIED (card shows milestones only). |
| 105 | fs58 | features/player/first_steps.js:88 | First steps rewards | - | fs58claim, fs58off | home | A | Home/FirstStepsCard.swift | Done | - |
| 106 | give28 | features/player/giving_and_goals.js:89 | Giving back: foundations, charity | cash, player | found28, gc28 | - | A | none (engine Businesses/Giving.swift) | Missing | No giving-back screen. |
| 107 | pro59 | features/player/pro.js:135 | Ledger Pro purchase/restore | country | prostore, prorestore | start, settings | A | none | Missing | No IAP/StoreKit (grep). Likely intentionally out of scope: UNVERIFIED decision. |
| 108 | settings | ui/phone/phone.js:227 | Settings: new game, privacy, welcome, pro link | settings | newgame2, privacy, wel59, prolink | start | A | Phone/SettingsView.swift | Done | Privacy/welcome screens absent (not game features). |
| 109 | clubs | ui/screens/club.js:13 | Football clubs market: find, buy, found, sponsor, hire | country, week | clubfind, clubbuy, clubfound, clubspon, clubhire, clubfire, clubofferx | co | A | CompanyClub.swift (ClubMarketView) | Done | - |
| 110 | cy56 | features/world/cyber_attacks.js:185 | IT security | npcs | cy56set, cy56tr, cy56bk, md56give | co | A | CompanyCustomers.swift (cyber section) | Done | - |
| 111 | tnd56 | features/sales/public_tenders.js:209 | Public tenders (bid) | npcs | tnd56go, tnd56re | co | A | CompanyContracts.swift, CompanyProjects.swift | Done | - |
| 112 | wx56 | features/world/weather_and_tourism.js:262 | Weather and tourists | country, seed | go | co | A | none (weather only in CompanyEnergy text) | Missing | No weather/tourism screen (engine Weather.swift exists). |
| 113 | registry | ui/phone/phone.js:211 | Registry: permits per company | liveCos, docNeeds | go | newbiz, co | D | n/a | Missing (obsolete) | Dead: no entry in PHAPPS (mockup.js:179; private_equity.js:140; pro.js:136), no `go('registry')`/`n:'registry'` anywhere (grep of ui/ and features/ finds only base.js:313 PHONE_APPS + its own definition). Content duplicates co docs page (ops:docs). |
| 114 | pickco | ui/phone/phone.js:8 | "Choose company" interstitial | list of cos | pickgo | - | D | n/a | Missing (obsolete) | Dead: `pickco` is referenced nowhere except its own definition/ACT.pickgo (phone.js:7-17); no go('pickco')/n:'pickco'. |
| 115 | hubs (V.titles.hq='HQ') | ui/screens/hubs.js:5 | Title only, no screen | - | - | - | D | n/a | n/a | File is 7 lines; sets a title overwritten by group_tab.js:93 (`V.titles.hq = 'Group'`, loaded later per manifest 85 vs 156). |

### Notes
- Totals: 115 rows; category A 71, B 29, C 11, D 4 (rows 87, 113, 114, 115); status Done 69 (incl. D row 87), Partial 32, Missing 13 (incl. D rows 113-114, which are obsolete), n/a 1 (row 115), Unreachable 0. Rows 17-37 are sub-pages routed through `V.co` (ui/company/view.js route()/page()), counted separately because they have their own data and actions. Pipeline wrappers (V.home:2, V.co:3, V.bank, V.lux, V.newco, V.stats, V.rivals, V.rival, V.sale, V.saletalk, V.payself, V.staffman, V.trophies28, V.weekreport, V.pricewar, V.shop, V.chain27, V.rvdetail, V.res36 fallbacks) are folded into the base row.
- Not screens but reachable overlays (not rowed): start sheets (ccsheet, citysheet, storysheet), bank sheets (depsheet, trsheet, repaysheet), `coursesheet`, `PRO.sheet`, pop-ups from `showPop` (tidier_screens...:148), `bkView` bankruptcy notice (chain_registration_and_boards.js), toast/confirm.
- No native screen is Unreachable: every Swift view found is referenced (FranchisesView, BrandMeetingView, StartFranchisedView, ClubMarketView, RankingView etc. each have a caller; grep of `\bName(` outside own struct).
- Native-only screens with no original counterpart: ProjectsView tab (company projects hub), TeamView tab (cross-company people), Start paste-import. (UNVERIFIED whether originals had an equivalent aggregate.)
- Evidence for D rows is limited to `registry`, `pickco`, `mkt36`, and the hubs title; everything else "missing in native" is NOT claimed obsolete.
- Everything marked UNVERIFIED was not opened line by line in the Swift file; only struct names, section titles and caller greps were read for it.

## 2. Original company tabs, sub-pages and modal sheets

### How the original builds a company (o/ui/company/view.js)
- Tab registry: `TABS` view.js:12 `{ov Overview, cli Sales, st Manage, money Money, more Company}`; `tabOrder` view.js:14: normal = ov, cli, st, money; football club = ov, st(Squad), money, more. Non-club "more" is folded into Manage (view.js:31, companyTab(inManage=1) view.js:109).
- Sub-pages: `OPS_SUB` (view.js ~290: table, people, assets, marketing, prices, time, upkeep, choices, special, ins, docs, biz), `CT.FIN_SUB` (money.js:6: books, value, sell, owner, loans, legal, tx, close), `CT.DEAL_SUB` (deals.js:6: value, supply, cust, sell, reach, rivals, grow, close, insight), Sales sub-pages `SALES_SUB` (view.js:61: mk, hys, cmp). Route table `route()` view.js:17. Per-tab KPI tiles: `DASH56` o/features/screens/company_dashboards.js:60/84/110/130/194.
- Native: `CompanySection` enum (n/CompanyDetailView.swift:10): Overview, Projects, Team, Finances, Operations, Marketing, Customers, Market, Setup + family sections Properties, Book, Plant, Fish, Holding, Club, Chain. So the native layout is NOT 1:1 with the original tabs: Sales -> Marketing + Customers + Market; Manage+Company -> Team + Operations; Money -> Finances.

Categories: A generic template (list/detail/form/confirm/KPI+rows) · B specialist template (hiring flow, board/meeting, rival/market cards, finance book, equipment/vehicle catalogue) · C individually designed · D verified obsolete/duplicate (evidence in note).
Status: Done / Partial / Missing / Unreachable.

### Inventory (one row per tab / page / screen)

| # | id | orig file:line | purpose; data; actions | cat | native counterpart | status | missing in native |
|---|----|----------------|------------------------|-----|--------------------|--------|-------------------|
| 1 | ov Overview (CT.ov) | o/ui/company/view.js:~235 (CT.ov); family cards CT.famOv o/ui/company/family.js:6 | cash hero + month result, week card (R41.weekCard trades_in_hours.js:521), targets row (TG58.row targets_and_budgets.js:283), storefront R28.shopCard (moments_and_trophies.js:339), open-decisions button `opendec`; reads co.cash, co.bk, co.hist, S.inbox | A | n/CompanyDetailView.swift `CompanyOverview` (l.93) | Partial | storefront card, targets row on overview, "Open N decisions" button, per-family cards (Stock policy/Members/House result/Order book/Portfolio: UNVERIFIED) |
| 2 | setup / opening checklist (CT.setupOv, openChecklist rows `cldo`, `docsall`, `autoset`) | view.js:~262 CT.setupOv; o/ui/company/assets.js:19-50 (clRows, cldo, docsall, setupCard) | each missing item is one tap: apply doc / choose premises / buy equipment / put in stock cash; `autoset` = manager sets up | A | n/CompanyDetailView.swift `CompanySetupSection` (l.226) | Partial | checklist rows are read-only (no tap-to-do); only "Fill in what is missing" (quickSetup) + equipment entry row + Open; no per-document apply; no "let manager set up" |
| 3 | cli Sales tab (hub) | view.js:61 salesTab; DASH56.sales company_dashboards.js:60 | rows Competitors, Business customers, Tenders, Marketing, How you sell, Complaints + R33.salesCard | A | split into n/CompanyMarketing, CompanyCustomers, CompanyMarket tabs | Done | (structural: hub replaced by three tabs) |
| 4 | st Manage tab (hub) | view.js:83 staffTab; DASH56.staff :84 | team, manager banner/You card (R45.youCard managers_who_manage.js:82), courses, perks row (PK58.row), payroll row (R29.row), then Company rows | A | n/CompanyTeam.swift (CompanyTeam l.7) | Partial | KPI tiles, You-next-to-manager card, payroll row |
| 5 | money Money tab (hub) | view.js:92 moneyTab; DASH56.money :110 | rows Pay yourself, Results, Sell unpaid invoices, Loans, Value, Legal, Close down | A | n/CompanyMoney.swift (l.8) | Partial | see rows 28-38 |
| 6 | more Company tab (hub; own tab only for club) | view.js:109 companyTab; DASH56.company :194 | running rows (Suppliers, Premises & equipment, Expand, Board, Stock, Choices, Rename, IT security) + Paperwork & protection (Docs, Insurance) | A | n/CompanyOperations.swift (l.6) + CompanyOtherSections | Partial | see rows 41-52 |
| 7 | mk Marketing page (CT.marketing) | view.js:480 (wrapped selling_startups_and_crisis.js:660); `setmkt` | awareness, weekly budget, active channel cards (build-up/min-term meters), `plopen`; reads co.mkt, co.aware, CH{} | A | n/CompanyMarketing.swift (73 lines) | Partial | channel build-up/minimum-term meters, awareness decay note, marketing-director bonus, stop/reduce per channel (UNVERIFIED) |
| 8 | Campaign planner sheet (planSheet) | view.js:~425-470 (`plopen`, `plset`, `plgo`, window.PLX advise/guess) | modal: channel, budget/wk, duration, target age group, analyst-guess "how well it fits", reach estimate; `setMkt`, co.mktEnd, co.mktT | A (form sheet) | inline in CompanyMarketing.swift (setCampaign l.70) | Partial | duration/end date, age-group targeting, manager advice, reach estimate |
| 9 | hys How you sell | o/features/sales/how_you_sell.js:61 (H.page), summary :54; `setknob` view.js:~300 | trade "knobs" (choices) with doc requirements | A | n/CompanyOperations.swift knobs (l.60-63) | Partial | "documents needed -> apply and choose" confirm (setknob) |
| 10 | cmp Complaints | o/features/people/owner_hours_clients_assistants.js:283 (complaintsPart, CT.complaints :221) | answer open complaints (refund/apologise/ignore); co.compl | A | n/CompanyOtherSections.swift `complaints` (l.25) | Done | – |
| 11 | rivals Competitors page (CT.rivalsCard) | o/ui/company/deals.js:254; sheets rivmeet/rivbuy/rivoffer/rivclose :264-293; V.rival o/features/world/rivals_holdings_software.js:61; V.riv31 world_around_you.js:143 | rival list, meet, buy, offer, absorb; rivalsOf(co) | B | n/CompanyMarket.swift Rivals + `RivalSheet` (l.156) | Done | – |
| 12 | pricewar | rivals_holdings_software.js:99 | start price war vs rival, chances, duration | A (form sheet) | n/CompanyMarket.swift `PriceWarSheet` (l.353) | Done | – |
| 13 | pricemoves | o/features/sales/price_moves_and_lawsuits.js:280 (V.pricemoves; title also selling_startups_and_crisis.js:571) | change prices vs rivals, discount campaign, forecast; `pm16*` | A | n/CompanyMarket.swift priceMoves (l.55) | Done | lawsuit side (price_moves_and_lawsuits) UNVERIFIED |
| 14 | cust Business customers + contract sheet (`acc39`, `ct56`) | deals.js:48-72, ct56 :101; acctmeet/acctdrop :131-142; engine/company/key_accounts.js | regular customers (discount, meet, drop), contracts/bookings, tenders link | A | n/CompanyCustomers.swift `AccountRow` (l.137) + n/CompanyContracts.swift | Done | contract profile sheet fields (extensions, quality promise, warnings) UNVERIFIED |
| 15 | tnd56 Tenders | o/features/sales/public_tenders.js:209 (V.tnd56), eligible :68, summary :196 | bid on public tenders, auto-bid | A | n/CompanyContracts.swift Volume tenders (l.119), n/CompanyProjects.swift Tenders (l.109) | Done | auto-bid setting (`tnd56auto`) UNVERIFIED (engine setManagerBids used) |
| 16 | Ways to sell (R33.salesCard) | o/features/sales/trade_sales_mechanics.js:237; `sw33t` :201 | contract/offer/booking ways | A | n/CompanyWaysToSell.swift (l.8) | Done | – |
| 17 | prices page (ops prices) | view.js:~310 (opsPart 'prices'), `pricestep` | price level -3..+3, avg ticket | A | n/CompanyOperations.swift slider (l.22) | Done | – |
| 18 | insight / analytics (CT.ana, DEAL 'insight') | view.js:619; deals.js:~66; `gaon` o/ui/phone/stats_meetings.js:34; piped screens/club.js:146 | web traffic sparkline, analyst briefing (marketOutlook), demand drivers `why()` view.js:163 + capacity limits; needs HQ analyst | A | none (only analyst verdict text in n/CompanyTeam.swift l.103) | Missing | whole page; engine `requestAnalystReport`, `setPerformanceAnalystAuto` are Unreachable |
| 19 | Team list (CT.ppl) + problem cards | o/ui/company/people.js:42; staffTag :28; FLAGN problem cards :58; seasons/hours `stseas/stpart/stfix/sthrs/stfull` :104-148 | roster with tags, wage, tenure; talk/let go; part-time/seasonal/hours | A | n/CompanyTeam.swift (l.25-90) + `StaffContractMenu` (CompanyOtherSections.swift:139) | Partial | tags (Rising/Fine), problem cards + "talk to them" (engine `talkToStaff` Unreachable), expandable row details |
| 20 | Staff profile (`staffman`, CT.staffProfile, pay/verify/onboard blocks) | o/features/player/selling_startups_and_crisis.js:474; o/ui/company/people.js:179-262 (energyBlock, moodOf, payBlock, verBlock, onbBlock); `raisesheet` :267, `talkstaff` :278, `coursesheet` :290 | one person: mood, energy, pay model/commission (`setpay`,`setrate`), agent verification (`verifyag`), onboarding tick | A (detail) | none dedicated; actions scattered in the "..." menu in CompanyTeam.swift l.47-61 | Partial | profile page (mood/energy/skill growth), raise tiers (3/6/10% vs only 5%), talk, verification, onboarding steps (engine `staffProfile`, `setPayModel`, `setCommissionRate` exist; `setPayModel` reachable via StaffContractMenu) |
| 21 | Hiring flow (find workers) | o/ui/screens/hiring.js:45-125 (V.hire); o/ui/company/people.js:308-460 (`candopen/candback/candpass/hirego/hrole/hrole2/hmode/hsearch/paysel/payrate/refcheck/trial/offer`) | pick role (+ "other roles" sheet :371), search mode ad/network/agency, candidate card, reference check, trial, wage offer negotiation | B | n/CompanyTeam.swift "Find workers" (l.91-120) + `HireOptionsMenu` (CompanyOtherSections.swift:203) | Partial | candidate detail page, reference check for workers, wage negotiation (counter-offer `offer` :430), "other roles" sheet; has: roles, 3 search modes, terms (full/part/seasonal/own car), trial week |
| 22 | Headquarters hub (HQ56) | o/ui/company/headquarters.js:116 (V.mgmt56), H.page :104, tabs ov/mgr/asst/team | tiles (Manager, Decides, Targets, Reports to, IT security, Insurance, Premises), who works here, vacancies | A (KPI+rows) | n/CompanyManagement.swift + CompanyTeamRoster.swift (combined in CompanyTeam) | Partial | tile dashboard, vacancy rows, pick-a-role start screen |
| 23 | HQ Manager page (mgrPage, CT.mgrCard, MD56.card) | headquarters.js:78; people.js:461-523 (authlvl/authbuy/authhire/authad/mgrraise/mgrfire); o/features/people/manager_duties.js:16; managers_keep_it_working.js | authority level + limits, duties the manager keeps (insurance, IT, premises), raise, fire, profit bonus | A | n/CompanyManagement.swift (l.11-135) | Partial | per-duty switches (engine `setManagerDuty` Unreachable), profit-bonus (`setManagerProfitBonus` Unreachable) |
| 24 | HQ Assistant (asstRow) | owner_hours_clients_assistants.js:339 | assistant manager, two duties | A | n/CompanyManagement.swift assistant (l.214-285) | Done | – |
| 25 | HQ Team (TEAM56.card) | o/features/people/management_team.js:14 | MD, department heads, regional managers | A | n/CompanyTeamRoster.swift (l.11) | Done | – |
| 26 | mgrhire (hire a manager / role via agency) | o/ui/screens/hiring.js:132 (V.mgrhire; HIRE56.mgrVerdict :115), people.js:524-558 (`mgrask/mgrref/mgrhirego`) | step screen: brief, interview skill, references, offer | B | n/CompanyManagement.swift hire section (l.138-205) | Done | HIRE56.mgrVerdict text UNVERIFIED |
| 27 | Promotion (pr11, p11talk, promoSheet) | o/features/people/worker_roles_and_promotions.js:422/448; view.js:~212 (promoSheet/promogo/promoboss); `hireManager` | promote worker to post / acting manager to manager, wage negotiation | B | n/CompanyManagement.swift `PromotionSheet` (l.288) | Done | – |
| 28 | tg58 Targets and budget | o/features/people/targets_and_budgets.js:332 (V.tg58), card :305, row :283, tile :302 | month targets, year budget, approve | A | n/CompanyPeopleActions.swift `CompanyTargetsCard` (l.9) | Done | – |
| 29 | pk58 Perks | o/features/people/perks_and_hosting.js:139 | staff perks, cost, leave effect | A | n/CompanyPeopleActions.swift `CompanyPerksCard` (l.104) | Done | – |
| 30 | Academy / courses (acad36) | o/features/screens/restyled_screens.js:149 (V.academy); menus_and_week_report.js:18 (ACT.acad36) | courses per person with "fit" tags | A | per-person course menu in CompanyTeam.swift l.53 | Partial | academy screen, fit tags |
| 31 | payroll29 Payroll and bills | o/features/company/payday.js:403 (V.payroll29), R29.row :512, `pr29day/mode/ok/run` :468-500 | payday schedule, bills tab of Results | A | none in company (global auto-payroll toggle only: n/../Phone/SettingsView.swift:20) | Missing | page; engine `setPayrollMode` Unreachable |
| 32 | You card on managed company (R45.youCard) | o/features/people/managers_who_manage.js:82 | owner vs manager workload | A | none | Missing | (content UNVERIFIED) |
| 33 | org56 Organisation (chain org chart) | o/features/company/org_chart.js:131 | CEO/regional/chain levels above store | A | n/ExecutivePosts.swift (l.11) in CompanyChain | Done | – |
| 34 | res36 Results (tabs Months/Accounts/Transactions/Bills) | o/features/screens/fewer_places.js:66 | container page of the Money tab | A | n/CompanyMoney.swift P&L card + `ReportsScreen` link (l.134) | Partial | tab container; see 35-37 |
| 35 | month30 Monthly results | o/features/screens/tidier_screens_and_monthly_bills.js:64 | this month + last 12 months, income vs expenses by cost line | A | monthly column in P&L card (CompanyMoney) + ReportsScreen | Partial | 12-month drill-down cards (UNVERIFIED) |
| 36 | Accounts (R6FIN.books: P&L, Balance, Cash flow, Tax) | o/features/screens/restyled_screens.js:80 (via CT.finPart money.js:17) | period chips, accountant "says", annual accounts due, invoice sale, credit checks | B (finance book) | n/CompanyMoney.swift "Profit and loss" card (l.71) | Partial | Balance, Cash flow, Tax tabs, year/last-year columns, "accountant says", filing due |
| 37 | Transactions (R6FIN.tx) | restyled_screens.js:112 | last 20 ledger entries (co.tx) | A (list) | none | Missing | whole list |
| 38 | payself Pay yourself | o/features/sales/realistic_odds.js:152 (V.payself); titles restyled_screens.js:23; `cinject/cdraw/cdiv/cosal` money.js:99-136 | put money in, take out/dividend, owner salary | A (form) | n/CompanyMoney.swift "Move money" (l.53) | Partial | owner salary (engine `setOwnerSalary` Unreachable), % chips |
| 39 | Loans (borrow, repay sheet) | money.js:154-190 (`loansheet/loanterm/loango/repaysheet/repaygo`) | choose amount/term/guarantee, repay early | A | n/CompanyMoney.swift borrow card (l.87; fixed 60 months) | Partial | term choice, personal guarantee, early-repay sheet for company loans |
| 40 | Sell unpaid invoices (`invsheet`) | money.js:46-62; engine money.js invoiceSale/sellInvoices | bank buys receivables for a fee | A (confirm) | none (no `invoiceSale` in Engine/Sources by grep) | Missing | engine + UI |
| 41 | Ownership and value (FIN/DEAL 'value'; CT.ownersRow, CT.marketRow, ownedThrough; V.own27) | money.js:17; deals.js:21; o/features/company/owner_investors.js:265 (V.own27), :296; market_map_and_reviews.js:481 | value, share, investors, franchisee terms, holding company | A | n/CompanyOwnership.swift (l.8) | Partial | franchisee terms inside value card; "owned through holding" (holding side done in CompanyHolding) |
| 42 | Sell company / shares (V.sale, saletalk) | o/features/player/selling_startups_and_crisis.js:38 (V.sale); rivals_holdings_software.js:210 (saletalk); R7DEAL.sell :257 | list on market, buyer offers, negotiate | B | n/CompanySaleSection.swift (l.9) | Partial | negotiation screen (UNVERIFIED) |
| 43 | Legal form + accountant + advisers (FIN 'legal'; CT.advisers; tcAS convert sheet; provsheet) | money.js:~44,137-153; o/ui/screens/providers.js:20-100 | choose accountant/insurer/other advisers by rating or own firm, convert sole trader -> limited | B (provider picker) | n/CompanyOtherSections.swift `accountant` (l.118) | Partial | convert to limited (engine `convertToLimited` Unreachable), own-group adviser (`chooseOwnAdviser` Unreachable), `chooseAdviser` Unreachable |
| 44 | Close down (FIN/DEAL 'close', `winduo`) | deals.js:182; money row view.js:100 | wind up company | A (confirm) | none | Unreachable | engine `closeCompany` / `windUpCompany` have no UI caller |
| 45 | Premises and equipment hub (CT.eq) | o/ui/company/assets.js:58-73 | split: premises + each equipment kind; counts vs standard | B (catalogue) | n/CompanyEquipment.swift `CompanyEquipmentScreen` (l.33; tabs Needed/Owned/Fleet/Software/Premises) | Done | – |
| 46 | Equipment/vehicle shop (V.shop, eqbrand/eqsheet/buyeq/buyveh) | o/features/company/realistic_buying.js:742; assets.js:170-280 | new/used/finance/lease, brand -> model -> quantity, service, sell | B | n/CompanyEquipment.swift `EquipmentShopView` (l.396) | Done | – |
| 47 | Premises picker (premCard/premsheet/premset) | assets.js:127-168 | five places, rent vs buy, deposit | A | n/CompanyEquipment.swift premises (l.339-362) + give-up premises CompanyOtherSections l.101 | Done | – |
| 48 | Documents and permits (CT.doc, docsCard, moredocs, applydoc/applydoc2, pickacc) | assets.js:55,74-125 | required/optional documents, apply, status, wait weeks | A | none for normal companies (only chain docs via n/CompanyFranchise.swift:117 `applyForChainDocument`) | Missing | page; engine Businesses/Documents.swift `applyDoc` exists but no Simulation action wrapper found |
| 49 | Insurance (CT.insurance) | view.js:594 (piped trades_in_hours.js:597, tidier_screens...:168); `toggleins`, provsheet 'ins' | choose insurer, policy toggles, manager keeps insurance | A | none (n/CompanyFinanceBook.swift insurer products are the *insurance trade*, not this page) | Unreachable | engine `toggleInsurancePolicy`, `chooseAdviser` without UI |
| 50 | Suppliers (CT.supply) + supply chain | deals.js:221-253 (`srcv/srcc/fixv`); V.chain27 o/features/company/intercompany_supply.js:178; CT.supplyChainRow :259 | choose goods supplier/class, repair supplier, supply from own companies | A | n/CompanySourcing.swift + `CompanySupply` (n/CompanyChain.swift:267) | Partial | repair/fix supplier (`chooseRepairSupplier` Unreachable) |
| 51 | Chain page (V.chain12) + grow into chain (R12.growX) + New store (V.store13) + Stores (V.brand56) | o/features/company/shelf_stock_chains_boards.js:186; chain_registration_and_boards.js:29/41,56; branches_and_addresses.js:86; `ch12*` | register chain, name it, rules, add companies, new store, lend between stores | C | n/CompanyChain.swift (`GrowIntoChain` l.40, `ChainOverview` l.95, `StoreRules` l.229) | Done | rename chain (`renameChain` Unreachable) |
| 52 | Franchise (CT.franchisor, V.frtalk56, V.brandneg, frmast/frset/frlaunch) | deals.js:196,357-375; o/features/company/franchise_talks.js:76; o/ui/screens/companies_list.js:398 | franchise out concept, applicants, master franchise, being a franchisee | B | n/CompanyFranchise.swift (+ `FranchiseTalkView` l.237), FranchiseBrandsView.swift | Done | – |
| 53 | Expand abroad (CT.abroad) | deals.js:309-356 (`abrset/abrgo`); o/features/company/money_abroad.js | open in another country/city | A | none | Unreachable | engine `expandAbroad`/`abroadOptions` without UI |
| 54 | Brand reach (DEAL 'reach') | deals.js:~56 (reachOf label, outlets, countries, next level) | KPI+rows | A | none found | Missing | (UNVERIFIED whether ChainOverview shows reach) |
| 55 | Develop something new (RD56) | o/features/company/product_development.js:13 (card; `rd56go` :78) | R&D project, weeks, cost | A | n/CompanyOtherSections.swift development (l.58) | Done | – |
| 56 | Rename / rebrand (RN56) | o/features/company/rename_and_rebrand.js:26 (`rn56`), :58 (`rb56`) | rename company, rebrand chain | A (form) | none | Unreachable | engine `renameCompany`, `renameChain` without UI |
| 57 | IT security (V.cy56) | o/features/world/cyber_attacks.js:185 | level, backups, training | A | n/CompanyCustomers.swift IT security (l.85) | Done | – |
| 58 | Boards (R12.boardRow; V.boards12, V.board12, V.bmeet12; old boardView) | o/features/company/shelf_stock_chains_boards.js:460,425,392,550; chain_registration_and_boards.js:215 (second boardView, `bd13*`) | seats, advisers, meeting items, emergency decisions | B (board/meeting) | n/GroupBoards.swift `BoardsGroupSection` (l.8; group level) | Partial | per-company board row on Company tab (it lives in Group); two boardView implementations in orig, load-order dependent (UNVERIFIED, not claimed D) |
| 59 | Stock / upkeep / stock policy | view.js:~315 (opsPart 'upkeep'), `stockpol`, `maint`; family autostock family.js:32 | lean/normal/safe stock, maintenance | A | n/CompanyOperations.swift (l.44-51) | Partial | auto-stock flag (`setAutoStock` Unreachable) |
| 60 | Owner time (ops 'time') | view.js:~305 (ownerHoursRow, `ownhrs`) | hours/week by owner | A | n/CompanyOperations.swift "Your time" (l.29) | Done | – |
| 61 | Football club (ops 'table': CT.clubTable/clubSp/clubPeople) | o/ui/screens/club.js:130/78/103; V.clubs :13 | league table, budget, wages, tickets, squad | C | n/CompanyClub.swift (l.9) + ClubMarketView | Done | – |
| 62 | Energy / oil & gas (energyPanel, oilPanel, oilexp/oilacq/oilbuy) | o/ui/company/family.js:45,156-184 | power plant, build MW, fields, explore/buy stake | C | n/CompanyEnergy.swift (l.31) | Done | – |
| 63 | Salmon farm (salmonPanel) | family.js:27; autostock | cohorts, feed, harvest | C | n/CompanyEnergy.swift `CompanySalmon` (l.155) | Done | auto-stock Unreachable |
| 64 | Property / rental (propPanel; propsheet, marketprop, leaseprop, sellto, buyprop, sellprop, renprop) | family.js:82-155 | portfolio, listings with LTV, tenants/buyers | C | n/CompanyProperties.swift (l.9) | Done | – |
| 65 | Finance trades (finPanel; insurance products `prodtog`) | family.js:37,55-72 | insurer/bank/fund book, product approval, verified sellers | B (finance book) | n/CompanyFinanceBook.swift (l.9) | Done | – |
| 66 | Project/construction (devPanel, devsheet, devgo, devprice; order book) | family.js:185-218; famOv :14 | jobs, backlog, developments | C | n/CompanyProjects.swift (l.10) + ProjectsView.swift | Done | – |
| 67 | Holding company (tohold, V.holdings, V.newhold) | deals.js:174; rivals_holdings_software.js:295/302 | put companies under a holding, group tax, move money | C | n/CompanyHolding.swift (l.9, `NewHoldingView` l.108) | Done | – |
| 68 | OPS 'biz' triple-page ("Prices, upkeep, choices") | view.js:321 (opsPart), :~295 OPS_SUB.biz | prices+upkeep+choices side by side | D | – | n/a | D evidence: not in `OPS_ORD` (view.js ~345) nor in `opsKeys0 has{}` and no link emits `s:'biz'` (grep `s: *'biz'` over o/: no hits) |
| 69 | Old finPart bodies 'owner','books','tx' (+ 'books' tabsRow) | money.js:22-35,43 | old Put-in/Take-out card, old P&L card, old tx list | D | rows 36, 37, 38 | n/a | D evidence: money.js:17 `if (window.R6FIN && window.R6FIN[k]) { const r6 = R6FIN[k](...); if (r6 != null) return r6; }` and R6FIN.owner/books/tx are defined restyled_screens.js:38/80/112 returning strings, so the old branches never run |
| 70 | Old instant-offers 'sell' branch in dealPart | deals.js:43-44 (+ ACT.sellco/sellsh :148/:163) | instant buyer offers for company/shares | D | row 42 | n/a | D evidence: deals.js:18 `window.R7DEAL[k]` override; R7DEAL.sell at rivals_holdings_software.js:257 returns a non-null string and its comment says "the money page no longer has instant offers: selling goes through the market" (-> V.sale). ACT.sellco/sellsh remain only wrapped by owner_investors.js:177 (use elsewhere UNVERIFIED) |
| 71 | DEAL_SUB value / sell / close duplicates of FIN_SUB value / sell / close | deals.js:7,12,14 vs money.js:7,9,13,17 | same bodies | D | rows 41, 42, 44 | n/a | D evidence: money.js:17 renders `dealPart(co,bd,'value')+dealPart(co,bd,'sell')` and money.js:18 `if (k==='sell'||k==='close') return dealPart(...)`; route view.js:28 sends deal/value|sell to the money tab. Counted once as rows 41/42/44; this row = the duplicate registry entries |

### Company-level sheets / popups that exist only as modal flows (`openSheet`/`confirmThen`; no tab of their own)
- Campaign planner `plopen` (view.js ~425; row 8); automatic setup confirm `autoset` (view.js:~270); promote acting manager `promoset/promogo/promoboss` (view.js ~212; row 27).
- Equipment: `eqbrand` brand sheet (assets.js:218), `eqsheet` model sheet (:226), `buyeq/buyveh/sellveh/selleq/repaireq` (:237-278) -> native EquipmentShopView/Condition (Done).
- Documents: `moredocs` optional-document sheet (assets.js:101), `docsall` (:38), `applydoc2` (:107) -> native Missing (row 48).
- Premises `premsheet` (assets.js:141) -> native Done.
- Finance: `invsheet` (money.js:51; Missing), `loansheet/loanterm/loango/repaysheet/repaygo` (:154-190; Partial), `tcAS` convert-to-limited sheet (:137; Unreachable), provider picker `provsheet` (providers.js:50) and `ownpick`/`pickown` (:44; Unreachable), `cdiv/cdraw/cinject` (money.js:99-131; Done in "Move money").
- Customers: `acc39` account sheet, `ct56` contract profile sheet (deals.js:101), `acctmeet/acctdrop` confirm (Done/UNVERIFIED).
- Rivals: `rivbuy` offer sheet and `rivoffer` result sheet (deals.js:273-291) -> native RivalSheet (Done).
- Property sheets `propsheet/marketprop/leaseprop/sellto` (family.js:87-125), oil `oilacq` (:173), development `devsheet` (:199) -> native Done inside CompanyProperties/CompanyEnergy/CompanyProjects.
- Staff: `raisesheet` (people.js:267), `coursesheet` (:290), `hrole` "Other roles" sheet (:371) -> native: raise (5% only), course menu (Done), other roles (Missing).
- Franchise: `frmast/frset/frlaunch` (deals.js:357-375) -> native Done.
- Confirm flows: `mgrfire` (people.js:512), `acctdrop` (deals.js:139), `winduo` close down (deals.js:182; Unreachable), `setknob` documents-needed confirm (view.js ~300; Missing).

### Notes
- V.wx56 (weather & tourists, o/features/world/weather_and_tourism.js:262) and V.market/mktdetail/reviews (world-level) are NOT company tabs; excluded. Native has MarketView/MarketDetailView (n/CompanyMarket.swift:418/527).
- Row 3-6 are hubs; they are counted as items because the tab layout itself is a design decision (native uses different tabs).
- Family cards on Overview (Stock, Members, House result, Order book, Portfolio) are rolled into row 1 and rows 59-66; whether the native Overview shows Stock/Members/House result is UNVERIFIED.
- Engine functions with no UI caller (grep over App/): closeCompany, windUpCompany, convertToLimited, expandAbroad, toggleInsurancePolicy, chooseAdviser, chooseOwnAdviser, renameCompany, renameChain, setOwnerSalary, setCreditCheck, setAutoStock, setPayrollMode, talkToStaff, setManagerDuty, setManagerProfitBonus, setRightHand, requestAnalystReport, setPerformanceAnalystAuto, chooseRepairSupplier, reopenCompany, signContract, merge.

## 3. Native app: navigation, views, dead and duplicate UI

### Counts

| Item | Count |
|---|---|
| View structs in Features/Core (incl. private helpers) | 125 |
| Design structs/modifiers/styles (Design/) | 31 |
| Never instantiated (Features) | 2 (MoneyView, EmpireCard) |
| Never used (Design) | 4 (ScreenHeader, MiniBars, Ring, AmbientLight) |
| Reachable Features views | 123 |
| Dead or silent buttons (found by grep, partial) | 1 dead deep link + 1 dead insight link + 24 silent `store.act` buttons (see 3b) |
| Engine funcs in GameEngine extensions (4-space-indent funcs only) | 512 |
| Engine funcs with zero references in App | 105 (50 mutating actions, 55 read helpers) |

### 1. Navigation graph

Root: `LedgerApp` -> `RootView` -> StartView (no engine) / GameOverView / `GameShell`. Overlays: ToastView, and an error alert driven by `store.errorText`.

`GameShell` -> `PhoneShell` (TabView, iPhone) or `SidebarShell` (NavigationSplitView, iPad). Both iterate `AppTab` (company, team, group, projects, inbox) through `TabContent`. Shared sheet: `PhoneView` via `store.showPhone`.

| Tab | Root view | NavigationStack path | Pushes or presents |
|---|---|---|---|
| Company | CompaniesView | `[CompanyRoute]` (.company(id), .newCompany, .market) | CompanyDetailView, NewCompanyView, MarketView. Toolbar "+" and a "Choose a trade" button push .newCompany; `phoneToolbar()` opens the Phone sheet. HomeSummary and AdvanceBar sit in the same screen. |
| Team | TeamView | none (its own stack, no destinations) | Rows are Buttons that set `companySection=.staff`, `openCompanyID`, `tab=.company`. Group-level rows set `tab=.group` only. |
| Group | GroupView (parts: Holdings / Money) | `[CompanyRoute]`, same destinations | Holdings part shows GroupSummary, a link to .market, HostingSection, ExecutivePosts(chainID nil), HeadOfficeSection, holding-company links, ChainsGroupSection, BoardsGroupSection. Money part shows FinanceView. |
| Projects | ProjectsView | none | Rows set `companySection=.projects`, `openCompanyID`, `tab=.company`. Also embeds VenturesContent. |
| Inbox | InboxView (All / Decisions / Risks / Updates) | none | MessageCard answers via `store.answer`. |

Phone sheet (`PhoneView`, `[PhoneDestination]`): News, Stats, Achievements, Rich list, Biggest companies (RankingView), World around you, Activity, Luxury, Settings. Inside these, NavigationLinks lead to AchievementsView (from TrophiesPreview in Stats), and ActivityView (also from FinanceView).

CompanyDetailView sections (`CompanySection`): Overview, Projects, Team, Finances, Operations, Marketing, Customers, Market, Setup, Properties, Book, Plant, Fish, Holding, Club, Chain. `sections(co, e)` returns:

| Company state or type | Sections shown |
|---|---|
| status == .setup | own + Setup, Overview, Finances. Setup is forced selected on appear. |
| type hold | Overview, Holding, Finances |
| type club | Overview, Club, Finances |
| type power or oilgas | Overview, Plant, then Team, Finances, Operations, Marketing, Customers, Market (+Chain if relevant) |
| type salmon | Overview, Fish, then the same standard set |
| family rent | Overview, Properties, then the standard set |
| family fin | Overview, Book, then the standard set |
| family project | Overview, Projects, then the standard set |
| any other open or closed company | Overview, Team, Finances, Operations, Marketing, Customers, Market, plus Chain (`CompanyChain.isRelevant`: not hold or club, open or closed) |

Deep links via GameStore:

| Property | Set by | Consumed by | Status |
|---|---|---|---|
| `tab` | many | PhoneShell and SidebarShell | works |
| `openCompanyID` | TeamView, ProjectsView, NewCompanyView, FranchiseBrandsView, CompanyClub, CompanyHolding, CompanyMarket (rival buy and absorb), `go(.openCompany)` | CompaniesView `onAppear` and `onChange`, replaces path with `[.company(id)]` | works. CompanyMarket sets `openCompanyID` without setting `tab`. It is only reachable inside the Company tab, so this is OK. |
| `companySection` | TeamView (.staff), ProjectsView (.projects) | CompanyDetailView `onAppear`, honoured only if in `sections()` | works, but silently falls back to Overview for hold and club companies (no Team section). TeamView lists a holding's manager row, so that tap lands on Overview. |
| `moneySection` | `go(.openLoans/.openInvest/.openTax)`, ReportPrompt, BoardsGroupSection | GroupView (switches to Money part) then FinanceView `onAppear` | works |
| `reportRequest` | ReportPrompt | ReportsView and ReportsContent | works |
| `openMessageID` | `go(.openMessage)` | InboxView `.onChange` only (no `onAppear`) | RISK: if the Inbox tab has not been built yet, `onChange` never fires and the id is never cleared. Also does nothing if the message is filtered out by the current sub-tab. UNVERIFIED at runtime. |
| `phoneDestination` | NOTHING (grep: only declared in GameStore and cleared in PhoneView) | PhoneView | DEAD deep link. `showPhone` is set directly instead. |
| `showNewCompany` | `go(.newCompany)` | CompaniesView | works |
| `showPhone` | PhoneToolbar and `phoneDestination` didSet | GameShell sheet | works |

Sheets, covers, dialogs (grep, complete for `.sheet`, `.confirmationDialog`, `.alert`):
- Sheets: PhoneView (GameShell), TradeSheet (InvestView), RivalSheet and PriceWarSheet (CompanyMarket), PromotionSheet (CompanyTeam), club offer sheet (CompanyClub), paste-save sheet (StartView).
- `fullScreenCover`: none in the app.
- Confirmation dialogs (about 30): Settings quit; Money people actions (host, lend, hire fund manager, dismiss fund manager, finance manager); Luxury (sell, buy via company); CompanySale; ExecutivePosts release; Energy drill; Club found; Team fire; TeamRoster release; Franchise leave and terminate; Properties sell and buy; Equipment (2); PeopleActions (targets, perks, successor); Management (manager, assistant); Market price change.
- No `fullScreenCover` or popover anywhere.

### 2. Screen / view inventory

Status column: R = reachable. Engine calls are the engine funcs the file calls (grep of `.name(` against engine func names; may omit calls on engine properties).

#### Shell, Home, Inbox, Start, Reports

| File | Struct | Purpose | Engine calls | Status |
|---|---|---|---|---|
| LedgerApp.swift | LedgerApp | @main | none | R |
| Root/RootView.swift | RootView, GameShell, PhoneShell, SidebarShell, TabContent, ToastView | shell and toast | none | R |
| Root/PhoneToolbar.swift | PhoneToolbar | "More" button | none | R |
| Root/GameOverView.swift | GameOverView | game over | none | R |
| Start/StartView.swift | StartView | new game, load, paste import | none (store.newGame, importLegacy) | R |
| Home/HomeView.swift | HomeSummary, HomeHeader, NetWorthSection, PeriodPicker, AdvanceBar | top of Company tab: net worth, chart, advance-day bar | companyHealth, openCompany, tradeName | R |
| Home/HomeView.swift | EmpireCard | duplicate of the Company list | companyHealth | UNREACHABLE (0 refs) |
| Home/SuggestionCard.swift | SuggestionCard, SuggestionRow | next-step suggestions, `store.go` | suggestions | R |
| Home/ComingUpCard.swift | ComingUpCard | upcoming payments; NavigationLink to FinanceView | financeOverview | R |
| Home/FirstStepsCard.swift | FirstStepsCard | first steps | firstSteps | R |
| Home/GoalsCard.swift | GoalsCard | daily goal and ambition | ambitionMilestones, chooseAmbition, claimDailyGoal, claimFirstStep, dailyGoal | R |
| Inbox/InboxView.swift | InboxView, MessageCard | decisions and news | localized (answer via store) | R |
| Reports/ReportPrompt.swift | ReportPromptSection | "Last month/quarter" prompt, deep link to Reports | pendingReportPrompt, dismissReportPrompt | R |
| Reports/ReportsView.swift | ReportsScreen, ReportsContent | P&L and balance reports (group or one company) | reports, openCompany, currency | R (ReportsScreen via CompanyMoney link, ReportsContent via FinanceView) |
| Reports/ReportParts.swift | ReportRef, ReportFormat, ReportTableRow, ReportTableHeader, ReportLine, PnLTable | report parts | none | R |

#### Company tab, company list, Group, Team, Projects

| File | Struct | Purpose | Engine calls | Status |
|---|---|---|---|---|
| Companies/CompaniesView.swift | CompaniesView, GroupSummary (used by GroupView), CompanyTable (iPad), CompanyRow, HealthChip, StatusChip, RunwayText | company list | companyHealth, cityName, tradeName | R |
| Companies/CompanyDetailView.swift | CompanyDetailView, CompanyOverview, CompanySetupSection | one company, overview, setup | insights, companyHealth, openCompany, quickSetup, openingChecklist, tradeInfo | R |
| Companies/CompanyTeam.swift | CompanyTeam | Team section: management, roster, targets, perks, labour, staff list | hire, fire, raise, warnStaff, layOffStaff, searchWorkers, sendOnCourse, completePaperwork, marketAnalystVerdict | R |
| Companies/CompanyManagement.swift | CompanyManagement, PromotionSheet | manager and assistant manager | hireManager, dismissManager, hireAssistant, dismissAssistant, toggleAssistantDuty, searchManagers, searchAssistants, setManagerAuthority, offerPromotion, interviewManager and more | R |
| Companies/CompanyTeamRoster.swift | CompanyTeamRoster | roles above the manager (ceo, department heads, region) | teamSlots, hireTeam, releaseTeam, searchTeam, setTeamAuthority | R |
| Companies/CompanyPeopleActions.swift | CompanyTargetsCard, CompanyPerksCard, SuccessorSection | monthly targets, staff perks, successor | setTargets, toggleStaffPerk, findSuccessor, approveBudget | R |
| Companies/CompanyLabourCard.swift | CompanyLabourCard | labour market card | currency | R |
| Companies/CompanyOtherSections.swift | CompanyOtherSections, StaffContractMenu, HireOptionsMenu, ChainStaffShortages | complaints, accountant, staff contract menus | answerComplaint, changeAccountant, setStaffHours, offerFullTime, offerPartTime, toggleSeason, setPayModel, hire, lendWorker | R |
| Companies/CompanyProjects.swift | CompanyProjects, JobList, DevelopmentList | jobs, tenders, developments | projectBoard, bidOnTender, withdrawBid, startDevelopment, setDevelopmentPrice, setManagerBids | R (family project) |
| Companies/CompanyContracts.swift | CompanyContracts | volume contracts and tenders | bidOnTender, endContract, volumeContracts, bookedOrders | R (no direct caller listed in my grep; reached through Operations or Customers, UNVERIFIED) |
| Companies/CompanyMoney.swift | CompanyMoney | Finances: cash, loan, dividend, sale, ownership | financeOverview, takeLoan, putMoneyInto, takeMoneyOut, payDividend, maximumDividend | R |
| Companies/CompanySaleSection.swift | CompanySaleSection | sell the company | grep: sells via store | R |
| Companies/CompanyOwnership.swift | CompanyOwnershipSection | owners, funding, share sales, listing | pitchToInvestors, acceptFundingOffer, sellPrivateShares, listSharesForSale, buyBackStake, listHoldingOnExchange | R |
| Companies/CompanyOperations.swift | CompanyOperations | knobs, price, stock, maintenance, owner hours | setKnob, setPriceLevel, setStockPolicy, setMaintenance, setOwnerHours | R |
| Companies/CompanySourcing.swift | CompanySourcing | suppliers | chooseGoodsClass, chooseGoodsSupplier, sourcingOffers | R |
| Companies/CompanyMarketing.swift, CompanyWaysToSell.swift | CompanyMarketing, CompanyWaysToSell | campaigns and sales channels | setCampaign, setWayToSell | R |
| Companies/CompanyCustomers.swift | CompanyCustomers, AccountRow | accounts and cyber | keyAccountInfo, meetAccount, dropAccount, setCyberLevel, trainStaff | R |
| Companies/CompanyEquipment.swift | EquipmentEntryRow, CompanyEquipmentScreen, EquipmentShopView | equipment screens (pushed from Operations and Setup) | buy, sell, lease, service, premises | R |
| Companies/CompanyProperties.swift | CompanyProperties | rental properties | buyProperty, sellProperty, renovateProperty, leaseSpace | R |
| Companies/CompanyFinanceBook.swift | CompanyFinanceBook | insurer, bank, fund book | financeBook, setInsuranceProduct, verifySalesperson | R |
| Companies/CompanyEnergy.swift | FlatRow (shared), CompanyEnergy, CompanySalmon | power plant, oil, salmon | orderTurbines, exploreForOil, buyOilStake, setSalmonAutomation | R |
| Companies/CompanyHolding.swift | CompanyHolding, NewHoldingView | holding company | createHolding, holdingInvest, holdingDivest, moveToHolding, payDividend, putMoneyInto | R |
| Companies/CompanyClub.swift | CompanyClub, ClubMarketView | football club | buyClub, foundClub, hireCoach, signPlayer, signSponsor and more | R |
| Companies/CompanyChain.swift | CompanyChain, GrowIntoChain, ChainOverview, StoreRules, CompanySupply | chains, supply links | makeChain, joinChain, openChainStore, setChainRule, setStoreRule, setSupplier | R |
| Companies/CompanyFranchise.swift | CompanyFranchise, FranchiseeCard, FranchisorCard, FranchiseTalkView | franchising | launchFranchise, offerToApplicant, leaveFranchise, sellMasterFranchise | R |
| Companies/FranchiseBrandsView.swift | ChainsGroupSection, FranchisesView, BrandMeetingView, AnyButtonStyle, StartFranchisedView | brands you can join | applyToFranchiseBrand, negotiateFranchise, signFranchiseTerms, startFranchisedCompany | R |
| Companies/CompanyMarket.swift | CompanyMarket, RivalSheet, PriceWarSheet, MarketView, MarketDetailView | rivals, price, reviews, market share | absorbRival, buyRival, startPriceWar, changePrice, marketDetail and more | R (MarketView via Group link only) |
| Companies/GroupView.swift | GroupView | Group tab | companyHealth | R |
| Companies/GroupOffice.swift | HeadOfficeSection, SuppliersGroupSection | head office staff, manager reviews, meeting with all managers, supplier deals | hireOffice, fireOffice, callMeeting, runManagerScorecards, agreeSupplierDeal and more | R |
| Companies/GroupBoards.swift | BoardsGroupSection | board seats and meetings | holdBoardMeeting, decideMeetingItem, pickEmergency, fillSeat | R |
| Companies/ExecutivePosts.swift | ExecutivePosts | group MD, chain CEO, chain manager, regional managers | hireExecutive, releaseExecutive, searchExecutive, setExecutiveAuthority | R (Group and company Chain section) |
| Companies/TeamView.swift | TeamView | all people, grouped by company | teamSlots, tradeName, cityName | R |
| Companies/ProjectsView.swift | ProjectsView | projects and tenders per company plus ventures | projectBoard | R |

#### Phone sheet and Money (Group, Money part)

| File | Struct | Purpose | Engine calls | Status |
|---|---|---|---|---|
| Phone/PhoneView.swift | PhoneView | index of the 9 pages | yourRanking | R |
| Phone/FinanceView.swift | FinanceView | Money: Overview, Bank, Invest, Taxes, Costs, Reports (per-company: 4 of them) | financeOverview | R |
| Phone/FinanceView.swift | MoneyView | wrapper for FinanceView | none | UNREACHABLE (0 refs) |
| Phone/BankView.swift | BankContent | loans and deposits | takeLoan, repayLoan, openDeposit, moveToSavings, loanOffer | R |
| Phone/InvestView.swift | InvestContent, TradeSheet | market trading | quotes, buyInvestment, sellInvestment | R |
| Phone/VenturesView.swift | VenturesContent | startups, private equity, big meeting, stakes | 19 funcs (foundStartup, pitchStartupRound, commitToFund, acceptBigMeetingOffer and more) | R (Projects tab and InvestView) |
| Phone/MoneyPeopleActions.swift | HostingSection, LendPieceSection, FundManagerCard, HoldingFinanceManagerCard | luxury hosting, lending, fund manager | hostDeal, lendPiece, hireFundManager, addToFundManager, toggleHoldingFinanceManager | R |
| Phone/LuxuryView.swift | LuxuryView | luxury pieces | buyLuxury, sellLuxury, setCastleOpen, hostIslandRetreat | R |
| Phone/WorldView.swift | RankingView, WorldAroundView, DataAnalystCard | rankings, favours, maps, analyst | askForFavour, callInFavour, hireDataAnalyst, orderAnalystReport | R |
| Phone/NewCompanyView.swift | NewCompanyView, TradeDetailView | pick a trade, start company | startCompany | R |
| Phone/SettingsView.swift | SettingsView, StepperPill | policy, save, import, haptics | setPolicy | R |
| Phone/AchievementsView, ActivityView, NewsView, RichListView, StatsView | same names, plus TrophiesPreview | records, log, news | none (read properties) | R |

### 3. Dead, unreachable, engine-only, duplicated

#### 3a. Unreachable views (grep each struct name; zero instantiations)

| View | File | Note |
|---|---|---|
| MoneyView | Phone/FinanceView.swift:9 | stale doc "The Money tab"; the tab was folded into Group |
| EmpireCard | Home/HomeView.swift:128 | duplicate of the Company list rows |
| ScreenHeader | Design/Components.swift:90 | unused |
| MiniBars | Design/Components.swift:198 | unused |
| Ring | Design/Components.swift:394 | unused |
| AmbientLight | Design/Glass.swift:87 | unused |

Dead state or API: `GameStore.phoneDestination` is never set from outside PhoneView. `CompanyRoute.market` is handled in CompaniesView's `navigationDestination` but nothing in the Company stack appends it (only GroupView does). `CompanyOwnership` is named in doc strings, but the struct is `CompanyOwnershipSection`.

#### 3b. Dead and silent buttons

Methods: grep for empty closures (`Button { }`, `action: { }`), TODO, FIXME, `.disabled(true/false)` found NONE. Then I cross-checked `store.act { $0.xxx }` calls whose engine function returns a result or Bool and whose result is dropped with no toast on the same line (line-based grep, so multi-line calls are not covered).

| Item | File:line | Problem |
|---|---|---|
| Insight "Team →" link | CompanyDetailView.swift (diagnosis) and Engine Insights.swift:16 | engine emits section "staff" for ids "wages" and "paper", but the app maps with `CompanySection(rawValue: "Staff")`, and the enum raw value is "Team". Result is nil, so the link never renders for those two insights. Engine "operations" for "rivals" lands on Operations, where Market is probably meant. |
| `phoneDestination` deep link | GameStore.swift | never triggered (see above) |
| Found: <sector> | VenturesView:31 | result `Startups.FoundResult` ignored; always `product[0]`, `model[0]`; `who: sec.canBuildYourself ? "c2" : "c2"` has identical branches |
| Raise a round / Put in / + builder / Shut down | VenturesView:44-47 | no feedback; RoundResult and Bool ignored; Shut down has no confirmation |
| Accept round, toggleProductUse, Help, Sell half, Sell all | VenturesView:52, 59, 83, 84-85 | Bool or Result ignored, no toast |
| Invest in pitch | VenturesView:75 | `InvestResult` ignored |
| Commit to fund / Sell fund stake | VenturesView:104, 94 | `CommitResult` ignored |
| Accept and borrow, Counter -10%, Walk away | VenturesView:115-117 | `AcceptResult`, `Bool?` ignored |
| Accept funding offer, Counter, Decline | CompanyOwnership.swift:61-63 | Bool ignored |
| Buy back stake | CompanyOwnership.swift:26 | Bool ignored (only a Haptics tap) |
| Sell % of yours (secondary) | CompanyOwnership.swift:54 | `Funding.ShareResult` ignored, no toast |
| List shares for sale (10/25/34/49%) | CompanyOwnership.swift:70 | Bool ignored |
| Decline meeting item | GroupBoards.swift:160 | `ItemResult` ignored (Approve handles `.followUp`) |
| Release from holding | CompanyHolding.swift:50 | Bool ignored |
| Offer fixed salary | CompanyOtherSections.swift:168 | always shows "Now on a fixed salary." even if the engine returned false |
| Set commission rate, toggleOwnCar, toggleSeason | CompanyOtherSections.swift:180, 171, 161 | Bool ignored |
| toggleStaffPerk (turn off) | CompanyPeopleActions.swift:129 | `Bool?` ignored; the add path (line 140) shows "success" haptics regardless of result |
| Choose ambition | GoalsCard.swift:38 | shows "Your ambition" toast regardless of Bool |
| Release exec and release team | ExecutivePosts.swift:59, CompanyTeamRoster.swift:37 | `_ =` explicitly discards the result |
| setPolicy | SettingsView.swift:57 | `_ =` discard (no failure expected) |

Also: raise pay 5%, completePaperwork, and similar Team menu actions only give a haptic tap, no toast (CompanyTeam.swift, grep).

#### 3c. Engine actions no app file calls (word-match count 0 in App/Ledger)

Mutating actions with no UI caller (50). "tests" means referenced from Engine/Tests; "eng" means used inside Engine/Sources by something else.

| Group | Functions | Player-facing gap |
|---|---|---|
| Company lifecycle | closeCompany, windUpCompany (windUpEstimate), reopenCompany, renameCompany (renameCost), renameChain, convertToLimited (rebrandCost) | The player cannot close, wind up, rename, or convert a company anywhere |
| Software products | startSoftware, setSoftwareModel, setSoftwareCoders, setSoftwareInternalPercent, setSoftwareSelfCoding, useOwnSoftware (softwareProduct, ownSoftwareOffers) | whole feature has no UI |
| Executive and office | setRightHand, setReports, setGroupLimit, setManagerDuty, setManagerProfitBonus, setPerformanceAnalystAuto, toggleOfficeAssignment, requestAnalystReport, recordPushedThrough, releaseGroupCEO, meetForProposals, lendFromSister (managerScorecard, personReport, officeRoleResult) | head-office features partly exposed through GroupOffice only |
| Ventures | askBuyer, counterBuyer, pitchProductToRival, setProductInternalPrice, toggleOwnerHoursOnProduct, privateEquityOffers (the app uses privateEquityOffersOnTable instead), canRaiseFunding, raisePlan, startupPlan, startupInterest | partial |
| Company tab | chooseAdviser, chooseOwnAdviser, dismissStaff (the app uses `fire`), expandAbroad (abroadOptions), talkToStaff, toggleInsurancePolicy, courseOffers, staffProfile | adviser and abroad expansion have no UI |
| Settings and flags | setAutoStock, setCreditCheck, setInflationHold, setFirstStepsHidden, setOwnerSalary, setPayrollMode, chooseRepairSupplier | no UI (the app uses setPolicy for payroll) |
| World and giving | hostYachtDinner, startFoundation (giftCost, giftDone, ambitionPerk, touristEvents, weatherForecast, weatherLine, monthlyResults) | giving, foundation and weather have no UI |
| Premises | moveBackHome (hasOutgrownHome, isHomeTrade, isWorkingFromHome, freeSpaceInYourBuildings, personalEquipmentNeed, offersOwnCar, taxiFleetClass, homeTradePlaceWord) | work-from-home flow absent |
| Reports and history | closeReportPeriods, openReportBaselines, resetHistory, contactsSummary | probably internal; UNVERIFIED |
| Read-only helpers also with 0 refs | accountSupplyLinks, adviserOffers, absorbRivalExtraCost, bigMeetingFinancing, boardCandidates, boardKey, chainOf, currentAdviser, currentGoodsSupplier, currentRepairSupplier, decisionChain, franchiseeInfo, groupLoanBalance, layoffCount, monthlyProfitSeries, ownAdviserFirms, ownAdviserOffer, projectInsights, rentalFinanceInsights, rivalTargetsForProduct, secondaryDiscount, staffStory, supplierCandidates, weeksSinceMeeting, weeksUntilNextPitch | |

Limitation: only funcs declared at 4-space indent inside GameEngine extensions were scanned; funcs declared on engine types outside those extensions, or multi-line signatures, are not counted. Some of these may be called from other engine code (eng uses: closeReportPeriods 1, contactsSummary 1, expandAbroad 2, hostYachtDinner 1, moveBackHome 1, openReportBaselines 1, resetHistory 1, setReports 2, startFoundation 1).

#### 3d. Duplicated UI logic

| Pattern | Where | Note |
|---|---|---|
| Candidate list with "Offer <rounded asking wage>" buttons | ExecutivePosts, CompanyTeamRoster, CompanyPeopleActions (successor), CompanyManagement (manager and assistant), GroupOffice, MoneyPeopleActions, CompanyTeam, WorldView | grep: `roundedStep`/`askingMonthlyWage` in 9 files; each has its own state `candidates`, search button, and hire switch. Strongest candidate for one shared view. |
| Authority picker "Asks you / Within limit / Full control" | ExecutivePosts:84, CompanyTeamRoster:61, CompanyManagement:85 | same three labels typed 3 times (one as Menu, one as SectionTabs) |
| `signed(_:)` | HomeView:104, ReportPrompt:42, ReportParts:16 | identical |
| `roleName(_:)` | TeamView:98, CompanyTeam:171 | identical |
| `pct(_:)` | StatsView:52, MoneyPeopleActions:118 | identical |
| Company list rows | CompanyRow (iPhone), CompanyTable (iPad), EmpireCard (dead) | EmpireCard dead copy |
| Group rows in Team vs ExecutivePosts | TeamView.groupLevel and ExecutivePosts.posts | same data (MD, chain CEO, chain manager, regional) read twice, TeamView read-only |
| HomeSummary vs GroupSummary | net worth card on Company tab and holdings card on Group | different numbers, overlapping KeyFigures |
| FlatRow defined in CompanyEnergy.swift | used by 10 files | shared component placed in a feature file |
| Two navigation stacks with identical `navigationDestination(for: CompanyRoute)` | CompaniesView:79, GroupView:28 | copy-paste |
| `pendingX` + `confirmationDialog(isPresented: Binding(get:set:))` | about 30 places | same boilerplate each time |

### 4. Reuse assessment

| Pattern | Status | Evidence |
|---|---|---|
| LedgerSection | generic template, ubiquitous | 160 uses |
| FlatRow | generic, mis-filed | 75 uses, defined in CompanyEnergy.swift |
| Card / GlassCard | generic | 41 and 7 uses |
| KeyFigures | generic | 30 uses |
| SectionTabs | generic (also used for non-section pickers such as authority) | 32 uses |
| ListRow, Chip, SectionLabel, ValueRow, AmountField | generic | 29, 36, 34, 15, 10 uses |
| Button styles (Quiet, Gold, SmallOutline, SmallGold) | generic | 119, 28, 45, 11 uses |
| Candidate hire list | NOT generic: re-implemented about 7 times | see 3d |
| Confirmation dialog | NOT generic: hand-written about 30 times | see 3d |
| Sheets | only 6 sheets; each is a one-off | RivalSheet, PriceWarSheet, PromotionSheet, TradeSheet, club offer, paste |
| One-off screens | FranchiseBrandsView, CompanyClub, CompanyEquipment (624 lines), CompanyMarket (582), VenturesView, LuxuryView, WorldView, Reports | large single-purpose files |
| ReportsContent, FinanceView(companyID:) | parameterised for group or company (good) | reused in Group and CompanyMoney |
| VenturesContent | reused in Projects tab and InvestView | embedded twice, so ventures appear in two places |

### 5. UI rule check

- No root, tab, or section is named Assistant, Regional, or Chief. Roots are Company, Team, Group, Projects, Inbox.
- "Assistant manager" appears as a LedgerSection inside Company > Team (CompanyManagement), and as "Assistant manager" for football clubs in CompanyClub. Acceptable (inside the company's Team section) but see below.
- "Regional manager" and "Chain CEO" exist as row labels only: TeamView entries (read-only), ExecutivePosts.
- "Managers vs assistants" is not split at a root level.

Placement problems:
1. Group-level and chain-level people (group MD, chain CEO, chain manager, regional managers, head office staff, manager reviews, "meeting with all managers", board seats) are hired and managed in the Group tab (ExecutivePosts, HeadOfficeSection, BoardsGroupSection) and in a company's Chain section, while the Team tab only lists them read-only and its Group rows merely jump to the Group tab without scrolling to ExecutivePosts. The Team tab is described as "everyone who works for you", yet it cannot act on them.
2. Other people live outside the Team tab: fund manager and finance manager (Group > Money > Invest / Holding), luxury hosting and lending (Luxury page in the Phone sheet), data analyst (World around you in the Phone sheet), staff perks and targets (Company > Team, fine), startup builders (Projects > Ventures).
3. Structure is spread across Company detail > Chain (chain overview and executive posts, franchise, supply), Group > Holdings (ChainsGroupSection, holding companies), and Company > Holding.
4. Holding companies are hidden from the Company list (`type != "hold"`) and appear only in Group > Holdings. The Team tab and the Projects tab, however, include them. A holding's Team deep link falls back to Overview because holdings have no Team section.
5. Market, reviews and rivals: Group > link to MarketView and Company > Market section both exist; HostingSection (luxury hosting) is embedded in Group and in CompanyMarket's rival page.

### 6. UNVERIFIED

- Whether the 24 listed silent buttons give feedback elsewhere in the engine (e.g. notices); I only read the call sites.
- Reachability of CompanyContracts, and the contents of CompanySaleSection, CompanyLabourCard, WorldView, LuxuryView, Settings, Stats beyond grep.
- Runtime behaviour of TabView lazy loading for the openMessageID risk.
- Engine funcs outside the scanned pattern; test usage was checked only for the 50 mutating funcs.

## 4. Engine: pipeline, not-ported and engine-only actions, duplicates, missing features

Per-id status of all 557 original actions: `docs/data/action_status.json` (verified in this audit; `tools/gen_parity.py` and the hand-edited MISSING_ACTIONS/PARITY docs are stale).

### 2. Simulation pipeline (verified from the call graph)

Entry: `GameEngine.nextDay()` (Simulation/GameEngine.swift:171).

```
nextDay()
  if day < 6:  day += 1; tradeAndPay(day); releaseDay(day)
  else (7th day over):
       closeReportPeriods()            // Reports.swift: week/month/year report closes BEFORE the next week is worked out
       rest.pend = null; day = 0
       stageWeek()   --> advanceWeek()  // the whole week is computed at once, its money/messages/news are held in rest.pend
       tradeAndPay(0); releaseDay(0)
  recordDay()
tradeAndPay(d) = DailyTrade.runDay -> ProjectWeek.runDay -> Payday.onDay      (payday + month-end bills run daily)
releaseDay(d)  = releases 1/7 of staged company cash, staged player lines, messages and news whose day == d

advanceWeek()  (GameEngine.swift:299-366)
  week += 1
  WorldWeek.economy ; Markets.weekly ; WorldWeek.competitors (rest.mk markets) ; FootballModel.leaguesWeek ; Markets.fundsWeekly ;
  Brokerage.weekly ; FinanceManager.weekly ; Luxury.weekly
  for each live company: CompanyWeek.run  (Documents, closeIfNobodyWorks, setup/closed/open week, complaints, Development, word of mouth,
        buzz, reach cap, Reviews, KeyAccounts, SalesWays, VolumeContracts, ProjectWeek.afterWeek; inside openWeek: RentalFinance/SpecialFamilies/
        ProjectDeveloper, weekEnd -> Marketing.weekly, StaffRoutine.weekly, ManagerModel.weekly, PersonalEquipment.weeklyCosts)
        then EventEngine.spawn (supported families only) ; trf traffic history
  Rivals.weekly (-> RivalGroups.weekly, WorldAround.weekly, monthly parts) ; PriceMoves ; Lawsuits ; Cyber ; MarketMap ; SoftwareProducts ;
  ProjectTenders ; AutoStaff ; Aftermath ; EventEngine.expire ; StrategicDecisions.weekly (-> Misconduct.weekly) ;
  Ventures.weekly (Startups, PrivateEquity, BigMeeting, Shareholders) ; Awards.weekly (-> CompanySale, RivalBids, RichList.monthly, Trophies.check) ;
  SpecialFamilies.weeklyAfter (-> HoldingModel, EnergyModel) ; Chains.weekly (Franchising, FranchiseBrands, IntercompanySupply, AccountSupply,
        RivalAbsorb, ManagerModel.groupWeekly = team/boards/executives/organisation/Headquarters.monthly) ;
  MiscWeekly.run (StaffProfile.trackWeek, PremisesExtras, Luxury.ownerWeek/riskChecks, StaffPerks, Giving, Ambitions, Stories, Press,
        WeatherEvents; month end: Suppliers.monthly)
  if isMonthEnd: MonthEnd.closeMonth   (per company close, tax group, FootballModel.monthly, autoDividends, PersonalFinance.monthly/advanceTaxMonthly,
        FX drift, Abroad.regulationMonth)
  if isYearEnd:  MonthEnd.closeYear    (flags reset, tax due, PersonalFinance.yearEnd, books roll, settleTax)
  ManagerTargets.weekly ; bankruptcy checks (cash / loan call / unpaid months) ; FinanceModel.insolventCompanies ; snapshot ; Failure.checkOver
```

Checked findings:

* **No weekly/monthly/yearly entry point is called twice and none is orphaned.** I listed every `static func weekly|monthly|yearly|runDay|onDay|week|weeklyAfter...` in Engine/Sources (about 90) and grepped qualified callers: each has exactly one call site (nested ones traced to advanceWeek: e.g. Documents/Reviews/KeyAccounts/SalesWays/VolumeContracts <- CompanyWeek.run; FranchiseBrands <- Franchising.weekly <- Chains.weekly; Misconduct.weekly <- StrategicDecisions.weekly; Headquarters.monthly <- ManagerModel.groupWeekly; RichList.monthly/CompanySale/RivalBids <- Awards.weekly). `Cyber.monthly` is only a read model (CustomerActions.swift:395-397); the monthly Cyber effect runs inside `Cyber.weekly` on isMonthEnd. `Awards.monthlyRevenue` (RichList.swift:123) is unused (dead).
* **Order differs from the original** (original `nextWeek0`, engine/core/week.js:59-110: econ, market, rivals, fb, clubLeagues, funds, invest, **startups, deferred sale payments**, then the company loop, then `expireMsgs`, **`monthEnd()` and `yearEnd()`**, bankruptcy, snapshot, and only then the `week.after` pipeline steps (luxury 10, owns 12, estates 14, PE 16, ... 55 feature weeklies, targets 56, tenders 57, inflation 60, ... bankrupt 70, deal of the week 92, rich list 93)). In Swift `Ventures.weekly` (startups, PE, deferred sale payments via CompanySale) runs **after** the company loop instead of before, `Luxury.weekly` runs **before** companies instead of after, and `MonthEnd.closeMonth/closeYear` run **after** Chains/Ventures/Rivals/MiscWeekly instead of right after the company loop. So month-end books, tax accrual and the monthly history line see franchise royalties, supply, rival and chain effects of the closing week that the original books in the next week. Effect size UNVERIFIED (no differential test of a month end with chains/franchises).
* Never run in Swift: original `week.after` 90 "monthly backup of the game" (the App does it: GameStore.swift:126,146 + SaveStore.backup, so it is covered at app level), 92 "the deal of the week", 92 "trades open as the net worth you earned grows" (UNL57), 20 "manager focus and job titles" (focus part), `S.al30` problem pop-ups (UI).
* Daily: Swift `Payday.onDay` runs every day incl. day 0 after the roll (GameEngine.swift:200-209). The original `day.after` steps "what each person did today", "day card notes", "firsts and milestones" (trophy check happens weekly in Swift via `Awards.weekly`), "managers keep everyone equipped", "when a company first went into the red" are not separate daily steps in Swift (UNVERIFIED equivalent timing).
* `MiscWeekly.monthly` contains only `Suppliers.monthly` although its comment says it covers `regulationMonth` (that one is in `MonthEnd.closeMonth`, MonthEnd.swift:233): comment is misleading, behaviour not duplicated.

#### 3.1 Not ported (7) and partial (7) and out of scope (11)

| Original id | Status | What is missing (evidence) |
|---|---|---|
| `dow56go` | NOT_PORTED | deal of the week (S.dow56, goals_and_awards.js) - no Swift counterpart |
| `firestaff` | COVERED_PARTIAL | App calls fire() (Hiring.fire, no cause/warnings/unfair dismissal); StaffProfile.dismiss via dismissStaff has no App caller |
| `gaoff` | NOT_PORTED | web analytics switch co.ga (grep analytics: none) |
| `gaon` | NOT_PORTED | web analytics switch co.ga (grep analytics: none) |
| `hysGo` | COVERED_PARTIAL | setKnob (PlayerActions.swift:49) only stores the option: no changeover cost/capacity penalty (changeover, hys56c), no multi-select toggle, no required-document check, no chain lock |
| `hysPick` | COVERED_PARTIAL | setKnob (PlayerActions.swift:49) only stores the option: no changeover cost/capacity penalty (changeover, hys56c), no multi-select toggle, no required-document check, no chain lock |
| `hysTog` | COVERED_PARTIAL | setKnob (PlayerActions.swift:49) only stores the option: no changeover cost/capacity penalty (changeover, hys56c), no multi-select toggle, no required-document check, no chain lock |
| `plgo` | COVERED_PARTIAL | setCampaign = setMkt only; campaign end week (mktEnd), target age group (mktT) and the advise() planner are not settable |
| `plopen` | COVERED_PARTIAL | setCampaign = setMkt only; campaign end week (mktEnd), target age group (mktT) and the advise() planner are not settable |
| `plset` | COVERED_PARTIAL | setCampaign = setMkt only; campaign end week (mktEnd), target age group (mktT) and the advise() planner are not settable |
| `pr29day` | NOT_PORTED | change of pay day: no function (grep nday/setPayDay: none) |
| `setconf` | NOT_PORTED | S.settings.confirm (confirm-before-spend preference) - no counterpart |
| `setfocus` | NOT_PORTED | manager focus plans co.focus/focusPlan/focusDraft (grep: none) |
| `setstory` | NOT_PORTED | life stories heir/laid/student/kid (STORY57) - newGame has no story parameter |
| `pro56 pro57 proask probuy prolink promanage proplan prorestore proskin proskinc prostore` | OUT_OF_SCOPE | Ledger Pro store, skins, free-vs-pro gating (App Store layer) |

#### 3.2 Engine-only (46): engine function exists, nothing in App/ calls it

| Original id | Swift function (file:line) / note |
|---|---|
| `abrgo` | expandAbroad (CompanyTabActions.swift:51); App has no caller |
| `abrset` | expandAbroad (CompanyTabActions.swift:51); App has no caller |
| `applydoc` | Documents.apply exists (Documents.swift:75); only wrapper is applyForChainDocument (chains); no per-company permit-apply action |
| `applydoc2` | Documents.apply exists (Documents.swift:75); only wrapper is applyForChainDocument (chains); no per-company permit-apply action |
| `arep` | requestAnalystReport (Engine/Sources/Simulation/ExecutiveActions.swift:112) |
| `autostock` | setAutoStock (Engine/Sources/Simulation/MiscActions.swift:220) |
| `b13go` | recordPushedThrough (Engine/Sources/Businesses/ManagerBoards.swift:273) |
| `ccheck` | setCreditCheck (Engine/Sources/Simulation/MiscActions.swift:218) |
| `clgo` | closeCompany (Engine/Sources/Simulation/MiscActions.swift:93) |
| `convgo` | convertToLimited (Engine/Sources/Simulation/MiscActions.swift:196) |
| `cosal` | setOwnerSalary (Engine/Sources/Simulation/PlayerActions.swift:171) |
| `fireceo` | releaseGroupCEO (Engine/Sources/Businesses/ManagerTeam.swift:442) |
| `found28` | Giving.give / startFoundation via GameEngine.give, startFoundation (WorldAndGivingActions.swift:17,22); no App caller |
| `fs58off` | setFirstStepsHidden (Engine/Sources/Simulation/MiscActions.swift:351) |
| `give28` | Giving.give / startFoundation via GameEngine.give, startFoundation (WorldAndGivingActions.swift:17,22); no App caller |
| `hqas` | toggleOfficeAssignment (Engine/Sources/Simulation/ExecutiveActions.swift:105) |
| `inflset` | setInflationHold (Engine/Sources/Simulation/MiscActions.swift:223) |
| `lh12set` | setRightHand (Engine/Sources/Businesses/Headquarters.swift:363) |
| `lx56din` | hostYachtDinner (Engine/Sources/Simulation/WorldAndGivingActions.swift:57) |
| `md56` | setManagerDuty (Engine/Sources/Businesses/ManagerProposals.swift:37) |
| `md56give` | setManagerDuty (Engine/Sources/Businesses/ManagerProposals.swift:37) |
| `mtgo2` | meetForProposals (Engine/Sources/Businesses/ManagerProposals.swift:159) |
| `ownpick` | chooseOwnAdviser (Engine/Sources/Simulation/CompanyTabActions.swift:32) |
| `ownsw` | useOwnSoftware (Engine/Sources/Simulation/CustomerActions.swift:506) |
| `p17go` | pitchProductToRival (Engine/Sources/Simulation/VentureActions.swift:122) |
| `p17open` | rivalTargetsForProduct (Engine/Sources/Simulation/VentureActions.swift:120) |
| `perfauto` | setPerformanceAnalystAuto (Engine/Sources/Simulation/ExecutiveActions.swift:107) |
| `pr29mode` | setPayrollMode (Engine/Sources/Simulation/PlayerActions.swift:207) |
| `pr29run` | Payday.runPayroll(.manual) only reachable from the inbox answer (Payday.swift:498); no player "run payroll now" wrapper |
| `provpick` | chooseAdviser (Engine/Sources/Simulation/CompanyTabActions.swift:26) |
| `rb56go` | renameChain (Engine/Sources/Simulation/MiscActions.swift:58) |
| `reopen` | reopenCompany (Engine/Sources/Simulation/MiscActions.swift:114) |
| `repset` | setReports (Engine/Sources/Businesses/Headquarters.swift:98) |
| `rn56go` | renameCompany (Engine/Sources/Simulation/MiscActions.swift:35) |
| `saleq` | askBuyer (Engine/Sources/Simulation/VentureActions.swift:23) |
| `saletalk` | counterBuyer (Engine/Sources/Simulation/VentureActions.swift:25) |
| `setbig` | setGroupLimit (Engine/Sources/Businesses/ManagerTeam.swift:449) |
| `swdev` | setSoftwareCoders (Engine/Sources/Simulation/CustomerActions.swift:501) |
| `swint` | setSoftwareInternalPercent (Engine/Sources/Simulation/CustomerActions.swift:504) |
| `swmodel` | setSoftwareModel (Engine/Sources/Simulation/CustomerActions.swift:503) |
| `swself` | setSoftwareSelfCoding (Engine/Sources/Simulation/CustomerActions.swift:502) |
| `tcAS` | create (Engine/Sources/Businesses/CompanySetup.swift:277) |
| `toggleins` | toggleInsurancePolicy (Engine/Sources/Simulation/CompanyTabActions.swift:39) |
| `w17int` | setProductInternalPrice (Engine/Sources/Simulation/VentureActions.swift:119) |
| `w17self` | toggleOwnerHoursOnProduct (Engine/Sources/Simulation/VentureActions.swift:116) |
| `winduo` | windUpCompany (Engine/Sources/Simulation/MiscActions.swift:151) |

Clusters: company lifecycle (`clgo`, `reopen`, `winduo`, `convgo`, `rn56go`, `rb56go`, `cosal`, `ccheck`, `autostock`, `inflset`, `tcAS`), own software product (`swdev swself swmodel swint ownsw`), startup product desk (`p17open p17go w17self w17int`), group office (`hqas lh12set perfauto repset setbig fireceo mtgo2 md56 md56give b13go arep`), abroad (`abrgo abrset`), giving back (`give28 found28`), advisers/insurance (`ownpick provpick toggleins`), payroll (`pr29mode pr29run`), sale talk (`saleq saletalk`), permits (`applydoc applydoc2`), yacht dinner (`lx56din`), first-steps hide (`fs58off`). A wider list (118 GameEngine functions in Simulation/ with no App reference, 71 of which are not even referenced elsewhere in Engine) is in `engine_only_funcs.tsv`.

### 4. Duplicate / parallel logic

#### 4.1 Dismissal and severance (3 paths, 2 reachable)
* `Hiring.fire` Hiring.swift:189-200 (pay notice+severance+fine as one "Severance" line) <- `PlayerActions.fire` PlayerActions.swift:104 <- App CompanyTeam.swift:126.
* `StaffProfile.dismiss` StaffProfile.swift:186-201 (documented warnings, unfair-dismissal settlement; internally calls Hiring.fire) <- `dismissStaff` CompanyTabActions.swift:94 <- **no App caller**.
* `ManagerModel.fire` ManagerPeople.swift:194-205 repeats the same "notice + severance + fine" booking as Hiring.swift:194-199 (the labour helper `World.terminationCost` WorldLabour.swift:24 is the single rule; the booking code is copied). Layoff preview `StaffProfile.layoffPreview` StaffProfile.swift:218-225 re-computes severance per person a third way (calls terminationCost without `withCause`).
#### 4.2 Hiring
* Two public `GameEngine.hire` overloads: PlayerActions.swift:94 (`ownCar:` flag) and MiscActions.swift:234 (`terms: Hiring.Terms`). Both end in `Hiring.hire` (Hiring.swift:138). App uses both: CompanyTeam.swift:163 (no terms, so no part-time/seasonal) and CompanyOtherSections.swift:229 (terms). Same candidate can be hired with or without terms depending on which screen.
* Role-specific parallel hires: `ManagerModel.hire` ManagerPeople.swift:176, `Headquarters.hire` Headquarters.swift:194, `FinanceManager.hire` FinanceManager.swift:94, `FootballModel` coach hire :534, `hireAssistant` ManagerPeople.swift:345, HQ data analyst `MarketMap.swift:299`. Non-player auto-hiring: ManagerWeek.swift:158,271, ManagerSeasonal.swift:77, AutoStaff.swift:29, CompanySetup.swift:490, RivalAbsorb.swift:85 (all call Hiring.hire; fine).
#### 4.3 Complaints
* `Satisfaction.answerComplaint` Satisfaction.swift:69 and `Complaints.answer` Complaints.swift:41 are the same function with different return mapping (`.sorry` vs `.ignore` result). Only `Complaints.answer` is called (CompanyTabActions.swift:65); the Satisfaction copy is dead (grep: no caller in Sources/App).
#### 4.4 Manager review
* `OfficeChecks.reviewManagerNow` OfficeChecks.swift:46-57 and `Headquarters.managerScorecards` Headquarters.swift:312-322 both call `Headquarters.review` and both write `lastRev {score,w}` themselves (OfficeChecks.swift:55 / Headquarters.swift:315): duplicated bookkeeping, drift risk.
#### 4.5 Lunch/meeting with a counterpart (4 copies of one rule)
* `Suppliers.meet` Suppliers.swift:97 (cooldown 4 weeks, cost scaledPrice(5000)), `Rivals.meet` Rivals.swift:712 (4 weeks, 4000, +4...9), `KeyAccounts.meet` KeyAccounts.swift:191, `ManagerModel.meet` ManagerPeople.swift:239. Cooldown/cost/gain constants are repeated per copy (mirrors the original which also has separate handlers; the constants could not be unified without checking each).
#### 4.6 Constants defined more than once
* Executive-search fee `scaledPrice(15000)`: ManagerPeople.swift:69, ManagerTeam.swift:242 and :337 (original has a per-role fee function `R.fee` with 15000 as default, ManagerTeam copies the default instead).
* Buyer valuation multiplier `need = 1.12` in GroupDeals.swift:72 and RivalBids.swift:32.
* Dividend/gain tax rate `c.dividendTax` used for capital gains in PersonalFinance.swift:24 and :79 (two copies of the gain-tax expression).
#### 4.7 Not duplicates (checked)
* Tenders: only one system. `VolumeTenders` (VolumeTenders.swift) is data + hooks on `ProjectTenders.Tender` (kind "vol"); `VolumeContracts` runs the awarded contract. `RivalBids` is the inbound counterpart (rivals bidding for your company). The three markets `WorldWeek.competitors` (creates/drifts `rest.mk`), `Rivals.weekly` (named rivals in the same `mk` records) and `RivalGroups.weekly` (`g27`) are stacked layers like the original, not copies.
* Company tax: single `MonthEnd.taxRate/accrueTax/settleTax` (MonthEnd.swift:19-57), reused by FinanceReport.swift:107.

### 5. Original features that exist but are not ported (by area)

Verified by id-set comparison against the *running original* (`dump*.json`) and by grep for the feature in Swift:

| Area | Missing in Swift | Count / evidence |
|---|---|---|
| Events (133 library events, 15 special kinds, 10 family event kinds, 29 country events) | none | 0 missing by id (events.json has exactly the 133 inventory ids; all 36 `ev27` ids and 29 country decisions present as `Def(id:)`; 4 extra Swift ids `m_bank m_bribe m_quality m_tax` are Swift-only misconduct decisions) |
| Trades | none | 0/67; equipment/standard/knob counts equal |
| Trophies | none | 0/106 (all ladder rungs included) |
| Ambitions | none | 0/63 milestone ids, 6 paths |
| Luxury | none | 0/45 pieces; gifts/estates present |
| Special families (energy, salmon, oil, club, holding, rental, finance, projects) | none by id; family models present | `isSupported` covers all 11 families (CompanyWeek.swift:15) |
| Marketing | **prime-time TV channels `prem_<CC>` x23** | original `initPremCh` (awareness.js:3-26) builds a national "very expensive media moment" channel per country (eff 34, `prem:1`, `only:CC`, 4 week minimum); Swift `marketing_insurance.json` CH has 11 channels and none with `prem`/`only`; `isPrimeTime`/`primeTimeActive` (Marketing.swift:148,153,175) and `onlyInCountry` (PlayerActions.swift:63) are therefore dead code. Country data (`media.prime`, `bigAd`) is in countries.json but unused. Also campaign length `mktEnd` unwritable and age-group targeting `mktT`/`fitAg`/`advise()` absent |
| Tenders / public work | 2 offers | trades `cons` ("Advisers for a state reorganisation") and `farm` ("Produce for the municipal kitchens") of the 34 tender trades; Swift states farm is skipped on purpose (VolumeTenders.swift:19), `cons` not mentioned |
| World / player start | life stories 4 of 5 (`heir`, `laid`, `student`, `kid`; only the plain start-up loan exists) | `features/player/life_stories.js`; no `story` parameter in `GameEngine.newGame` |
| Progression | trade unlocks (UNL57) | original starts with the 8 cheapest trades; others open at ~1/3 of start cost as earned net worth grows (`trade_unlocks.js`); Swift has no gating (grep "unlock" none) - all 67 trades are open from day one, which changes pacing and balance |
| Player goals | deal of the week | `goals_and_awards.js:42-95` (rival owner sells 20% under value / private sale at 15% off / share dip 12% with rebound); no `dow56` anywhere in Swift |
| People | manager focus plans (`setfocus`, `FOCUS_ACT`, `co.focus/focusPlan/focusW/askW`) | `ui/screens/mockup.js:420-520`, week.after step "manager focus and job titles"; no Swift counterpart |
| Company | web analytics switch (`co.ga`), pay-day change (`pr29day`), confirm-before-spend setting (`settings.confirm`) | small; no counterpart |
| Company knobs ("how you sell") | changeover cost/penalty, multi-select knobs, document prerequisites | see 3.5 (`hysGo/hysTog`) |
| Pro (paid) | Pro features (8: untl slots tycoon clubs world estates pe trades), 4 packs, 2 skins | out of scope for a native build |
| Presentation/UI-only features of the original with no engine need | problem pop-ups `al30` (Advisor/Insights partly replace), `unl36` look-ups, celebrations queue, picture library | UI |

Items in the previous docs that are NOT gaps any more (docs stale, see 6): trophies n1/rk/no1/top10 are present (Trophies*.swift ladders `n1`, `rk`, `no1`, `top10`); volume contracts and tenders for services/shops/carriers are ported (VolumeTenders.swift, VolumeContracts.swift); strategic decisions are complete (36 + 29 country); business awards rank by CompanyRanking revenue and growth (RichList.swift:137-138), "Fastest growing" exists; boards/CEO/MD/regional/team posts are ported (ManagerBoards/ManagerTeam/ManagerMeetings/ChainHierarchy).

### 7. Top gaps (ranked)

1. **Company lifecycle actions are not reachable from the App**: close, reopen, wind up, convert sole trader to limited, rename company/chain, owner salary, credit check, auto stock, inflation hold (`clgo reopen winduo convgo rn56go rb56go cosal ccheck autostock inflset` -> MiscActions.swift/PlayerActions.swift:171, zero App callers). A player cannot take a salary from a limited company or close a business.
2. **Trade unlocks (UNL57) and life stories (STORY57) missing**: all 67 trades open from day one and only the start-up-loan start exists; the original pacing/balance depends on both.
3. **Prime-time TV channels (23 of 34 marketing channels) not in the channel table**, plus campaign end date and age-group targeting; the prime-time engine code is dead. Marketing planner `plgo` is only `setMkt`.
4. **"How you sell" changeover (`hysGo/hysTog/hysPick`) reduced to a field write**: no changeover cost, no temporary capacity loss, no multi-select, no document check, no chain lock.
5. **Dismissal rules unreachable**: App uses `fire()`; warnings, "documented" vs unfair-dismissal settlement live in `StaffProfile.dismiss`/`dismissStaff` with no caller. Same pattern for `warnStaff`-based flow: the rules exist only in the engine.
6. **Month-end / year-end ordering differs from the original** (closeMonth/closeYear run after Chains, Ventures, Rivals, MiscWeekly instead of right after the company loop; startups/deferred sale payments after, not before, the company loop). Not covered by a differential test; effect UNVERIFIED but touches taxes, monthly history, franchise royalties.
7. **46 engine-only actions** with no UI: abroad expansion (`abrgo`), giving back / foundation (`give28 found28`), own software product desk (`swdev swself swmodel swint ownsw`), startup product pitch (`p17go`), advisers/insurance (`ownpick provpick toggleins`), group-office settings (`lh12set perfauto repset setbig fireceo hqas`), payroll mode/run (`pr29mode pr29run`), sale talk (`saleq saletalk`), per-company permit application (`applydoc`), yacht dinner.
8. **Deal of the week, manager focus plans, web analytics, pay-day change, settings confirm, tender offers `cons`/`farm`** (smaller features with no Swift counterpart); typed-model risk: 85 `rest` keys and 276 company-record keys are string-typed JSON with no schema (no compile-time protection, several owner files per key e.g. `mk` 13 files, `g27` 9 files, `office` 8 files).

UNVERIFIED in this audit: body-level equivalence of the ~12 WRAPPER rows above; the "presentation" status of ~75 handlers (regex-scanned, not read); presence of `fam` event kinds and startup sector/perk ids beyond string-literal match; numeric effect of the pipeline order differences; whether every Swift weekly rule matches the original numerically (that is the job of the repo differential tests, which I did not run).

