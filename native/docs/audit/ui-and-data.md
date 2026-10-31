# Audit: ui-and-data (UI/menu compliance, country rules and data)

Auditor: Claude (Sonnet 5.5), pre-launch audit. Branch audit/ui-and-data from origin/native-swiftui (d687a42). Read-only on game code. App audited by reading plus CI screenshots (branches ui-shots-iphone, ui-shots-ipad, ui-shots-iphone-ios26; I viewed home, company overview/finances/operations/marketing, team, group, group money/bank, projects, inbox, More sheet). Country data audited by running Python over the JSON.

## Scope limits (what was NOT done)
- I did not read every one of the ~75 App files line by line. Read in full or near full: RootView, GameStore, NavigationRoutes, PhoneToolbar, PhoneView, GroupView, CompaniesView, TeamView, InboxView, ProjectsView, FinanceView, CompanyDetailView, CompanyOverview (first 300 lines), HomeView, SuggestionCard, ComingUpCard. The rest was pattern-scanned (grep for horizontal scrolls, NavigationLink/chevron, store.act, onTapGesture, SectionTabs) and spot-read. Not individually reviewed for empty/locked/error states: most Company* sections, Ventures, Luxury, Stats, News, Rich list, World, Settings, New company flows, Boards, Chain, Franchise.
- "Home variation 1" and "Company overview variation 1": no document in the repo defines these. I could not check layouts against them (UI-D1).
- MoneyLiteralLintTests allowlist entries were not reviewed one by one. 1 vs 10+ companies was checked by reading code only. No app build or run was possible.

## Findings (sorted by severity)

### S2 (feature misleading, or violates a binding owner decision)
- **UI-01 Side-to-side scrolling menus everywhere (owner: none allowed).** VERIFIED. `SectionTabs` is a horizontal ScrollView (Design/Components.swift:331) used at about 47 sites: Company tabs (CompanyDetailView.swift:51, 7-8 tabs: Overview, Team, Finances, Operations, Marketing, Customers, Market, Chain), Finances sub-tabs (CompanyMoney.swift:23), Group money (FinanceView.swift:26, 6 tabs), Inbox (InboxView.swift:181), Bank terms (BankView.swift:72,148), chain, club, equipment and more. Plus 12 raw `ScrollView(.horizontal)` chip rows: VenturesView.swift:190, CompanyMarketing.swift:63,72, ChainView.swift:317, CompanyFranchise.swift:322, GroupBoards.swift:172, CompanyMarket.swift:96,388, CompanyHowYouSell.swift:42, CompanyCustomers.swift:162, ReportLedger.swift:46, ReportsView.swift:63. Screenshots (iphone 23, 25, 29, 30): tab strip cut at "Marketing", sub-tab "You a...", chips "52 we", "£14", "Until" clipped. Fix: wrapping chip layout or Menu/Picker; for more than 5 company sections a two-row grid. Changing the shared SectionTabs fixes about 47 sites.
- **UI-02 Team tab lists decisions that belong to Inbox.** VERIFIED. Team "Needs you" includes `.decision` issues (TeamOverview.swift:189,302; TeamView open()). Screenshot iphone 40: "Essential equipment breaks down" and "The London Courier wants an interview" are in Team; the same items are on Home and Inbox (three homes). Fix: drop `.decision` from Team, keep people issues.
- **UI-03 Dashboard carries more than top priorities.** VERIFIED HomeView.swift:20-34: net worth, report prompt, suggestions, Coming up, First steps, Goals, then the whole company list. Screenshot ipad 22 shows first steps (7 rows), goals. Home is also the root of the tab named Company, while DESIGN_RULES says that tab is the company list. OWNER DECISION UI-D2.
- **UI-04 A second Group-money instance opens in the Company tab.** VERIFIED. ComingUpCard.swift:28 pushes `FinanceView()` ("Group money") from the Company tab; Group > Money is the one home. Fix: `store.moneySection = .overview; store.jump(to: .group)`.
- **UI-05 Silent or unconditionally successful actions.** VERIFIED by reading: success toast without checking the engine result: CompanyClub.swift:123-124 hireCoach; CompanyEquipment.swift:236 "End the lease" (no confirmation, no cost shown); GroupOffice.swift:149 and WorldView.swift:221 (fire); CompanyStaffRoster.swift:122 and GroupOffice.swift:143 "Do all"/"Paperwork done" (loop, success regardless, no cost shown); MoneyPeopleActions.swift:201 dismissFundManager (no feedback); CompanyCustomers.swift:180 "End contract" (drops a key account: no confirmation, no result); CompanyMarket.swift:66,94 (end price war/discount, no result); CompanySaleSection.swift:131-132 askBuyer. Fix: PendingAction + `.confirmAction`, branch on result.
- **UI-06 Policy sliders/segments apply immediately with no cost or effect preview.** INFERENCE (engine effect not traced). Price level (CompanyOperations.swift:22), maintenance/stock (:47,:51), manager authority limits (CompanyManagement.swift:210-216), chain rules (ChainView.swift:287-300), store rules (CompanyChain.swift:145-161), dividend policy (CompanyOwnership.swift:42). OWNER DECISION UI-D3.
- **UI-07 Payroll approval in Inbox answered without confirmation.** VERIFIED InboxView.swift (`pay29` prefix bypasses the confirm) though it spends money; comment says routine. OWNER DECISION UI-D4.

