# Audit: connectivity (AREA=connectivity)

Scope: are all features reachable, do their settings have outcomes, are outcomes shown, are systems connected. Read-only on game code. App code audited by reading only (no macOS build).

## Method
Python scans (kept outside the repo) over Engine/Sources, Engine/Tests and App: (1) every GameEngine-extension func (584; 293 mutating) matched by name against all identifiers in App; (2) every `set/add/rest[...]=` key matched against all other quoted occurrences (376 keys); (3) every key of every JSON data file matched against quoted strings and identifiers in Swift; (4) every `fx` key used by events.json, country_events.json and inline event JSON matched against a handler; (5) every `addMessage(... action:)` matched against the dispatcher in `GameEngine.answer`; (6) `docs/data/action_status.json` ENGINE_ONLY rows re-checked against current App code; (7) manual reading of Trophies, PlayerGoals, Advisor, GoalsCard, FirstStepsCard, AchievementsView, EventEffects, EventEngine. Name matching can give false "wired" results (a name appearing in App is not proof it is called); items marked VERIFIED were read.

## Coverage checklist
Done: GameEngine public actions (matrix below), PlayerActions, MiscActions, SupplierDeals/SupplierActions, ContractTalk (wired: contractPropose/Respond/LeaveToManager), marketing/knobs (setCampaign, changeKnob), supply, insurance (toggleInsurancePolicy wired), payroll (setPayrollMode, setPayday wired), loans/bank/invest, ventures, franchising, chains, boards/head office, luxury, achievements, goals/first steps, events and inbox decisions, JSON data, docs-vs-code status.
Not done in depth: per-feature weekly-read tracing for every one of the ~290 mutating actions (only dead-key and handler scans were done), structure parity (stand-alone vs chain vs franchise vs holding) beyond spot checks, ContractTalk/Negotiation outcome tracing, rival/world-around UI outcomes, every inbox actionID handler body.

## Findings (sorted by severity)

