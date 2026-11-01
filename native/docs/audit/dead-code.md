# Dead and write-only code (audit CONN-04, 07, 09, 10 follow-up)

Checked by identifier match over `Engine/Sources`, `Engine/Tests` and `App` on the branch after the audit fixes. "No caller" means no App identifier match and, where noted, no Engine or test use. A wrapper under another name could exist; a verdict of `wire` means the original game has a screen for it.

## Fixed in this pass
| Item | What was wrong | Now |
|---|---|---|
| `subPause` (CONN-04) | Written by `closeCompany(pauseSubscriptions:)`, read nowhere | `CompanyWeek.closedWeek` charges software plans each closed week unless paused (original `weekCo.after`); Company settings has the "Pause software plans" switch; reopening clears it |
| Event effect `lose` (CONN-05) | Data key with no handler | The original has no handler either (`c_scope`, `bad: { rep: -2, lose: 1 }`): removed from `events.json` |
| Unknown inbox action (CONN-06) | Fell into `Payday.answer` and the message was marked done | Only `pay29`/`pay29all` reach `Payday.answer`; anything else returns false (message stays open) and writes a "bad" note |
| `RivalBids.answer` unreachable (CONN-07) | `Ventures.handlesAnswer` claimed `g27bid` first, so `GroupDeals.answerBid` ran and `RivalBids.answer` never did | `g27bid` is answered by `RivalBids.answer`; `GroupDeals.answerBid`/`outsideVote` deleted; `GroupDeals.sellToGroup` now uses `RivalGroups.completeSale` (one sale path, with the rival's price fields) |
| `aw23`, `olw`, `promoPost` | Written, never read, also unread in the original | Writes removed |
| `trial` | Nothing blocked a second trial week for one candidate | `Hiring.trialWeek` returns nil if the candidate already had one |
| `Advisor.firstSteps` (CONN-03) | Second first-steps list, no rewards | Deleted with `FirstStepsCard`; `PlayerGoals.firstSteps` (10 steps, rewards) is the one list |
| `chooseGoodsSupplier`, `currentAdviser`, `ownAdviserOffer`, `courseOffers`, `monthlyProfitSeries` | No App, Engine or test use | Removed |

## Engine actions with no App caller
| Action | Where | Verdict |
|---|---|---|
| `setCreditCheck` | MiscActions | wire (original `ccheck` toggle on the company); tests use it |
| `setAutoStock` | MiscActions | wire (original `autostock`) |
| `setInflationHold` | MiscActions | wire (original `inflset`, owner price policy) |
| `changeAccountant` | CompanySetup | wire (change the accountant) |
| `setFirstStepsHidden` | PlayerGoals/MiscActions | wire (the Goals card has no hide switch) |
| `useOwnSoftware`, `ownSoftwareOffers` | CustomerActions | wire (original `ownsw`; the Ventures screen has no own-software choice) |
| `setProductInternalPrice` | VentureActions | wire with the internal-sales screen (`w17int`) |
| `pitchProductToRival`, `rivalTargetsForProduct` | VentureActions | wire (original `p17go`, `p17open`) |
| `releaseGroupCEO` | ManagerTeam | wire (original `fireceo`) |
| `recordPushedThrough` | ManagerBoards | wire (original `b13go`, record a decision pushed through against the board) |
| `toggleOfficeAssignment` | ExecutiveActions | wire (original `hqas`) |
| `setReports` | Headquarters | wire (original `repset`, who reports to whom) |
| `contractWithdraw` | ContractTalkActions | wire (withdraw an open contract proposal) |
| `moveBackHome` | PremisesExtras | wire (move a company back to the home country) |
| `buyFromAccount`, `stopBuyingFromAccount` | ReachActions | wire (docs claim a screen; tests use them) |
| `chooseRepairSupplier`, `supplierCandidates`, `currentGoodsSupplier`, `currentRepairSupplier` | SupplierActions | remove later: superseded by `switchSupplier`/`supplierInputs`; still used by tests, so left until the tests move |
| `setSupplier`, `clearSupplier`, `supplyLink`, `supplyKinds`, `possibleSuppliers` | ChainActions, IntercompanySupply | remove later: superseded by `switchSupplier`; test-only |
| `adviserOffers` | CompanyTabActions | keep: used by `CompanyCoverageReads`; no App caller needed |
| `canRaiseFunding`, `weeksUntilNextPitch` | VentureActions | wire into the fundraising screen (no App use of either read) |
| `monthlyResults`, `projectInsights`, `rentalFinanceInsights`, `personReport`, `franchiseeInfo` | various | keep: read models for screens that exist in the original; each is one line |
| `ambitionPerk` | WorldAndGivingActions | wire: the Goals card shows milestones but not the perk text |
| `setKnob` | PlayerActions | keep: raw setter used by tests; the App uses `changeKnob` |
| `runPayrollNow` (does not exist) | | wire: `Payday.runPayroll(.manual)` is reachable only from the inbox answer |

## Company keys written but never read
| Key | Writer | Verdict |
|---|---|---|
| `claimExp` | Hiring (candidate) | wire: the original shows "Claims N years" on the candidate |
| `dq27` | Shareholders | wire: original shows it under the dividend policy |
| `gcLy` | MonthEnd (year change) | wire: original group-tax screen compares to last year |
| `inherited` | LifeStories | keep: marks an inherited company; trade unlocks could read it |
| `insOwn` | Advisers | wire: the original manager duty `insNeed` skips a policy the owner switched itself |
| `lastComm` | CompanyCosts commission | keep: per-person last commission, shown in the original daily sales table |
| `mgrName` | EventEngine (manager decided an event) | now read by the first-step check (a manager's decision is not "answered by you"); original also shows "Name recommends" |
| `subPause` | MiscActions | read now (see above) |
| `trial` | Hiring | read now (see above) |
| `aw23`, `olw`, `promoPost` | | removed (also unread in the original) |
| `wageShort` (`wageShortfall`) | Payday | wire: should feed the late-payroll display |
| `yearsPlayed` (stats) | PersonalFinance | keep: for the legacy score, nothing reads it yet |
| `reval` | RentalModel (revaluation accumulator) | keep: unread, but `RentalFinanceDifferentialTests` compares it with the original game; wire into the rental report or drop together with the oracle |