### S3 (inconsistent / violates a design rule)
- **UI-08 Tappable rows with no cue.** VERIFIED: phone company list row `CompanyRow` (CompaniesView.swift:72, CompanyRow struct) has no chevron; iPad `CompanyTable` rows use `onTapGesture` (CompaniesView.swift:233) with no chevron and no button trait; CompanySourcing.swift:46, ChainSuppliers.swift:97, ChainView.swift:253 (store rows), GroupOffice.swift:336 (manager row), ChainView.swift:171 (out-of-cash link, red text only). `ListRow` defaults `chevron=false` (Components.swift:67), so action rows in SettingsView.swift:40-49 rely on an icon only.
- **UI-09 Duplicate content on one screen.** VERIFIED screenshot iphone 23/24: "6 paperwork items missing at Evans Services" under Needs you and "6 staff paperwork items missing" under What is going on, both to Team.
- **UI-10 Duplicate "Off" and "£0/wk" options** in marketing budget chips. VERIFIED screenshot iphone 30; CompanyMarketing.swift:74-76.
- **UI-11 Hidden nav-bar background lets content scroll under Back and the status bar.** VERIFIED screenshots iphone 24, 30 (Back drawn over text), ios26 26. `.toolbarBackground(.hidden)` in CompaniesView.swift:88, GroupView.swift:30, TeamView, ProjectsView.
- **UI-12 More is reachable only from Company and Group tabs** (PhoneToolbar used at CompaniesView.swift:91, GroupView.swift:31). Team, Projects, Inbox and pushed screens have none; the button is an unlabeled "..." and the list is behind a long-press. iPad sidebar lists all. Every More entry has a destination in PhoneView.swift and the view types exist (not run).
- **UI-13 Activity (account statement)** is in More and linked from Group > Money > Reports (FinanceView.swift:232): second money place. OWNER DECISION UI-D5.
- **UI-14 Group "Market, reviews and rivals" (GroupView.swift:59) vs Company > Market section:** two entries; not traced whether same record. INFERENCE.
- **UI-15 iPad company table truncates.** VERIFIED screenshot ipad 22 ("Evans S...", "Self-fun...", "Space (30...").
- **UI-16 Stale text.** Advisor.swift firstSteps "Open the Phone and choose a trade"; "Phone" is no UI name. `MoneyView` (FinanceView.swift:8) is dead code naming a Money tab that no longer exists.
- **UI-17 Money formats disagree on one screen.** VERIFIED screenshot iphone 20: "£8,026" and "Profit was £8 026 on revenue of £82k." (ReportPrompt text not tidied). LabourRules.summary builds "£ 2065 a month" by hand.
- **UI-18 Plural "1 staff".** VERIFIED screenshots iphone 23, 40; TeamView companyRow `"\(l.staff) staff"`, CompanyOverview KeyFigures sub, ChainView.swift:253. Overview says "1 person". Use "1 person"/"N people".
- **UI-19 Inbox badge semantics.** Tab badge = unread + open (GameStore.unreadCount: 25) vs Decisions badge 2. VERIFIED screenshots iphone 20/52.

### S4
- UI-20 Inbox option cards are boxed (InboxView.swift MessageCard RoundedRectangle fill+stroke), against STYLE_IVORY_LEDGER rule 1; also CompaniesView.swift:118, CompanySettings.swift:75, CompanyStaffRoster.swift:94.
- UI-21 Inbox filter icon hides group-by-company, company filter, mark all read, no label.
- UI-22 Projects tab is an almost empty screen for non-project players (screenshot iphone 50).
- UI-23 Titles inconsistent across tabs (Projects sets no navigationTitle).
- UI-24 Two supplier contacts both named "George Johnson" (screenshot iphone 46): name collision.
- UI-25 "Take to lunch" / "Buy goods through them for all" (Group > People you buy from) show no cost in the screenshot; not traced (HostingSection).
- UI-26 iPad detail uses `.id(store.tab)` (RootView.swift): switching tabs discards each tab's navigation path. Probably intended.

