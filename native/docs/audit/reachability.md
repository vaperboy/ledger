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
| setAutoStock, changeAccountant, moveBackHome, startupPitches, contactsSummary, fire, releaseGroupCEO, chooseGoodsSupplier, chooseRepairSupplier, setSupplier, clearSupplier, buyFromAccount, stopBuyingFromAccount, setReports, toggleOfficeAssignment (and `StaffContracts.toggleOwnCar`, the duplicate of `PersonalEquipment.toggleOwnCar`) | DELETED with their static helpers. Salmon stocking is `setSalmonAutomation`; the accountant is `chooseAdviser(kind: .accountant)`; giving up premises is `giveUpPremises`; one supplier call, `switchSupplier`, serves a store and tests; `fire` was the old dismissal path (`dismissStaff`); `releaseGroupCEO` only repaired old saves; `setReports` / `toggleOfficeAssignment` wrote values no rule read (the `rep` field of the office record went with them). Tests were repointed to the live path. |
| setKnob | moved to a test-only extension (`KnobPreviewTests.swift`); the app uses `changeKnob` / `toggleKnobOption`. |
| startCompany | kept: not an app entry point but the one function `startCompanyChoosingPremises`, `startFranchisedCompanyChoosingPremises` and `Demo` build on (and many tests). |
| setFlag, prepareLeague | private helpers still used (credit check, league set-up). |
| startFranchisedCompanyChoosingPremises | WIRED: Start under a brand now has the same premises picker as a new company (`PremisesPicker`, shared), the cost comes from `franchiseStartPlan` (plan plus entry fee), and the result toast says when the picked place could not be paid. `startFranchisedCompany` (standard place only) was removed; tests use a test-only wrapper. |

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

## 5. Owner questions, decided

1. Group office report settings and analyst assignment: no engine effect, so deleted (no fake settings).
2. `fire`, `releaseGroupCEO`: deleted (the game is not published; no old saves).
3. Franchise start place: the player chooses it (done, see above).
4. `carallow` lives in the contract talk (benefits topic, `PersonalEquipment.toggleOwnCar`); `mgrmove` / `mgrmovego` in the contract talk (move topic, `ManagerModel.move`). `action_status.json` is fixed.
5. One first-steps tracker: `PlayerGoals.firstSteps` (rewards) stays; `Advisor.firstSteps` and `FirstStepsCard` are gone, the Goals line in More counts the unfinished reward steps.
