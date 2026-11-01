# Progression and player background: trade unlocks, start-up loan, age/city/life story

Scope: native/Engine and native/App at /home/user/ledger; original at `$O` = /tmp/claude-0/-home-user-ledger/215d63e3-40ac-5956-8b0a-51af6046d38a/scratchpad/orig/Ledger/source/src/js.
Read first: native/docs/IMPLEMENTATION_ROADMAP.md (B1, B2 are both listed KEEP and depend on each other), DESIGN_RULES.md, SCREEN_MIGRATION_INVENTORY.md (rows 1, 29, 39-42).
Numbers marked "measured" come from a throw-away probe test run on a copy of the engine in the scratchpad (not in the repo): `CompanySetup.estimate` at the recommended size, sole trader (limited where the trade needs it), capital city, `newGame(seed: 1)`. Everything else is read from code.

## 0. Corrections to the premises (checked)

* "All trades open from day one" is true in Swift, but "67 trades" is not what a player sees: `NewCompanyView` lists `e.data.catalog.all` and greys only banned and non-startable ones (NewCompanyView.swift:12-50; `CompanySetup.banReason` CompanySetup.swift:32; `SpecialFamilies.isStartable` SpecialFamilies.swift:18). Startable and not banned is 63-65 trades (measured, UK/US/NO/MX/PL).
* The original did NOT lock 67 trades behind a loan. Its start was the 8 cheapest trades open, the rest opening on earned net worth (section 1.1).
* The "loan start" is not a mode in Swift; it is the only start. `GameEngine.newGame` always creates the `kind == "start"` loan (GameEngine.swift:50-92, `l.kind = "start"`). In the original it is the default of five stories (`life_stories.js:20`, `Y.get` falls back to `Y.L[4]`).
* The start screen has no age or city input and no story. `StartView.newGameCard` has a name field and a country picker only (StartView.swift:145-172); `GameStore.newGame(name:countryCode:)` (GameStore.swift:134) does not pass `age` or `cityID`, so the engine defaults apply: age 30 (GameEngine.swift:52), city = `country.cities[0]` (GameEngine.swift:75). The original's default age is 25 (`start.js:17`).
* There is no Pro/country gating in the native app (UNVERIFIED by full grep, but `grep -rniE "isPro|FREE_CC|proUnlock"` over App/ and Engine/Sources finds nothing relevant to countries; roadmap B12 defers Ledger Pro). Original: only UK, US, DE, FR free (`start.js:6`, `PRO.FREE_CC`), others behind Pro; and Pro or the "trades" pack opens every trade (`trade_unlocks.js:34`). So there is no country-vs-Pro interaction to design now; section 3 notes where it would plug in.

## 1. Item 1: trade unlocks and the start-up loan

### 1.1 What the original does
* `features/player/trade_unlocks.js` (UNL57). At new game, after the story is applied (`start.js:158-159`: `STORY57.apply` then `UNL57.init`), every non-holding, non-club trade that is legal in the country (`legalStatus`) is priced by `setupEstimate` and sorted by cost (`trade_unlocks.js:27`). The 8 cheapest are open (`:29`, `need = 0`). Every other trade gets `need = tier(estimate / 3)`, rounded up to 1, 1.5, 2, 3, 5, 7.5 x 10^n of the local currency (`:16-21`, `:29`).
* "Earned" = highest net worth reached minus net worth at start (`nw0`, `:28`, `:37`, `:54`). Money you started with does not count (header comment `:5-6`). Checked weekly (`addStep('week.after', 92, ...)` `:63`); a trade whose `need <= best` opens with an inbox message from "Your bank" (`:61`).
* Always open: trades you own (`:35`, `:65`), the holding family (`:35`). Everything open when `PRO.has('trades')` (`:34`) and in saves with no `S.unl57` (`:8`, `:35`).
* UI: New company hides a group until one of its trades is open, and shows "Opens when you have earned X" (`ui/screens/companies_list.js:133-136, :228, :248`). Football clubs have their own gate (`sportOk`, `:49`).
* Design consequence found in the code: `nw0` is taken AFTER the story. A "kid" with 2 M starts with `nw0` about 2 M, so `earned` = 0 and only the 8 cheapest trades are open despite the cash. An heir's `nw0` includes the café. That is exactly the arbitrary block the owner wants to avoid, so the original rule cannot be ported as is.
* The start-up loan: `engine/core/state.js:79-100` (`kind: 'start'`, `bal: c.loan`, margin 4.5 %, annuity over `loanTermM`), money `S.cash = c.loan` (`:35`). Four of the five stories delete it (`noLoan`, `life_stories.js:23`); the loan also is excluded from refinancing events (`business_events.js:299-305`).