## Navigation rules check
- Five tabs; none named Assistant/Regional/Chief. OK.
- Hiring: Team opens Company > Team; football coaches and group office have own flows (engine-specific). No duplicate firing flow found in the scan.
- Deep links (openCompany, jump, ReturnBar, routeRequests) consistent, cleared on new game/quit.
- Many companies: company list search and chain filter from 8, Team grouping from 10, Inbox paging 60. One company: fine in screenshots.

## Part 2: country rules and data
Files: Engine/Sources/Countries/Resources/countries.json (23 countries), country_traits.json (labour, politics, traits), docs TAX_SOURCES.md and KNOWN_GAPS.md.

- **DATA-01 (S2) Minimum wage in 9 countries is a game-scaled value far below the real one** (NO, SE, PL, LT, KR, BR, MX, IT, FI; about 85% of the cheapest market wage). minMonthly vs realMinMonthly: MX 1,370 vs 9,577; BR 510 vs 1,621; PL 2,160 vs 4,806; KR 1,481,000 vs 2,156,880; LT 650 vs 1,153; NO 29,000 vs 37,000; SE 17,900 vs 25,000; IT 920 vs 1,500; FI 1,740 vs 2,200. VERIFIED. Documented as deliberate in TAX_SOURCES.md. DATA-D1.
- **DATA-02 (S2) Mexico `economy.medianWage` 9,500 MXN/month is below the real statutory minimum 9,577 (general zone).** Median under minimum is inconsistent. VERIFIED.
- **DATA-03 (S3) Orphan/duplicate labour keys:** `minimumWage` lists (9 countries), `realMinMonthly` (9), `employeeNoticeWeeks` (IE), `massLayoffNotice` (US, duplicate of `massLayoffNoticeWeeks`), `noticeTerm` (DE text). LabourRules.init (Employees/Labour.swift) reads none of them. INFERENCE (grep). Wire up or remove; resignation notice is unused.
- **DATA-04 (S3) Stale docs:** KNOWN_GAPS.md ("Pay and tax rules abroad") and the TAX_SOURCES.md header say the data has no minimum wage or notice period; the labour block has both. `commerce.latePayment` is absent in all 23 countries (confirmed).
- **DATA-05 (S3) Brazil brackets** `[[0,0],[60000,0.4735],[88200,0.275]]`: rate falls from 47.35% to 27.5% (an average over the phase-out, TAX_SOURCES.md). If brackets are applied as marginal (IncomeTax doc), income 60,000-88,200 is taxed at 47.35% marginal, overstating tax. INFERENCE.
- **DATA-06 (S3) Leave data in two places that disagree:** `work.leaveWeeks` x5 vs `labour.leaveDays`: BR 25 vs 30, AE 21.5 vs 30, FI 25 vs 30, SG 10 vs 14. VERIFIED.
- **DATA-07 (S3) Vehicles block:** only UK (mileage 0.34175 GBP/km, car road tax 200) and US (mileage 0.47224; TAX_SOURCES.md says 76c/1.609344 = 0.47226) filled; the other 21 countries and fuel, motor insurance, BIK for all 23 are empty (mechanism inactive). VERIFIED.
- **DATA-08 (S3) Non-statutory floors enforced as law:** NO, SE, CH, AE, IT, DK, FI, SG (`statutory:false`).
- **DATA-09 (S4)** Special taxes exist only for NO (oil, salmon, hydro) and UK (oil); US, CA, MX, BR, AE (oil producers) have none (DATA-D2). Wealth tax only NO, ES, CH.
- Units: wages monthly in local currency, thresholds annual, rates fractions 0..1 in every country (no percent-as-number found). Completeness: 89 schema paths present in all 23 countries; only optional blocks vary (wealth 3, MX contributions table, special taxes, registrationName 6, vehicles 2). All 23 labour entries have the core keys.
- Arithmetic that checks out: UK 12.71x37.5x52/12=2,065; DE 13.90x40x52/12=2,409 (data 2,410); FR 1,867; NL 14.99x40x52/12=2,598; IE 14.15x39x52/12=2,391; US 1,257; CA 3,146; AU 26.44x38x52/12=4,354; ES 1,221x14/12=1,424; JP 1,177x40x52/12=204,013; KR 10,320x209=2,156,880; MX 315.04x30.4=9,577.