| ID | Sev | Finding | Evidence | Status | Proposed fix |
|---|---|---|---|---|---|
| CONN-01 | S2 | First-step reward "Read your week report" can never complete, so the reward queue stalls at step 4 and steps 5-10 (sell, ad, inbox, pay, profit, manager) are never shown or claimable. | `PlayerGoals.swift:123` reads `s.rest["reports"]["week"]`; reports are stored under key `"w"` (`ReportModels.swift:16` storeKey, `SaveFormats.swift:40`). `GoalsCard.swift:20` shows only the first unclaimed step. | VERIFIED (reading) | Read `["w"]` (use `ReportKind.week.storeKey`). Add a test that completes the step after one week. |
| CONN-02 | S2 | Nine achievements in group "market" are granted but never listed on the wall; the header "N of M" counts them. Hidden: stars, st48, no1, top10, n1_3, n1_10, rk_50, rk_3, rk_1. | `Trophies.groups` has no "market" (`Trophies.swift:28`); `AchievementsView.swift:21` iterates only `Trophies.groups`; `TrophiesMore.swift` uses group "market". | VERIFIED (reading) | Add ("market","Markets") to `groups` (or loop over groups present in entries). |
| CONN-03 | S2 | Two parallel first-step systems: `Advisor.firstSteps` (7 steps, FirstStepsCard, says "no rewards") and `PlayerGoals.firstSteps` (fs58, 10 steps with rewards, GoalsCard). Both show on Home with different lists/ids; violates one source of truth. | `Advisor.swift:81`, `FirstStepsCard.swift:4`, `GoalsCard.swift:20`, `HomeView.swift:26-27`. | VERIFIED | OWNER DECISION: keep the reward list (original FS58) and drive the card from it; drop Advisor.firstSteps. |
| CONN-04 | S3 | "Pause subscriptions while closed" is a dead setting: `closeCompany(pauseSubscriptions:)` writes `subPause`, nothing reads it, and the App never passes the argument. | `MiscActions.swift:93,106,120`; `CompanySettings.swift:142`; `CompanyWeek.swift:70-86` (closedWeek has no subscription logic). | VERIFIED | Read `subPause` in the closed week's subscription charge and add the toggle, or delete the parameter and key. OWNER DECISION. |
| CONN-05 | S3 | Event effect `lose` (c_scope, "Hold the line" bad branch) has no handler: the "friction" consequence beyond rep -2 does nothing. | `events.json` c_scope; no `["lose"]` read in `EventEffects.swift`. | VERIFIED | Define it or remove it from the data. |
| CONN-06 | S3 | Unknown inbox actionID falls into the `Payday.answer` catch-all and the message is marked done with no effect. All current producers are dispatched (see verified fine), but a new id would silently do nothing. | `GameEngine.swift:159-160`. | VERIFIED | Return false or assert for unknown ids. |
| CONN-07 | S3 | Duplicate rival-group-bid implementation: `RivalBids.answer` is unreachable because `Ventures.handlesAnswer` claims `"g27bid"` first (`GroupDeals.bidAction` and `RivalBids.action` are the same string). Live path is `GroupDeals.answerBid`; `RivalBids.weekly` still runs and has its own reader of the same `rest["g27"]` data. | `GameEngine.swift:147,151`; `Ventures.swift:21`; `GroupDeals.swift:14`; `RivalBids.swift:12,43`. | VERIFIED | Remove the dead `RivalBids.answer/sell/outsideVote` or merge into GroupDeals. |
| CONN-08 | S3 | Expired action messages get `pick = -1`, so an ignored decision counts as "answered" for the first step "Answer a decision". | `EventEngine.swift:237-239`; `PlayerGoals.swift:125`. | VERIFIED | Require `pick >= 0` and not `auto`. |
| CONN-09 | S3 | Engine actions with no App identifier match: `setCreditCheck`, `setAutoStock`, `setInflationHold`, `changeAccountant`, `setFirstStepsHidden` (the fs58 card cannot be hidden), `useOwnSoftware`/`ownSoftwareOffers`, `setProductInternalPrice`, `pitchProductToRival`/`rivalTargetsForProduct`, `releaseGroupCEO`, `recordPushedThrough`, `toggleOfficeAssignment`, `setReports`, `contractWithdraw`, `moveBackHome`, `buyFromAccount`/`stopBuyingFromAccount` (docs claim a screen), `chooseGoodsSupplier`/`chooseRepairSupplier`/`supplierCandidates`/`currentGoodsSupplier`/`currentRepairSupplier` and `setSupplier`/`clearSupplier`/`supplyLink`/`supplyKinds`/`possibleSuppliers` (superseded by `switchSupplier`/`supplierInputs`, test-only), reads `adviserOffers`, `currentAdviser`, `ownAdviserOffer`, `courseOffers`, `canRaiseFunding`, `weeksUntilNextPitch`, `monthlyProfitSeries`, `monthlyResults`, `projectInsights`, `rentalFinanceInsights`, `personReport`, `franchiseeInfo`, `ambitionPerk`. | scans; locations in `MiscActions.swift`, `VentureActions.swift`, `ExecutiveActions.swift`, `ChainActions.swift`, `ReachActions.swift`, `SupplierActions.swift`. | VERIFIED by identifier match only (a wrapper under another name could exist) | Wire the player-facing ones (accountant change, credit check, auto stock, buy from key account, pitch product, release CEO, hide first steps), delete superseded ones. |
| CONN-10 | S3 | Dead stored keys (written, never read in Engine or App): `aw23`, `claimExp`, `dq27`, `gcLy`, `inherited`, `insOwn`, `lastComm`, `mgrName`, `olw`, `promoPost`, `reval` (rental revaluation accumulator), `subPause`, `trial` (nothing blocks a second trial week). Write-only properties: `wageShortfall` (`Payday.swift:240,282`), `yearsPlayed` (`PersonalFinance.swift:90`). | key and property scans. | VERIFIED (no read sites) | Remove or give an outcome; `wageShortfall` should feed the late-payroll display. |
| CONN-11 | S3 | JSON fields no code reads: countries.json `bigAd`, `fxLocalPerUSD`, `limitedShort`, `registrationName`, `soleTraderShort`; country_traits.json `ageBand`, `effective`, `employeeNoticeWeeks`, `massLayoffNotice`, `monthlyAt35h`, `monthlyAt40h`, `noticeTerm`, `realMinMonthly`; trades.json `aum0`, `expR`, `noStart`, `perM2`, `roleCap`, `solv`; balance.json `ticketTuning`; tables.json `CAT_TIER`, `EXPRO`, `FULL_H`, `HCAP`, `MGR_FIT`, `PRICE_NAMES`, `TIERS`; `pcbang` keys and many equipment ids (ids probably looked up dynamically). | JSON key scan: key absent from all quoted strings and identifiers in Swift. | VERIFIED for the named scalar fields, INFERENCE for ids | Remove or wire (notice-period and min-wage fields look like missing rules). OWNER DECISION. |
| CONN-12 | S3 | Docs are stale: `docs/data/action_status.json` lists 46 ENGINE_ONLY, 33 of which now have App callers; it lists pay-day change (`pr29day`) and knob changeover (`hys*`) as missing though `setPayday` (`PlayerActions.swift:285`) and `KnobChange.swift` exist; MISSING_ACTIONS.md calls the abroad tab Engine only but `ExpandAbroadView.swift` exists. | scripts. | VERIFIED | Regenerate the status file from code. |
| CONN-13 | S4 | Trophy "Every country" is at 15 countries; the game has 23. | `Trophies.swift` ladder `cc`; `countries.json`. | VERIFIED | Use the country count or relabel. |
| CONN-14 | S4 | Event cash "whole thousands are scaled to the country" is a value heuristic (`v % 1000 == 0`): -3000 scales, -2500 does not. | `EventEffects.swift` `scaled`. | VERIFIED | Mark scaled amounts in the data. OWNER DECISION. |

