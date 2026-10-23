# Hands-on test plan

Practical steps to follow on the app. Nothing here has been run by a person yet: every result is **NOT TESTED** until you fill it in.
Fill in "Actual", "Result", "Severity" and "Notes"; do not edit "Expected" without saying why. Add a new row for anything you find.

**Test session** (fill in once per session)
- Build / commit: ______ (CI run: ______) · Device and iOS: ______ · Date: ______ · Tester: ______
- Start state: fresh install / existing save (say which). Launch with `-showcase` only for screenshots, never for these tests.

**Result:** PASS · FAIL · BLOCKED (could not reach the step) · NOT TESTED
**Severity (for FAIL):** S1 data loss, crash or money wrong · S2 feature does not work or misleading · S3 confusing or ugly · S4 cosmetic
Tip: write money amounts exactly (e.g. cash before £251,000 / after £230,500) so differences can be checked against the screen.

## 1. Start a game
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T1.1 | Fresh install, launch | Start screen: name, country, start button; no crash | | NOT TESTED | | |
| T1.2 | Enter a name, pick a country, start | Company tab opens with Home summary (net worth, cash, "Next day"), 5 tabs: Company, Team, Group, Projects, Inbox | | NOT TESTED | | |
| T1.3 | Open each of the 5 tabs once | Each opens; empty states are written in plain words (no blank screens, no placeholder text) | | NOT TESTED | | |
| T1.4 | Tap the More button (Company or Group) | Menu/sheet with News, Stats, Activity, Luxury, Settings, Achievements, Rich list, Ranking, World around you; each opens and closes | | NOT TESTED | | |
| T1.5 | On iPad: look at the sidebar | Five tabs plus a More list; only the selected tab's toolbar is shown (no stacked buttons) | | NOT TESTED | | |

## 2. Create a company
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T2.1 | Company tab > + (New company) | Trade list; choose a Café | | NOT TESTED | | |
| T2.2 | Pick city, legal form, size | Start cost, remaining cash and risks shown **before** you confirm | | NOT TESTED | | |
| T2.3 | Confirm | Company created in Setup; cash falls by the shown amount (note both) | | NOT TESTED | | |
| T2.4 | Open the company: Setup checklist | Each open row opens the place where it is fixed (premises, equipment, money) | | NOT TESTED | | |
| T2.5 | "Fill in what is missing…" | Asks for confirmation with the cost; after confirming, missing items are done | | NOT TESTED | | |
| T2.6 | "Open for business" | Status changes from setup to open; overview shows health, "Run by you", Team link | | NOT TESTED | | |
| T2.7 | Try to start a company with too little cash | Refusal in words (not a silent failure, no crash) | | NOT TESTED | | |
| T2.8 | Create a second company, then a third; open Company list | List shows both; sorted by "Needs attention"/profit; each opens its own overview | | NOT TESTED | | |

## 3. Hire staff
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T3.1 | Company > Team > Find workers: pick a role | Job ad / Network / Agency with prices; slower/cheaper vs faster/dearer is explained | | NOT TESTED | | |
| T3.2 | Run a Job ad | Cost taken once; candidates appear | | NOT TESTED | | |
| T3.3 | Open a candidate | CV claim, age, asking pay; offer options (ask / lower / higher; full-time, part-time…) | | NOT TESTED | | |
| T3.4 | Offer below ask | Result shown (accepted, counter or refused) in words | | NOT TESTED | | |
| T3.5 | Hire | Person appears in the staff list; monthly wages in the header rise by their wage | | NOT TESTED | | |
| T3.6 | Open the person | Profile: mood, record, character; actions raise / talk / warning / promote / contract / let go | | NOT TESTED | | |
| T3.7 | Let someone go | Cost (notice + severance) shown first; after confirm, cash falls by that amount and the person is gone | | NOT TESTED | | |
| T3.8 | Hire a manager (Company > Team > Management) | Search cost shown; candidate list; offer; manager row with authority picker; "Run by <name>" on the overview | | NOT TESTED | | |
| T3.9 | Team tab with 1 company run by you | "Needs you" lists real problems; companies list says "You run it"; tapping a row opens the right company on the right section; Back returns to Team | | NOT TESTED | | |
| T3.10 | Team search: type part of an employee's name | Result opens the owning company's Team section | | NOT TESTED | | |