### 1.2 What Swift has today
* Start loan: always created (GameEngine.swift:50-92); per-country amounts in `countries.json` `start.loan` (e.g. UK 9 500, US 16 000, NO 150 000 local; account units after FX: UK 128 671, US 171 200, NO 150 000, MX 144 500, PL 88 275 measured). Scaling rule: buys about the same business everywhere (MONEY_SCALING.md:43).
* Trade list: no locks. Cost is only advisory: `TradeDetailView` shows "You are X short of the full start-up cost. You can still register, but opening will wait for money." (NewCompanyView.swift:121-122). `PlayerActions.startCompany` (PlayerActions.swift:17-31) creates the company and injects `min(amount, liquid)`; `CompanySetup.create` only refuses on ban, limited-company share capital, and abroad fee (CompanySetup.swift:283-287). So with the starting loan a player can register an oil and gas company; registration and documents are sunk and the company never opens. UI text is the only guard.
* Measured start costs (`estimate.total` as a multiple of the starting loan):

| Country | trades startable | cost <= 1x loan | <= 3x | <= 10x | <= 100x | Café | Restaurant | cheapest 5 (x loan) |
|---|---|---|---|---|---|---|---|---|
| UK | 65 | 1 | 7 | 24 | 51 | 7.1 | 26.2 | tutoring .67, freelance 1.16, photo 1.32, car cleaning 1.34, handyman 1.49 |
| US | 64 | 1 | 7 | 27 | 52 | 6.0 | 22.4 | .61, 1.06, 1.11, 1.12, 1.24 |
| NO | 64 | 2 | 9 | 31 | 53 | 5.9 | 21.4 | .48, .83, 1.03, 1.06, 1.16 |
| MX | 64 | 3 | 18 | 33 | 54 | 4.1 | 14.0 | .46, .77, .91, 1.00, 1.08 |
| PL | 63 | 2 | 7 | 30 | 51 | 7.2 | 25.4 | .56, .96, 1.27, 1.51, 1.66 |

  Dearest: renewable power, oil and gas, indoor ski hall, regional airline at 2 000 to 7 000 x the loan.
* What a new player experiences: a flat list of 63-65 trades, sorted in catalogue order, with the first 5 to 9 actually fundable; the café that the original's heir story hands you costs 4 to 7 loans. Nothing says which trades are sensible first moves.

### 1.3 Gameplay purpose (honest assessment)
* Decision it gives: which of the few trades you can really afford to open first, and what to grow towards (a visible ladder: tutoring or freelance, then hair salon or food truck, then café, then bigger). That also drives "who benefits": the small owner-operator gets a short, meaningful first list; the 10-store group never sees the gate (owned trades and chain stores are open, and `NewCompanyView` for a rich player is unconstrained).
* Gap it solves: the sunk-fee trap above and decision overload on day one. The same gap could be solved without any stored unlock state by sorting and labelling by cost vs money. The extra value of a real unlock is the progression feel ("bank letter: you can now start X") and a reason to care about net worth. That value is moderate, not large; the design below keeps it only because it is cheap and derived from money, never from time or grind.
* Weak point to say plainly: the original's tier rule (`need = tier(cost/3)` against EARNED net worth) is arbitrary when starting money does not count (kid, heir). Do not port it literally.