## Feature matrix (compact)
| Area | Engine actions | State | Reader | UI | Result |
|---|---|---|---|---|---|
| Pricing/knobs | setPriceLevel, changeKnob, setMaintenance, setStockPolicy, setOwnerHours | priceLevel, knob, maintenance, stockPol, ownerHours | Demand, QualityModel:23, CompanyWeek:462 | CompanyOperations:22-51, CompanyHowYouSell:96 | ok; raw `setKnob` test-only |
| Marketing | setCampaign | mkt | Marketing.swift:225 | CompanyMarketing | ok; no target group (`mktT`) or planner |
| Insurance | toggleInsurancePolicy | ins | EventEffects loss cover, premiums | Company tabs | ok |
| Payroll | setPayrollMode, setPayday, inbox runPayroll | pr29 | Payday | CompanyPayroll(Run) | ok |
| Closing | closeCompany, reopenCompany, windUpCompany | status, closeW, subPause | CompanyWeek.closedWeek | CompanySettings:142 | subPause dead (CONN-04) |
| Suppliers | switchSupplier, negotiateSupplier, set*PaymentTerms | suppliers | SupplyTerms | CompanySourcing, ChainSuppliers | ok; old chooseGoodsSupplier family unused |
| Chains | joinChain, setChainRule, releaseChainKnob/Supplier | chain rules | Chains | ChainView, ChainSuppliers | ok |
| Franchise | signFranchiseTerms, fr24/fb24 | fr | Franchising | FranchiseBrandsView, CompanyFranchise | ok |
| Boards/office | setBoardMode, removeFromBoard, setRightHand, fireOffice | rest.office | ManagerBoards | GroupBoards, GroupOffice | releaseGroupCEO, toggleOfficeAssignment, setReports, recordPushedThrough no UI |
| Ventures | changeBuilders, setSoftware*, declineStartupRound | founded | Startups | VenturesView | pitchProductToRival, setProductInternalPrice no UI |
| Achievements | Trophies.check | rest.ach28 | n/a | AchievementsView | 9 hidden (CONN-02) |
| Goals | claimDailyGoal, claimFirstStep | dy59, fs58 | PlayerGoals | GoalsCard | stalls (CONN-01) |
| Inbox decisions | answer -> dispatcher | inbox | EventEffects and handlers | InboxView:132 | all producers dispatched; `lose` missing |
| Customers | meetAccount, dropAccount, setAccountDiscount, buyFromAccount | accounts | KeyAccounts, AccountSupply | CompanyCustomers | buyFromAccount no UI |

## Events end to end
Library events (133) trigger weekly by weight `w` and `cond`, post a "decision" message, the answer runs `EventEffects.apply`, expiry takes the cheapest-cash option, and a manager with authority decides (`EventEngine.decider`). All fx keys in events.json and inline event JSON have handlers except `lose` (CONN-05). Chains read: rival call (`Rivals.swift:422`, `coord/warn`, collusion fine), aftermath events, strategic decisions (`e27`), shareholders (`own27`), startup rounds, cyber ransom/leak, lawsuits. Not traced to numbers.

## OWNER DECISION list
1. CONN-03: which first-step list is canonical.
2. CONN-04: implement subscription pause while closed, or remove the option.
3. CONN-11: should notice-period and minimum-wage country fields drive rules, or be removed?
4. CONN-14: explicit scaling flag for event cash amounts.
5. Confirmed absent from code: deal of the week (`dow56`), web analytics switch, manager focus plans, student and kid life stories (only loan and heir), campaign target group. Intended omissions or backlog?

## Original features still missing (confirmed from code)
Deal of the week, web analytics switch, manager focus plans, student and investor's-kid starts, campaign target group/planner. Pro store/skins are out of scope. Pay-day change, knob changeover and the abroad tab exist despite the docs.

## Verified fine
- Result-bearing actions are not discarded in App (all statement-form `store.act` calls return Void).
- 33 of 46 formerly ENGINE_ONLY actions now have App callers.
- Every inbox actionID produced by `addMessage` has a dispatcher branch (cpx56, org56, emg12/37, mfind11, mprop, tg58*, successor, prop, mgrraise, mgrpoach, staffx, ftx, ctv, cy56r/l, oil24, club24, fr24, fb24, acct, sue16, g27poach, g27bid, fav31, own27, round, bridge, e27, pay29, pay29all, press interview, weather prepare, Stories).
- Country events: fx keyed by family/trade, handled in `CountryEvents`.
- Trophy keys read (`mgrW0`, `rvN`, `fr.units`, `amb27.cnt`, `pe56`, `founded`, `office`) all have writers.
- Daily goal and ambitions are reachable in `GoalsCard`; life-story picker exists in StartView.

## Open data gaps
Not checked: whether each name match in App is a real call for each of the ~260 wired actions; structure-parity table; weekly-engine reads of every setting; numbers behind event chains. No code was executed, so CONN-01/02 are verified by reading only.