## 4. Transactions
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T4.1 | Company > Finances > You and owners: Put in an amount | Company cash up by the amount, personal cash down by the same; both visible | | NOT TESTED | | |
| T4.2 | Take out an amount | Reverse; refused with a reason if it would leave the company short | | NOT TESTED | | |
| T4.3 | Finances > Loans: choose a term | Rate, monthly payment, total interest and total repaid shown before confirm | | NOT TESTED | | |
| T4.4 | Confirm the loan | Cash up; loan listed; instalment appears in "what falls due" | | NOT TESTED | | |
| T4.5 | Repay part, then all | Cash down; loan reduced/removed; interest to come updates | | NOT TESTED | | |
| T4.6 | Group > Money > Bank: personal loan and a fixed deposit | Terms and totals before confirm; balances change correctly | | NOT TESTED | | |
| T4.7 | Check totals: cash + company cash + savings vs net worth on Home | No unexplained difference after each transaction (write numbers) | | NOT TESTED | | |
| T4.8 | Finances > Settings: rename the company | Name changes everywhere (list, Team, Inbox) | | NOT TESTED | | |
| T4.9 | Finances > Settings: close for a while, then reopen | Consequences shown first; status and costs follow | | NOT TESTED | | |

## 5. Progress time
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T5.1 | Tap "Next day" 7 times | Day counter moves; on the week the week number advances; payday/bills messages appear in the Inbox | | NOT TESTED | | |
| T5.2 | Use the fast-forward ("until needed") | Stops with a toast when a decision is waiting; stoppable with "Stop" | | NOT TESTED | | |
| T5.3 | Play 4 months with one café | Revenue, wages, rent and bills happen on their dates; cash never silently changes without a line in transactions | | NOT TESTED | | |
| T5.4 | Let cash run low on purpose (hire several, spend) | Warnings in Team ("less cash than a month of wages") and Company overview ("behind on payments") before anything breaks | | NOT TESTED | | |
| T5.5 | Miss a payment | Late interest / supplier cut-off messages; "Behind on payments" card in Finances | | NOT TESTED | | |
| T5.6 | Inbox: answer a decision | Options show cost/benefit/risk and what happens if ignored; confirmation before the answer; result shown | | NOT TESTED | | |
| T5.7 | Ignore a decision until it expires | The cheapest answer is taken as the text says | | NOT TESTED | | |

## 6. Reports
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T6.1 | Home: report prompt after a period | Sentence with real figures; "Read the full report" opens Reports | | NOT TESTED | | |
| T6.2 | Group > Money > Reports: week, month, year | Summary / Transactions / Bills and payroll switch; numbers change with the period | | NOT TESTED | | |
| T6.3 | Company > Finances > Accounts: P&L, Balance sheet, Cash flow, Tax, Transactions | Each shows data; balance sheet adds up; cash flow ending cash = company cash | | NOT TESTED | | |
| T6.4 | Compare profit/cash for one company on: Company list, Overview, Team, Group | Same figures everywhere (write them) | | NOT TESTED | | |
| T6.5 | Money text | Amounts formatted consistently ("£11k", "£251,000", no "£11 k") | | NOT TESTED | | |

## 7. Saving and loading
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T7.1 | More > Settings: save now | "Saved." toast | | NOT TESTED | | |
| T7.2 | Note cash/net worth/week, force-quit, relaunch | Start screen shows a Continue card with real player, week, companies; Continue restores identical figures | | NOT TESTED | | |
| T7.3 | Play 1 week after loading | Game continues normally; no duplicated messages or payments | | NOT TESTED | | |
| T7.4 | Start a new game over an existing save | Asks before replacing | | NOT TESTED | | |
| T7.5 | Export the save, then import it again | Imported game equals the exported one (note week and net worth) | | NOT TESTED | | |
| T7.6 | Import a corrupt/empty text | Clear error, existing save untouched | | NOT TESTED | | |
| T7.7 | Install a build over an older save (if you have one) | Old save loads without loss | | NOT TESTED | | |