### 1.4 Interactions
* Money/cash flow, banks: `Banking.offer(kind: "biz")` already bases the business loan on 25 % of net worth plus profit estimate (Banking.swift:84-87); the original comment "about what a bank wants to see as your own stake before it lends the rest" matches that, so a "reach = 3 x own funds" rule is consistent with the bank (UNVERIFIED that a player can actually borrow the remaining 2/3 at setup: `startCompany` has no loan step; only `CompanySetup` equipment/vehicle finance, CompanySetup.swift:143).
* Entry points that must NOT be gated because they use `CompanySetup.create` or other paths: rival absorption (`RivalDeals.swift:30`), chain stores (`Chains.newStoreCost`, Chains.swift:221), abroad subsidiaries (`ExpandAbroadView`, `CompanySetup.create` with `countryCode`), franchise units (`FranchiseBrands.apply`, ChainActions.swift:131), `SpecialFamilies.blankCompany` (holding, club). Put the gate in `PlayerActions.startCompany` (the New company entry), never in `CompanySetup.create` (also used by `estimate`, which clones state and calls create, CompanySetup.swift:396).
* Reports/events: none read the unlock state. Events keyed on first company: `PlayerGoals.firstSteps` "Start a business" (Advisor.swift:85), unaffected.
* Exploit risks: (a) inflating cash with a consumer loan to pass the gate: counter by measuring own funds as net worth based (debt nets out), not cash; (b) buy-and-sell rival or franchise to "own" a trade type and unlock it (original has the same hole, `trade_unlocks.js:65`): acceptable, those paths already cost real money; (c) double processing: check runs weekly, idempotent set insertion, no cash moved. (d) Golden tests: `newGame` is used in 98 test call sites; a new optional `story:` parameter defaulting to the current behaviour must leave every golden unchanged. The gate must live in `startCompany` only, so engine tests that call `startCompany` directly (Demo.swift:14 calls it for a café with 4 M) need a bypass (default `enforceReach: false` in the engine API, true only from the New company screen) or the demo will refuse.

### 1.5 Data and save impact, UI home
* New key `rest["start"]` = `{ "story": "loan", "stake": <number>, "nw0": <number>, "best": 0, "open": {tradeID: 1}, "at": {tradeID: week} }`. Missing key = no gate (every trade open), same as original saves without `unl57` (`trade_unlocks.js:8`). Old native saves therefore load unchanged; no migration. Legacy (HTML) imports: key absent, so no gate (original `S.unl57` is not mapped, keep it that way or all imported saves would be re-locked).
* UI home: New company list (`NewCompanyView`), the one place trades are chosen. Rows grouped "Within reach", "Needs more capital" (with "opens at X"), no separate screen. Inbox message on opening (existing `s.addMessage`). The player sees the cost and the exact threshold before tapping; locked rows are disabled with the reason (DESIGN_RULES: real locked states).

### 1.6 RECOMMENDATION: ADAPT (M)
Differences from the original and why:
1. Count the money you start with. `reach = 3 x (stake + max(0, earnedNW))`, where `stake` is the cash the story hands you (loan principal for the loan start, severance, savings, the gift; for the heir only the savings, not the café), and `earnedNW = peak(netWorth) - nw0`. For the loan start `stake` = the loan so day-one reach is 3 x loan, which opens 7 to 18 trades (table, "<= 3x" column), about the original's "8 cheapest". For the kid it opens about 45 trades (see section 2) instead of the original's 8 for a player holding 2 M.
2. Guarantee: the 8 cheapest trades of the country are always open (original `:29`), so the list is never empty, even for the student.
3. Owned trades always open; holding and club families keep their own screens (not in this gate).
4. No tier rounding to powers of ten: show the real number ("Opens at an own capital of X"), rounded with `Currency.tidyShort`. The rounding only existed to make trades open in batches; with a visible list that is noise.
5. Gate only the New company entry (section 1.4), not rivals, chains, abroad, franchise.
6. Cheaper fallback if the owner dislikes stored state: no `rest["start"]`; label rows from current net worth plus start loan principal and refuse only when `estimate.total > 3 x ownFunds`. Loses the inbox "new trade" moment and the story stake distinction; about S effort.
7. Do not build the Pro override (B12 deferred); leave a single `unlockAll` predicate in the engine for later.

Sketch: `Engine/Sources/Simulation/TradeAccess.swift` (new): `static func reach(_ s: GameState) -> Double?` (nil = no gate), `isOpen(trade:state:data:)`, `need(trade:...)`, `weeklyCheck(&s)` called from the weekly step beside the other `PlayerGoals` hooks (find the call site next to where `PlayerGoals.firstSteps` is updated; UNVERIFIED which function). `PlayerActions.startCompany(..., enforceReach: Bool = false)` returns `.failure(.notYetUnlocked(need))` (new `StartError` case; update the switch in NewCompanyView.swift:138-143). `GameEngine.newGame(..., story:)` writes `rest["start"]`. App: `NewCompanyView` grouping and disabled rows. Tests: `TradeAccessTests` (loan start in 5 countries opens 7-18 trades and the café is closed; kid reach >= 40 trades; heir café open and no more than loan start plus savings; old save without key everything open; `startCompany` direct call with default flag still works for Demo and goldens; consumer loan does not raise reach). Run `swift test --filter Golden` to prove newGame default output is unchanged.
Dependencies: item 2 (stake per story). Without item 2 the gate would only ever see the loan stake, which is fine but pointless as a story differentiator.

