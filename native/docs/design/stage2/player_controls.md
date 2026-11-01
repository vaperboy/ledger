# Player controls: pay day, confirm-before-spend, web analytics, manager focus plans

Paths: ORIG = scratchpad/orig/Ledger/source/src/js; ENG = native/Engine/Sources; APP = native/App/Ledger. Roadmap rows B7-B10 (native/docs/IMPLEMENTATION_ROADMAP.md:41-44) are the starting classes; this file revises two of them.

---------------------------------------------------------------------------
## 1. Change pay day (`pr29day`)

### 1. Original and Swift today
- Original: `DAYS = [1,5,10,12,15,20,25,28,0]` (0 = last day) ORIG/features/company/payday.js:30; chip row under "Payday, Company setting" payday.js:450-453, shown only if the company has payroll/staff. `payDate()` payday.js:36-44 (weekend payday moves to the Friday before, Monday after if that leaves the month). `ACT.pr29day` payday.js:468-479: if this month's payday is already paid (`c.pm >= mi`) and nothing is late, `c.day` changes immediately; otherwise it is stored as `c.nday` and applied by `applyNewDay` (payday.js:120-125) when the current payroll completes (called at :150 and :285). UI text: "Changes ... after this month's payroll (staff need notice)". Reminder is reset (`c.rem = -1`).
- Swift engine: all the payday logic is ported. `Payday.PayrollConfig.day` (default 25, 0 = last day) ENG/Simulation/Payday.swift:49, parsed :72, serialised :86 (`"day"`); `payDate` :31-41 (same weekend rule, note weekday 5/6 = Sat/Sun); `config()` :105; `nextPay` :474; `onDay` :361 uses `payDate` for payroll, `nextPay` for the 7-day reminder (:~440). Day mode is the only mode in which payday matters (`onDay` returns if `!s.dayMode` :362; `nextDay()` sets dayMode true GameEngine.swift:171).
- Gaps: no player action writes `day`; `PayrollConfig` has no `nday` and `json` drops unknown keys (Payday.swift:86-96), so an imported original save with `nday` loses the pending change (UNVERIFIED whether import maps it; the field is simply not read). No UI: SCREEN_MIGRATION_INVENTORY.md:760 "NOT_PORTED ... grep nday/setPayDay: none" and :374 "payroll29 ... engine `setPayrollMode` Unreachable". Only `setPayrollMode` exists (ENG/Simulation/PlayerActions.swift:207); Settings has only the global `autoPayroll` toggle (APP/Features/Phone/SettingsView.swift:20).

### 2. Gameplay purpose
- Real decision: cash-flow timing. Payday vs the month-end bills date (`billDate` Payday.swift:~43 = last day) vs when the company's income arrives. A 25th payday (default) leaves 3-6 days to the month end; a 1st/5th payday means staff are paid at the start, when the previous month's takings are in; the "last day" payday stacks wages and rent/suppliers on one day (cash cliff). It matters most for a company that runs lean (overdraft room, `lateSince` path, morale/walk-outs on a missed payroll) and for owner-run payroll where approval must be given 7 days before.
- Small owner-operator: moderate, a real lever for a cafe whose cash dips mid-month. 10-store group: weak per store, but a group policy "pay everyone the same day" is useful; per-company setting only is enough (no group UI needed).
- Honest strength: modest but real, cheap, and it is a mechanic the engine already implements; the only missing piece is the setter.