### Unverified figures and the source needed (nothing invented)
| Figure | Where | Source needed |
|---|---|---|
| Mexican UMA MXN 117.31/day, 30.4 days | MX tax.employer.unit | INEGI/DOF UMA 2026 |
| IMSS employer rates and caps table | MX tax.employer.contributions | IMSS / Ley del Seguro Social 2026 |
| State payroll tax about 3% | MX statePayroll | state tax laws |
| NO real minimum 37,000 NOK | NO realMinMonthly | Tariffnemnda 2026 regulation |
| SE, IT, FI agreement minima | realMinMonthly | collective agreements |
| DK minimum 21,000 DKK, severance rule | DK | agreements, Funktionaerloven |
| CH 4,000 CHF minimum, overtime | CH | cantonal minima |
| AE 2,000 AED minimum, gratuity | AE | UAE labour law |
| SG severance 2/yr | SG | MOM, contract practice |
| DE, ES, NL, IE overtime premium | labour.overtimePremium | collective norms |
| LT severance 2 months and notice | LT | e-tar.lt Labour Code |
| UK qualifying period 104 wk, changes 1 Jan 2027 | UK probationWeeks | gov.uk commencement orders |
| CA Canada Labour Code sections | CA | CLC text |
| FI dividend 28%, contributions | FI | Vero 2026 |
| LT VAT 21%, threshold 45,000, employee 19.5%, employer 1.77% | LT | VMI, Sodra |
| Registration/licence fees, policy rates (not rechecked) | all | registers, central banks |
| Fuel price, motor insurance, BIK, road tax (vans, trucks, buses), mileage for 21 countries | vehicles block | official statistics, tax authorities |
| commerce.latePayment | all 23 | national late-payment statutes |
| staffExpenses employerCharge | all | payroll law |
| km per week, litres per km, litre price 20 | tables.json RUNNING | game design values, unsourced |

### Data-driven design checks
- CountryNeutralityTests (testNoCountryCodeIsWrittenIntoTheCode) scans Engine/Sources only. Exemptions: `Demo.swift` (showcase) and the two data keys `d["DK"]`, `j["CH"]` (design factor, marketing channels that look like codes); a line containing either is skipped whole. **DATA-10 (S3):** App code is not scanned; StartView.swift:32 hard-codes `"GB" -> "UK"`.
- MoneyLiteralLintTests (MoneyScalingTests.swift:68-190) per-file allowlist with reasons; not reviewed entry by entry. It covers numbers of 1000 or more in Engine only. **DATA-11 (S3):** App has fixed money choice lists, e.g. CompanyManagement.swift:214-216 [3000, 8000, 15000, 30000], [10000...250000], [0,1500,3000,7000]; CompanyTeamRoster.swift:103 scales with `scaledPrice`, the others were not confirmed to. INFERENCE.
- Orphans checked only for labour keys. Other JSON resource files not audited for orphans.
- English literals are in engine messages (Advisor.swift, Labour.swift summary); the game is English only. Truncation risk: GroupLinkRow title lineLimit(1) (GroupComponents.swift:62), table cells, Team names.

## OWNER DECISION list
- UI-D1: where are "Home variation 1" and "Company overview variation 1" defined?
- UI-D2: should net worth/home live in the Company tab, and stay with First steps and Goals?
- UI-D3: do slider/segment policies need confirmation with cost/effect?
- UI-D4: payroll approval without confirmation intended?
- UI-D5: is Activity a Group money feature or a More page?
- DATA-D1: keep game-scaled minimum wages or rebalance wage tables to real minima?
- DATA-D2: add special (oil) taxes for other producers?
- Mexico median below minimum: is 9,500 MXN meant as an informal-economy median?

## Verified fine
- Tabs match DESIGN_RULES; no Assistant/Regional/Chief tab.
- Deep-link system consistent and reset on new game.
- Inbox decisions confirm with cost/effect preview (except pay29) and report the engine result.
- Company list urgency sort and filters; Team grouping; Inbox paging.
- Confirmations with cost/effect/risk for coach and assistant hire/dismiss, group office fire, fund manager hire, funding offers, data analyst, chain loans.
- Cards are flat with hairlines (Ivory Ledger); tokens used.
- All More entries have destinations and view types.
- 23 countries complete vs schema; rates are fractions; sourced minimum-wage arithmetic correct; no Norwegian text outside NO.

## Open data gaps
See the unverified table: vehicles block (21 countries), commerce.latePayment (23), staffExpenses (23), fixed-term expiry notice/severance (23), BIK (23).
