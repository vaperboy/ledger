# Reachability and menu rules (26 Oct 2026)

Method: every `mutating func` in `Engine/Sources/Simulation/*Actions.swift` and `PlayerActions.swift` (275 names) was matched by whole word against `App/Ledger`. 28 had no caller. Read models (non-mutating `func`/`var` on `GameEngine` in `Simulation/`, 885) were matched the same way. App code cannot be compiled here (only `swiftc -parse`); CI compiles it. `docs/data/action_status.json` was regenerated from the same check (COVERED_UI 381, ENGINE_ONLY 5; the old file said 339 and 46 and was stale in both directions).

## 1. Actions with no app caller (28), and what was done

| Action | Decision |
|---|---|
| setCreditCheck | WIRED: Company > Customers, "Credit check" switch, only for trades that invoice businesses; shows cost (0.4% of invoiced) and benefit; toast on change. |
| setInflationHold | WIRED: Company > Operations, "Hold my prices" under Price; shows the edge built up; turning off asks first (the edge is lost). |
| useOwnSoftware (+ ownSoftwareOffers) | WIRED: equipment shop of a software item, "From your own companies": price, who builds it, test-version warning, confirmation, result toast (ok / not enough cash / not possible). |
| setProductInternalPrice, pitchProductToRival (+ rivalTargetsForProduct) | WIRED: Projects > Ventures > startup product: "Your companies pay 0/50/100%" and "Sell it to rivals" (odds, wait, result toast). |
| contractWithdraw | WIRED: contract discussion, "Drop this talk" on a talk you started and they countered. |
| setFirstStepsHidden | WIRED: Goals card, hide / show the first-step rewards. |
| recordPushedThrough | WIRED: closing a company (wind up) and selling it, when the engine's `boardVote` says you carried it alone against every other owner; the others' mood drops and the Inbox gets a line. |
| setAutoStock | engine internal: salmon stocking is `setSalmonAutomation` (Company > Energy screen). |
| changeAccountant | engine internal: superseded by `chooseAdviser(kind: .accountant)` (Company > Insurance and advisers). |
| moveBackHome | engine internal: duplicate of `giveUpPremises`, which Workplace calls. |
| chooseGoodsSupplier, chooseRepairSupplier, setSupplier, clearSupplier, buyFromAccount, stopBuyingFromAccount | engine internals: one supplier screen calls `switchSupplier` (Company > Operations > Suppliers). Two actions for one choice would be the duplicate entry point DESIGN_RULES forbids. |
| startupPitches | engine internal: the app reads `startupPitchesOnOffer` (no side effect). |
| contactsSummary | engine internal: text form of the circles the World screen already shows. |
| fire | engine internal / legacy: the app dismisses through `dismissStaff` (StaffProfile rules). Candidate for deletion. |
| setKnob | test and set-up only (its own comment); the app uses `changeKnob` / `toggleKnobOption`. |
| startCompany | engine internal: the app uses `startCompanyChoosingPremises`. |
| setFlag, prepareLeague | private helpers, not API. |
| releaseGroupCEO | not wired: repairs a CEO post from saves older than round 56. Nothing to offer a new game. |
| setReports, toggleOfficeAssignment | NOT wired on purpose: they write `office.rep` and `staff[].cos`, and no engine rule reads either. A setting with no effect would be fake functionality. Question for the owner below. |
| startFranchisedCompanyChoosingPremises | NOT wired: the franchise start screen says the standard premises are taken and can be changed under Equipment, so it is honest today. Choosing the place at start needs a premises picker for franchise units (`newCompanyPlan` is not franchise-aware). Left as is. |

The 5 remaining ENGINE_ONLY ids in `action_status.json` are applydoc, applydoc2 (no per-company permit application), fireceo, hqas, repset.

## 2. Read models with no app caller (not wired, none is an action)

Chain: chainKnobStandard, franchiseCountry, franchiseStartPlan, possibleSuppliers, supplyKinds, supplyLink, supplyPriceFactor, yearlySupplySpend. Advisers: courseOffers, currentAdviser, ownAdviserFirms, ownAdviserOffer, accountantChoices. Group office: boardCandidates, courseCost, deskUse, groupOfficeMonthlyCost, personReport. Reach/supplier: accountSupplyCandidates, accountSupplyLink(s), absorbRivalExtraCost, sourcingOffers, sourcingSummary, currentGoodsSupplier, currentRepairSupplier, supplierCandidates, supplierInvoices. Money/reports: monthlyProfitSeries, operatingAndOther, reputationChange, valueChange, monthlyResults. People/legacy: lifeStory, legacyHistory, retirementHall, topFifty, staffStory, ambitionPerk, tirednessWord, localPaperName. Other: freeSpaceInYourBuildings, ownCarMileagePerMonth, personalEquipmentNeed, taxiFleetClass, canRaiseFunding, weeksUntilNextPitch, crisisCentre.
Most are superseded by a bigger read the screens use. Missing-feature candidates: crisisCentre, retirementHall/topFifty/legacyHistory (game-over run summary), supplierInvoices (bills page), staffStory (staff profile history), monthlyResults.

## 3. Visible outcomes

Every wired action above ends in a toast built from the engine's own answer (refusal or success), and the row it changes is on the same screen (switch state, percent chip, "Already a customer", offer list, "Hold" edge text). The close and sale paths state when the others did not want it. Silent buttons listed in ui-and-data.md (UI-05) were not re-audited.

## 4. DESIGN_RULES check

Fixed: dead `MoneyView` (a "Money tab" that no longer exists) removed; stale "Money tab" comment on `FinanceView`; the previous audit's "unreachable `EmpireCard`" is already gone.
Checked and fine: no Assistant/Regional/Chief tab; hiring a manager is called from two screens but both call `hireManager`; Team and Inbox have empty states; Group > Money is the one `FinanceView` (the Company-tab push is gone).
Known and left to the owner (already in ui-and-data.md): UI-02 decisions in Team, UI-03 dashboard load, UI-12 More only from two tabs, UI-13 Activity vs Money, UI-14 Group market vs Company market.

## 5. Questions for the owner

1. Should the group office report settings (`setReports`: frequency, detail, which companies) and the marketing director / analyst company assignment (`toggleOfficeAssignment`) get an engine effect? Today nothing reads them, so no screen offers them.
2. `fire` (PlayerActions) and `releaseGroupCEO` look deletable; delete them, or keep for old saves?
3. Franchise start: should the player choose the place at start (engine ready)?
4. Stale mapping in `action_status.json` for `carallow`, `mgrmove`, `mgrmovego`: the named functions no longer exist. Where do own-car allowance and moving a manager between companies live now? (Marked STALE in the file; the staff-contract ids were mapped to the contract discussion by inference.)
5. Is the second first-steps tracker intended? `FirstStepsCard` (Advisor, no rewards) and `GoalsCard` (PlayerGoals, with rewards) both exist on the Goals screen.