### 3. Interactions
- Payroll: `Payday.onDay` (payday test `cfg.paidMonth < mi && t >= pd`, :~372), `runPayroll` (sets `paidMonth`, `approvedMonth = -1`, :~180-195), reminder logic (`reminderMonth`), `nextPay`, `lateDay`. Cash flow: `FinanceReport` upcoming-payments rows (ENG/Simulation/FinanceReport.swift:134-143 use `Payday.nextPay`) update automatically. TeamOverview cash warning (TeamOverview.swift:125) unaffected.
- Marketing/demand/reputation: none. Morale: only through late payroll (existing).
- Exploit/double-processing risks (all handled by copying the original rule): (a) changing the day while this month's payday is unpaid could skip or double-pay a month, so queue it (`nday`) until `paidMonth >= current month`; (b) a late payroll (`lateSince != nil`) must also defer; (c) moving the day earlier than today after paying must not re-trigger this month (guarded by `paidMonth`). Avoid a "free float" exploit (change the date every month to delay wages): original has none and the queue-until-paid rule already means the date moves at most one step per cycle; optionally add a once-per-quarter limit (not in the original; skip unless playtests show abuse).
- Countries/rules: none in the original. Optional realism: some countries have legal pay deadlines (UNVERIFIED in the country data; do not add now).
- Golden tests: payroll timing is exercised by BillsAndLoansTests and the differential tests; default `day = 25` is unchanged, so nothing moves unless the setter is called.

### 4. Data, UI, preview
- Data: new optional key `nd` inside the existing `pr29` object (the original stored it as `nday`; keep the original name `nday` in the JSON so imported saves keep working). Default absent = no change. `PayrollConfig.nextDay: Int?`, parse in `init(json:)`, write in `json` only if set. Old saves load unchanged.
- UI home: Company > Finances (payroll and bills page, the missing `payroll29` screen, inventory :374). One home: the payroll card, not Settings. Preview before confirming: "Payday moves from the 25th to the 1st. Staff are next paid on <date> (this month's payroll stays on <date>). Wages and rent no longer fall in the same week / now fall on the same day." Use `PendingAction` only if the change is immediate; a queued change needs no confirm but must show the effective date.

### 5. Recommendation: KEEP (as roadmap B8)
- Reason: real cash-flow decision, engine already supports it, zero effect on existing saves.
- Sketch: ENG Payday.swift: add `nextDay`, `static func setPayday(_ s: inout GameState, companyID:, day: Int) -> Result` (valid values `[1,5,10,12,15,20,25,28,0]`; immediate if `paidMonth >= monthNumber(t) && lateSince == nil` else set `nextDay`; reset `reminderMonth = -1`) and apply `nextDay` where the original `applyNewDay` is called (end of `runPayroll` after `paidMonth` update, and the `!hasPayroll` branch in `onDay`). Expose `GameEngine.setPayday` in PlayerActions.swift next to `setPayrollMode`. App: payroll card in the company finance screen. Tests: new PaydayChangeTests (immediate when paid, queued when unpaid, queued when late, applies after payroll, weekend rule on the new day, old save without `nday`, round-trip, no double pay across a month boundary).
- Effort S-M (engine S, UI card M if the payroll page does not exist yet). Dependency: the payroll/bills page (inventory :374); can ship together with `setPayrollMode` exposure.

---------------------------------------------------------------------------
## 2. Confirm-before-spend setting (`setconf`)

### 1. Original and Swift today
- Original: Settings > Game, two chips "Ask before big actions" / "Do not ask" ORIG/ui/phone/phone.js:229, handler `ACT.setconf` phone.js:242-246 writes `S.settings.confirm`. Consumed in exactly one place: `confirmThen(title, body, label, fn, danger)` ORIG/ui/core/base.js:476-490: `if (!S.settings.confirm && !danger) { fn(); return; }`; otherwise open a sheet with Cancel / confirm button. `danger` actions always ask (text: "Dangerous or irreversible actions always ask." phone.js:229). So the original is a binary toggle that skips the confirm on non-dangerous actions.
- Swift: no setting. Every consequential action builds a `PendingAction` (APP/Design/Components.swift:460-476) and shows `.confirmAction` unconditionally: 56 `PendingAction(` constructions, 13 marked `destructive: true` (counted in native/App). `destructive` ~ the original's `danger`. Messages already carry cost, benefit, risk (e.g. CompanyManagement.swift askShare). The only comparable setting is `ManagementPolicy` (ENG/GameCore/Policy.swift, stored `rest["policy"]`, UI SettingsView.swift:17-37 "How much I decide").