## 8. Errors and edge cases
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T8.1 | Every action with too little cash (hire, borrow, put in, buy) | Refusal toast in words; money unchanged | | NOT TESTED | | |
| T8.2 | Double-tap a confirm button | Done once only | | NOT TESTED | | |
| T8.3 | Open a company, switch to Team and back, then open another company | Second company opens on Overview, not on the first one's section | | NOT TESTED | | |
| T8.4 | Deep link: Inbox message about a company > "Open <company>" | Opens that company; Back works | | NOT TESTED | | |
| T8.5 | Team decision row | Opens the exact message in the Inbox | | NOT TESTED | | |
| T8.6 | Rotate iPad / split view | No overlapping or cut-off content | | NOT TESTED | | |
| T8.7 | Sell shares / raise money in a sole trader | "Only a limited company…" message, no crash | | NOT TESTED | | |
| T8.8 | Go bankrupt on purpose (no cash, bills unpaid, 4+ months) | Warnings first; failure flow ends the game with a run summary | | NOT TESTED | | |
| T8.9 | Any screen shows blank, "undefined", "NaN", zero where money is expected, or a button that does nothing | Record as FAIL with screen name and steps | | NOT TESTED | | |

## 9. Extra packs (add when stages land)
- Delegation with 10 stores and a store manager; chain, regional manager, holding (after Stage 1 dismissal merge).
- Acquisitions, ventures, expand abroad, boards, head office.
- Country rules: start in two countries and compare wages, notice and tax.
- Balance feel: play 3 years of a shop, a contractor, a rental company.
- Pay day and confirm threshold (stage 2, controls). Status of each row: NOT TESTED.
  - 9.P1 Company > Finances > Payroll and bills, company with staff, this month's payroll unpaid. Steps: tap another pay day, confirm. Expected: "Queue the change" dialog names this month's pay date and the first date on the new day; after confirming the card shows the pending change; old day stays until payroll runs, then the new day applies. NOT TESTED.
  - 9.P2 Same screen after payday has passed (month paid). Steps: choose an earlier day (e.g. the 1st). Expected: change applies at once, first pay date is next month, this month is not paid again. NOT TESTED.
  - 9.P3 Advance days over 3 months across a change. Expected: exactly one "Payday" message per month, none skipped; wages owed accrue weekly; cash drops once per payday. NOT TESTED.
  - 9.P4 Choose "Last day": row says wages fall the same day as rent and supplier bills. Company with no staff: card says nothing to pay. Late wages: note says the change waits. NOT TESTED.
  - 9.P5 Month-end bills leave on the last day of the month and payday on the chosen day (not on the 1st). NOT TESTED.
  - 9.C1 Settings > How much I decide > Ask before spending, default "Always ask": job ad / executive search show the confirmation. NOT TESTED.
  - 9.C2 Raise the step above the fee: job ad / executive search run at once and the toast says what was paid. Dismissals, wind-up, closing, selling, loans, dividends still ask at every setting. Restart the app: setting kept; export/import a save: setting not in the save. NOT TESTED.

## Results summary (update after each session)
| Section | Tests | Pass | Fail | Blocked | Not tested |
|---|---:|---:|---:|---:|---:|
| 1 Start | 5 | 0 | 0 | 0 | 5 |
| 2 Company | 8 | 0 | 0 | 0 | 8 |
| 3 Hire | 10 | 0 | 0 | 0 | 10 |
| 4 Transactions | 9 | 0 | 0 | 0 | 9 |
| 5 Time | 7 | 0 | 0 | 0 | 7 |
| 6 Reports | 5 | 0 | 0 | 0 | 5 |
| 7 Save/load | 7 | 0 | 0 | 0 | 7 |
| 8 Errors | 9 | 0 | 0 | 0 | 9 |
| **Total** | **60** | **0** | **0** | **0** | **60** |