## 2. Item 2: player background at start (age, city, life story)

### 2.1 What the original does
* `ui/screens/start.js`: name, age (stepper, 18-110 via `U.AGE0/AGE1` base.js:546, default 25 `:17`), country (guessed from phone language `:20-34`), city list sorted by population with a rent label (`:109-114`), story list (`:119-129`), country "at a glance" (wages, company tax, VAT, loan). `startgame` calls `newGame({name, age, city, country})` then `STORY57.apply`, `UNL57.init`, `SEEN57.start`, `FS58.start` (`:155-161`).
* What age does in the original engine: one thing, `age > 60` costs 0.02 credit per month (`engine/money/money.js:332-333`). `grep -rnE "player\.age|myAge"` finds no other use. The story only suggests an age: laid 38, student 21, kid 24, others 0 = keep (`life_stories.js:15-21`, applied `start.js:127`).
* What city does: `S.player.city` is the default city of new companies (`companies_list`/`api.js:68-69`, `company.js:80`), the office city (`office.js:77, :119`, `state.js:100`), where the holding is registered (`deals.js:230`), the local paper and the giving list (`giving_and_goals.js:34`). City itself carries `pop, rent, wage, price, dem` (countries data).
* The five stories (`life_stories.js`):
  * Heir (`:25-44`): no start loan; gives `put + 50 000 + asCapital + asFee` where `put = round(1.3 x café estimate)`; creates a café company ("<Surname> Café", form AS), cash injected, set up, all documents `ok`, staff onboarded, awareness >= 45, reputation >= 60, owner hours 25, flag `inherited57`; then removes everything above 50 000 from your cash (so you keep 50 000 savings; `:42-43`).
  * Laid off (`:48`): no loan; cash = 12 months of the median wage x 0.72 (rounded to 1 000). Age suggestion 38.
  * Student (`:49`): no loan; cash 30 000 (reference scale `KC`); credit 40 (default 62, `state.js:41`); loan margin +1 % for 156 weeks (`:54`). Age 21.
  * Investor's kid (`:50`): no loan; cash 2 000 000 (`KC`); credit 45; flag until week 104: loan margin +1.5 % (`:54`), manager asking pay +10 % (`:55`). Age 24.
  * Start-up loan: nothing changes (default).

### 2.2 What Swift has today
* Player record: `player.age` (set in `newGame` GameEngine.swift:72, param default 30), `player.cityID`, `player.skill {}`. `credit` (default 62, GameEngine.swift:75), `loans`, `cash`, `cash0`. No `story`. First-steps checklist exists (`PlayerGoals.startFirstSteps`, GameEngine.swift:97).
* Existing consumers of `player.age`: only `PersonalFinance.swift:44-45` (credit -0.02 per month after 60), identical to the original. Not displayed anywhere in App (grep `player.age` in App finds none).
* Existing consumers of `player.cityID`: default city in `TradeDetailView` (NewCompanyView.swift:75), `Press.swift:16` (local paper name), `HoldingModel.swift:88`, `Headquarters.swift:85`, `ExecutiveActions.swift:88` (office), `ChainActions.swift:131` (franchise default), `Giving.swift:65`, `Demo.swift:14`. City demand, rent, price and wage already act through each COMPANY's `cityID` (`World.swift:34`, `CityMarket.profile`), not through the player's.
* Family events tied to the player's age: none in the original or Swift (grep for player age in events: none). Retirement/succession machinery in Swift (`Stories.swift:115`, `ManagerPeople.findSuccessor`) is about staff and managers, not the owner.
* Engine hooks that already exist for the stories: `Banking.offer` (margin, Banking.swift:77-96; its doc comment already names "young-borrower rules" but no code reads a story flag: UNVERIFIED that the rule was ported, `grep kid57|story57` in Sources = nothing), `ManagerPeople` candidate generation (`askingMonthlyWage`, ManagerPeople.swift:40-60), `Company.ownerHours/awareness/reputation` (Company.swift:73-78), `Payments.injectCash`, `CompanySetup.quickSetup` (CompanySetup.swift:448), `Documents` states (`co.value("docs")`, CompanySetup.swift:151).