### 2. Gameplay purpose
- It is not gameplay; it is an input-friction control (guards against mis-taps, removes fatigue). DESIGN_RULES.md "confirmation for consequential decisions" is a rule of the app, so any setting must not weaken it for consequential actions.
- A binary "do not ask" toggle conflicts with that rule and is the weakest design. A global money threshold is better: it removes confirms for small routine spends (a 10-store group buying small items all day) but keeps them for the decisions that matter. Benefit goes to the larger group; the small owner-operator rarely needs it and is safer with the default.
- Judgement: a per-spend-size rule should be THE rule (single rule, one setting), not a toggle plus a threshold. Do not keep both.

### 3. Interactions
- Pure app layer: no engine change, no save-format risk to the simulation, no golden test impact. Touches all 56 call sites, so the risk is inconsistency, not exploits. Danger: a threshold computed per view drifts. Mitigate with one central helper.
- Which actions have a money size? Many `PendingAction`s are not spends (appointments, firing, closing, signing loans). Rule: the threshold applies only to reversible money outlays; anything `destructive`, irreversible (sale, closing, firing, loan, dividend of large size, new company/country, acquisition) always asks. The size must be a number supplied by the view from the engine preview (cost in home currency via the engine's currency conversion; do not recompute in views, DESIGN_RULES "No game rules in views").
- Scale: threshold in home currency is wrong across countries and inflation; define it relative to the player's scale (e.g. a share of the company's weekly costs `FinanceContext.weeklyCost`, or `Currency.scaledPrice` for a fixed base, see docs/MONEY_SCALING.md). UNVERIFIED which scaling helper the app should prefer; `cur.scaledPrice(x)` is used throughout the engine.

### 4. Data, UI, preview
- Data: add `confirmAbove` to `ManagementPolicy` (Policy.swift init at :16-20, json :26) as a number of "weeks of the company's costs" or a scaled amount; absent key defaults to 0 = always ask (today's behaviour), so old saves behave exactly as now. Alternatively an app-local `UserDefaults` value because it is a device preference, not game state; choose that if the threshold should not travel in an exported save (recommended: device preference, like `Haptics.enabled` SettingsView.swift:13).
- UI home: Settings > "How much I decide" group (existing, SettingsView.swift:17). One row: "Ask before spending over ..." with a stepper (Always, then steps). Footer: "Sales, closures, loans, dismissals and other irreversible steps always ask."
- Preview: unchanged for actions that still ask; for actions that do not, the result toast already reports the engine outcome (DESIGN_RULES: every action reports the result), plus an undo is not available, so the toast must state what was spent.

### 5. Recommendation: ADAPT
- Differs from the original: a spend-size threshold (default: always ask) instead of an on/off toggle; irreversible actions are never skippable. Reason: satisfies the owner rule and scale concern in one rule.
- Sketch: add `var cost: Double? = nil` to `PendingAction`; add `func ask(_ p: PendingAction, store:)` or a `GameStore.confirmOrRun(_ p: PendingAction, pending: Binding<PendingAction?>)` that runs `p.run()` immediately when `!p.destructive && p.cost != nil && p.cost! < threshold` else sets `pending`. Migrate call sites incrementally starting with the repeat-purchase ones (stock, equipment, marketing budgets, hiring), leaving destructive ones untouched. Tests: unit test the helper (decision table: destructive, cost below/above, nil cost, threshold 0); engine tests unaffected.
- Effort M (touches ~56 sites but mechanical). Dependencies: none; do after the money-scaling decision (docs/MONEY_SCALING.md).

---------------------------------------------------------------------------
## 3. Web analytics (`gaon` / `gaoff`)

### 1. Original and Swift today
- Original: `ACT.gaon`/`ACT.gaoff` ORIG/ui/phone/stats_meetings.js:34-43 only set `co.ga = 1/0`, then `save(); render()`. `co.ga` is read in exactly two places: the company page analytics card ORIG/ui/company/view.js:619-627 ("Connect analytics to see basic traffic for this company. It is free.") and the Stats screen rows stats_meetings.js:17. It gates only the DISPLAY of a sparkline of `co.trf` plus "Last 4 weeks vs before". `co.trf` is recorded every week regardless of `ga` (ORIG/engine/core/week.js:79-81: push `lastW.D || lastW.units`, keep 52). No cost, no effect on demand, marketing, reputation or any other system. The original's own privacy page says "no analytics" (phone.js:247-251), i.e. "web analytics" is an in-fiction toggle, not telemetry. (The roadmap wording "telemetry toggle" is therefore slightly off; the conclusion holds.)
- Swift: `trf` is already recorded for every open company each week (ENG/Simulation/GameEngine.swift:318-322, 52 cap) and used by the analyst report (`analystReport`, ENG/Businesses/ManagerMeetings.swift:575-590, needs a data analyst in HQ). No `ga` field anywhere (grep). Inventory: SCREEN_MIGRATION_INVENTORY.md:161, :361 (page "insight / analytics": web traffic sparkline + analyst briefing, status Missing), :753 NOT_PORTED.

### 2. Gameplay purpose
- No decision. A free, reversible, cost-less view toggle; nothing happens either way except a card appearing. The data (weekly demand/sales trend) is genuinely useful to the player but as a standing chart, not as an opt-in switch. The trend belongs to the company's performance/analytics view and the analyst report (which has a real gate: an HQ data analyst).
- Benefit to either player type: none from the toggle itself.

### 3. Interactions
- None to remove: no engine system reads `ga`. `trf` recording stays (analyst report depends on it). Saves: an imported original save has `co.ga`; unknown keys are kept in `rest`/company dictionary round-trip (UNVERIFIED for company-level unknown keys; the SAVE_FORMAT.md rule says unported fields survive a round trip), so ignoring it is lossless.
- No exploit, no golden test touches it.

### 4. Data, UI, preview
- No new keys. If the sparkline is wanted, show it always on the company performance/Reports view (one home), fed by `trf`, without any switch. If not, nothing.

### 5. Recommendation: REMOVE (agree with roadmap B10)
- Reason: pure display opt-in with no cost, consequence or decision; the underlying trend data is already recorded and should be shown unconditionally (and the richer version is the analyst report, row "C" screen gap).
- Sketch: mark `gaon`/`gaoff` in docs as intentionally dropped; separately (not this item) surface a "Sales trend" sparkline from `trf` in the company performance card and, for the analyst feature, the existing `analystReport`. Tests: none. Effort S (docs only for the removal). Dependency: none.

---------------------------------------------------------------------------
## 4. Manager focus plans (`setfocus`)

### 1. Original and Swift today
- Original (ORIG/ui/screens/mockup.js:427-535, "6B: the manager follows a focus"): Home chips Profit / Growth / Quality for the managed company (ORIG/ui/screens/home.js:168) call `ACT.setfocus` (mockup.js:488-497): requires `co.mgr`, stores `co.focus`, builds a plan with `planFor` and sends the manager's message "My plan: <focus>" with options "Sounds smart" / "Let us discuss" (`sendPlan` :477-487, expires in 2 weeks). Plan = at most 2 of the 8 `askManager` steps (`FOCUS_ACT` :428-437):
  - profit: price_up if util>0.85 and price<2; mkt_less if marketing active and aware>55; save if maint>1; cut if util<0.5 and staff>1; price_up if price<0; save if maint>0 (:441-447).
  - growth: hire if util>0.9 or short-staffed; mkt_more if aware<60; price_down if util<0.6 and price>-2; mkt_more always (:448-452).
  - quality: quality if maint<2; hire if util>0.95 or short; price_up if maint>=2 and price<1 (:453-456).
  - Poor managers (`mgrQual<0.45`) rotate the list with 35% chance (:459-460). "Let us discuss" yields one alternative plan (`ACTS.focusplan` :507-522).
  - Execution (`focusWeek`, called weekly at mockup.js:582): every 4 weeks per company with a focus and manager, run the next step via `askManager` (engine/management/managers.js:442-520) and post a note "Name (Focus): said"; replan when the list is empty (:524-535). It reuses the owner's "Ask for..." path, including its 2-week cooldown (`co.askW`, managers.js:~447) and the hire cash check (`hireShort`). It does NOT check authority level, duty or budget.
- Swift: the "ask for a change" mechanic is ported as `ManagerModel.ask` (ENG/Businesses/ManagerWeek.swift:331-410) with the same 8 keys (`askOptions` :333), 2-week cooldown (`askW`), `GameEngine.askManager` (ENG/Simulation/ManagerActions.swift:81) and the UI menu "Ask for..." (APP/Features/Companies/CompanyManagement.swift:305-313). Missing: `focus`, `focusW`, `focusPlan`, `focusDraft`, `planFor`, `focusWeek` (grep "focus" in the engine returns only unrelated trade "Focus" in ProjectModel.swift). No UI. Swift's manager already acts alone on its own initiative: `ManagerModel.weekly` ManagerWeek.swift:9-49 (proposals every 3rd week via `decideProposal` :~176, answered in the inbox; `tune()` :165 price nudges if authority level >= 1; `keepTeam`, `seasonalWeek`), plus authority levels (`auth.lvl`, `auth.buy`; `ManagerPeople.swift:158-162`, `setExecutiveAuthority` ManagerTeam.swift:423), duties (`setManagerDuty`, ManagerProposals.swift:37; `dutyAllows` :~226), profit share (`setManagerProfitBonus`, ManagerProposals.swift:207, UI CompanyManagement.swift:268-300), and monthly targets/budget (ManagerTargets.swift; `setTargets`, TargetActions.swift:12).

### 2. Gameplay purpose
- What the player controls today: how far the manager may act alone (authority 0/1/2 and purchase budget `buy`), what they own (duties), how they are paid (profit share, target bonus) and what they are measured against (targets/budget). Direction ("which way should I lean: profit, growth or quality?") is only implied by targets; the manager's proposals (`decideProposal`: hire when demand > capacity, cut when util < 50%, ad when awareness < 26, cash) are one fixed strategy.
- What a focus plan adds: a statement of strategy that changes WHICH of the 8 levers the manager pulls (cut/save/raise price vs hire/advertise/cut price vs maintenance/quality). That is a genuine, if shallow, strategic axis, and it is cheap for a 10-store group to set "this one is growth, this one is profit" instead of asking 8 things per store. It mildly overlaps with targets: a profit target and a growth target (rev) already pressure the manager, but in this port they only affect bonuses, mood and a boss talk (ManagerTargets header comment), they do not change what the manager does.
- Weaknesses (be honest): (a) the original plan is a fixed rule list of ~8 steps already available manually under "Ask for..."; once authority levels exist, a focus plan that fires price/hire/cut/marketing without checking authority is a back door around them; (b) it acts every 4 weeks only, so effects are slow and mostly invisible; (c) the three presets are close to dominated by playing the numbers (util > 0.85 -> raise price is almost always right), so the "decision" often reduces to a choice the player would make anyway; (d) overlap with `tune()` (price nudges at authority >= 1, every 10 weeks with a 25% roll) and `decideProposal` (hire/cut/ad) would produce double or conflicting actions (e.g. focus "profit" cuts staff while `decideProposal` asks to hire).

### 3. Interactions
- Money: hire (`hireShort`, `Payments.injectCash` in `answerProposal`), cut (severance via `exec` cut), marketing budgets (`mkt` with lock weeks), maintenance (`co.maintenance`, running cost), price (`PriceMoves.managerStep`, which also applies consumer-authority rules for misleading discounts, PriceMoves.swift:58). Payroll: hire/cut change payslips (`Payday.payslips`, weekly wage cost). Demand/reputation: price and quality steps feed `Demand`, `Satisfaction`, `QualityModel`.
- Authority/duties/targets: today `meetForProposals` and `propose` respect `dutyAllows` (hire/buy duties) and `auth.buy` (a manager buys within the budget the owner set; ManagerProposals.swift:~85-95). A Swift focus step MUST go through those gates (authority level 0: ask the owner via an inbox proposal; level >= 1: act within `buy`, only if the "hire" duty is the manager's), otherwise it contradicts the delegation model (DESIGN_RULES "Delegation comes from the engine (`decisionChain`, authority levels); do not invent mechanics in views").
- Hierarchy: `hierarchyDecide` (someone above the manager judges first) must be consulted for hires; a chain/regional manager's focus for several stores is the natural group-level extension (UNVERIFIED how `decisionChain` would carry a chain-wide focus).
- Cooldowns: reuse `askW` (2 weeks) and `mgrCool`/`propLast` (20 weeks per key) to prevent double processing in the same week with `tune`/`decideProposal`; the three sources should share the same cooldown flags.
- Events/reports: Inbox messages ("My plan"), notes, TeamOverview exceptions; saves: new keys. Risks: oscillation (profit focus raises price, growth focus lowers it; switching focus each month = free price walk), and extra RNG draws changing seeds in golden and differential tests (any new `random.chance` call in a weekly path shifts golden numbers; keep the plan deterministic with `HashedRandom`, as `decideProposal` does for `sense`, or only run for companies with `focus` set, which no golden fixture has).

### 4. Data, UI, preview
- Data (inside the company, absent = none, old saves unaffected): `focus` ("profit"|"growth"|"quality"), `focusW` (week of last step), `focusPlan` ([String] remaining steps), `focusDraft` (only if the discussion step is kept). Same names as the original so imported saves keep the field.
- UI home: Company > Team > manager screen (CompanyManagement.swift), in the existing delegation block next to Duties / Profit share (one home), and visible on the Team tab exceptions only when a step needs the owner. Not on Home.
- Preview: the manager's plan itself is the preview ("For X I would raise prices a little, then spend more on marketing, because ...") with cost/benefit; the owner confirms via the existing inbox ask (Sounds smart / Not now). The weekly steps must say which authority they used ("within the budget you set").

### 5. Recommendation: DEFER (do not port as designed; lean REMOVE the plan-message ritual)
- Reason: the item does not add a decision that authority levels, duties, `buy` budget, profit share and targets do not already give; it largely automates the existing "Ask for..." menu, bypasses authority in the original, and conflicts with `tune()`/`decideProposal`. Roadmap B7 KEEP ("Delegation depth") is not supported by the code: delegation depth already exists.
- If the owner still wants a strategy axis, ADAPT as a single manager setting "Direction: Profit / Growth / Quality" that BIASES the existing engine rather than adding a second actor: (a) `decideProposal` thresholds (growth: hire at demand > 0.75 cap instead of 0.85, profit: cut at util < 0.6, quality: prefer maintenance/equipment), (b) `tune()` price direction, (c) default third target (rev vs profit vs rating). It then needs no new messages, uses the existing authority/duty/`buy` gates automatically, shares cooldowns, and is testable as deterministic threshold changes. Key `focus` on the company; show a preview such as "Growth: your manager will propose hires earlier and advertise more; running costs rise, profit falls first".
- Sketch if built: ManagerWeek.swift (`decideProposal`, `tune` take a `Direction`), ManagerProposals.swift (`setManagerDirection` + preview), PlayerActions/ManagerActions wrapper, CompanyManagement.swift row, tests in ManagementTests (each direction changes the proposal for a fixed seed; authority 0 asks, level 1 acts within `buy`; no change when unset so goldens unchanged).
- Effort: L as the original (messages, discussion, replan) / M as the biasing variant. Dependencies: none hard; the targets third-target choice (ManagerTargets) if integrated.

---------------------------------------------------------------------------
## Summary table
| Item | Rec | Effort | Depends on |
|---|---|---|---|
| `pr29day` | KEEP | S-M | payroll/bills page |
| `setconf` | ADAPT (threshold, default always ask; irreversible always asks) | M | MONEY_SCALING decision |
| `gaon`/`gaoff` | REMOVE (show `trf` trend unconditionally elsewhere) | S | none |
| `setfocus` | DEFER (variant: Direction bias on proposals/tune, no plan messages) | M/L | none |