### 2.3 What each choice would change, exactly

| Choice | Cash (account units, measured UK / NO) | Debt | Credit | Trades open (with item 1, section 1.6) | Other |
|---|---|---|---|---|---|
| Start-up loan (current) | 128 671 / 150 000 | same (5-year annuity, +4.5 %) | 62 | reach 3 x loan = 7 to 18 trades | nothing |
| Heir | savings 46 050 / 50 000 plus a café worth about 1.3 x its start cost (4 to 7 loans, owned from day one) | none | 62 | café + 3 x savings reach: the 8 cheapest only (~0.36 x loan stake) | open café, rep 60, awareness 45, owner hours 25, papers in order, staff onboarded |
| Laid off | 12 months of median wage x .72 = 449 971 / 483 840 (about 3.5x and 3.2x the loan) | none | 62 | 3 x severance = about 10 x loan = 24 to 31 trades | no company; age 38 |
| Student | 28 443 / 30 000 (about 0.22 x loan) | none | 40 | the 8 cheapest (the guarantee); tutoring costs 0.5 to 0.7 x loan so even that is tight | loan margin +1 % for 3 years; age 21 |
| Investor's kid | 1 896 202 / 2 000 000 (about 12 to 15 x loan) | none | 45 | 3 x stake = about 40 x loan = 45 to 50 trades | loan margin +1.5 % and managers ask +10 % for 2 years; age 24 |

Findings:
* The student is dominated: less cash than the loan, no debt relief that offsets it for a game of 5-year loan payments, worse credit. Net worth is positive (+28 k vs 0) but purchasing power is 22 %. It works only as a deliberate hard mode, and the ONLY upside is "no repayments". If kept, it needs a real upside (see recommendation).
* Laid off at 3.2 to 3.5 x the loan with no debt is better than the loan start on every axis except it has no business to run and the story text says "no business yet". It makes the loan start the weakest "normal" option unless it is explicitly the guided default. Needs an owner decision on severance multiplier (UNVERIFIED balance; `0.72` and 12 months copied from original).
* Heir is the only story that gives a running business; it also tests that nothing breaks with an owned company at week 0 (first-steps "Start a business" is satisfied at once).
* Age: apart from the credit decay after 60, age changes nothing. A typed age 18 to 110 is a dead input (and age 100 would only drain credit by 0.02 a month, i.e. a free "bad credit" button). The only age that matters is the one the story implies.
* City: affects the default city and thus the first company's rent, wages, demand (`dem` 0.22 to 2.4) and rivals, but the first company's city is chosen again in `TradeDetailView` (NewCompanyView.swift:97). So a start-screen city is a duplicate decision for everyone except the heir (whose café exists already).
* Country: the one background choice that already matters; it sets currency, taxes, wage level, loan size, banned trades.

### 2.4 Interactions
Money (cash/`cash0`/`loans`), credit (`Banking.creditMargin`, `Banking.offer` kind "cons"/"biz"/"mort" uses `band(credit)`; credit 40 = band D = business loans halved, credit E = none, Banking.swift:79-84), manager hiring (`ManagerPeople` ask), company model (heir), reports (net worth history starts with `cash0`; `openReportBaselines()` at GameEngine.swift:100 must run after the story or the opening baselines are wrong), first steps, saves, inbox. Risks:
* Heir creates a company inside `newGame` before `openReportBaselines` and `snapshot`: order matters for tests that compare week-0 net worth. Apply the story before `engine.openReportBaselines()` (GameEngine.swift:98-101).
* `cash0` is read by reports and "profit since start"; set it to the story's starting cash, not the loan, or the net worth chart shows a fake gain/loss. UNVERIFIED which views read `cash0`.
* Removing the start loan: the loan record is created after JSON decode (GameEngine.swift:80-86); for non-loan stories skip it entirely rather than creating then deleting (the original deletes it and debits cash, `life_stories.js:23`, which would leave a stray "No start-up loan" ledger line).
* Time-limited modifiers (margin +1/1.5 %, manager +10 %) need an expiry keyed on `s.week` (original used `S.flags.kid57 = week + 104` and `S.week < 156` for student); keep them in `rest["start"]` as `{ "doubtUntil": 104 }` and read them in the two places above only. No double-processing risk if read-only.
* Golden tests: `newGame` default (story "loan") must be byte-identical; add the story parameter last with default `"loan"`.

### 2.5 Data and save impact, UI home
* `rest["start"]` (as in 1.5) plus the story's modifiers; `player.age` already exists. Old saves: key absent = loan story, no modifiers, no gate.
* UI home: the Start screen (StartView.newGameCard), after country: a "Your story" row opening a sheet with the options. Under each option show exactly what changes in the chosen country's money: starting cash, debt (none / the loan), credit (62 / 40 / 45), trades you can start, and the two time-limited penalties. This replaces the original's free-text one-liners with numbers (DESIGN_RULES: cost/benefit/risk before confirming). City appears only for the heir ("Where is the family café?"). No age field.

### 2.6 RECOMMENDATION
* Life story: ADAPT (M, with item 1). Ship in two steps: (a) first the data and engine plumbing with `loan` and `heir` only (both are the "start state" you can verify: heir proves company-at-start), then (b) `laid`, `kid`, `student` once the owner has chosen the numbers. Differences from the original: stories show real numbers; the severance multiplier and student cash need an owner decision or a balance probe before shipping (student dominated); no deletion of the loan after creation; the penalty rules live in `rest["start"]`, not in global flags.
* Age: REMOVE as a typed input. Keep `player.age` in the engine and let the story set it (heir 30, laid off 38, student 21, kid 24, loan 25 as in the original default `start.js:17`; Swift's present default 30 changes nothing in play but note the 5-year difference for the credit >60 tick, which is immaterial over a 30-year game). Reason: it is the only story-independent field that does nothing.
* City: REMOVE from the start screen except for the heir (S). The first company already asks for a city with demand/rent visible per city (`TradeDetailView`). A fallback: derive `player.cityID` from the first company created (UNVERIFIED if office/paper code tolerates a late change; `Giving.swift:64-65` already unions company cities with the player's city, so tolerant).

## 3. Item 3: interactions between (1) and (2)

* The story is the only input to the gate: `stake` = cash the story gives (not the company the heir receives). Per section 2.3: loan 7-18 trades; heir 8 plus the café; laid off 24-31; student 8; kid 45-50. This is the intended shape: a ladder from freelance to airline, entered at different rungs.
* Heir: the café is owned, so `open[cafe] = 1`; later chain stores of the café are not gated either. Heir does NOT unlock restaurants (26 x loan) or other food trades until reach, which is the intended "family café first" path.
* Trades closed by an unfunded start story: never leave a player stuck. Guarantee 8 cheapest even if the student holds 0.22 loan; the student's tutoring trade (0.46 to 0.67 x loan = 2 to 3 x the student's cash) therefore costs more than the student has. For the student the "8 cheapest" guarantee is not enough to start anything: either raise student cash to at least the cheapest trade (about 0.7 x loan, i.e. 100 k reference not 30 k) or drop the story. Flag for the owner.
* Pro/country gating (original `PRO.FREE_CC` four countries; Pro opens all trades): not present in native; B12 deferred. Keep a single `unlockAll` boolean in `TradeAccess` and a single `allowedCountries` predicate in the Start screen so the commercial layer can attach later. No interaction to build now.
* Countries banned trades (`banReason`) are filtered before reach, so a locked row never also shows a ban message; the row shows the ban (hard) in preference to "opens at" (soft), as in the original (`legalStatus` filtered first, `trade_unlocks.js:27`).
* The first-steps card (`PlayerGoals.firstSteps`) should show the first reachable trade for a non-heir; low effort, no new mechanic.
* Banks: credit penalties (student 40, kid 45) change `Banking.offer` bands and the "reach" estimate that depends on a business loan; since reach is by own funds, not by bank approval, a student can see a trade as "reachable" yet get no loan for the rest. Show the reach text as "own capital needed", not "the bank will lend".

## 4. Summary of recommendations

| Item | Class | Effort | Depends on |
|---|---|---|---|
| Trade unlocks | ADAPT (money-derived reach incl. starting stake; 8 cheapest guaranteed; gate only New company entry) | M | stories (stake) |
| Start-up loan as an option | ADAPT: stays the default story, no extra mode | S | stories |
| Life stories | ADAPT (numbers shown; heir and loan first; student needs owner decision) | M | none |
| Age | REMOVE as input; implied by story | S | stories |
| City | REMOVE at start except heir | S | stories |
