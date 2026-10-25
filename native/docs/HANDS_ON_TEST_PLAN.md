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

### 9.M Marketing and how you sell (stage 2, batch 2B)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9B.1 | Open a barber (or any trade with add-ons) > Operations > How you sell; switch on two add-ons | Both stay on; switching one off leaves the other; an add-on needing a licence asks first with fee and weeks | | NOT TESTED | | |
| T9B.2 | Marketing > pick a channel, a length (4/12/26 weeks, Until I stop it), tap a budget | Confirmation shows weekly budget, total cost for the length, the lock, "results vary"; no customer or reach number anywhere | | NOT TESTED | | |
| T9B.3 | Start a 4-week campaign and play 5 weeks | Campaign stops by itself; card says "Ends in N weeks" before; money stops leaving | | NOT TESTED | | |
| T9B.4 | Try to switch off a campaign inside its minimum weeks, or choose a length below the channel minimum | Refusal toast with the weeks left; nothing changes | | NOT TESTED | | |
| T9B.5 | Café > Operations > How you sell > pick a different concept | Confirmation: changeover cost, weeks at 75% capacity, on-paper effects, "no guarantee"; after confirming cash drops by that amount and capacity is lower for those weeks | | NOT TESTED | | |
| T9B.6 | Change the same choice again straight away | Refused: "Still changing over" until the stated week | | NOT TESTED | | |
| T9B.7 | Change with too little cash | Refusal says how much is needed; nothing changes | | NOT TESTED | | |
| T9B.8 | Chain with 2+ stores > Chain rules > pick a "how you sell" standard | Confirmation lists stores changing, total cost, and stores that cannot (kept as exceptions with reason); stores then show that choice locked with the chain's name | | NOT TESTED | | |
| T9B.9 | In such a store try to change the locked choice; then set the chain rule to "Each store decides" | Locked and refused first; free for the store afterwards (with its own changeover) | | NOT TESTED | | |
| T9B.10 | Marketing > last channel "Prime-time TV ..." in two countries | Named from that country's own broadcast moment; budgets bigger in more populous countries; independent shop gets little for the money | | NOT TESTED | | |
| T9B.11 | Team a marketing manager and leave it running for months | Manager never starts Prime-time TV | | NOT TESTED | | |

### 9.S Suppliers (stage 3, suppliers)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9S.1 | Open a cafe (or hotel) > Operations > Suppliers | One section listing Goods, Repairs (if equipment) and each service own companies could supply; each row names the current provider, price vs market, reliability and yearly saving/cost | | NOT TESTED | | |
| T9S.2 | Tap Goods, pick a different outside supplier | Confirmation shows price, discount, quality, terms, delivery, risks and saving vs now; after confirming a toast says who now provides it and the row updates | | NOT TESTED | | |
| T9S.3 | Take a supplier to lunch twice within four weeks | Confirmation shows the cost; first works and raises the relationship/discount, second says to wait; cash drops once | | NOT TESTED | | |
| T9S.4 | Hotel with no cleaning company of yours, tap Cleaning | Locked line names the kind of company that would provide it (a cleaning company in the same city); no create button; outside option current | | NOT TESTED | | |
| T9S.5 | Add a cleaning company, wait for it to open, tap Cleaning on the hotel, choose it at cost plus 10% | Three price modes listed with saving per year; confirm; row shows "Yours"; 20 weeks later the books still balance | | NOT TESTED | | |
| T9S.6 | Same input, choose Outside suppliers | Link removed, toast; the supplier company's page no longer lists "Supplies <hotel>" | | NOT TESTED | | |
| T9S.7 | Company > Chain: no second "Supply from your own companies" card | A single link row to Operations > Suppliers; it opens that section | | NOT TESTED | | |
| T9S.8 | Chain with 3+ stores > chain page > Suppliers | Usual provider per input with "n of m stores"; stores that differ listed as exceptions, each opening that store's Operations; says each store chooses | | NOT TESTED | | |
| T9S.9 | Business customer that runs a cleaning trade but you barely know | Listed greyed with "get to know them better"; cannot be chosen; after a better relationship it can | | NOT TESTED | | |
| T9S.10 | Group > People you buy from still shows lunch and the board goods deal | Board agreement text appears in each company's Suppliers section | | NOT TESTED | | |

### 9.T Supplier terms: chain supplier rule, payment terms, price talks (stage 3, supplier-terms)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9T.1 | Chain with 3+ cafes > chain page > Suppliers > Set a chain-wide provider > Goods > pick a supplier > confirm | Confirmation lists how many stores switch, which cannot and why; afterwards a "Chain rule · Goods" block with a Mandatory chip and "n of m stores follow it" | | NOT TESTED | | |
| T9T.2 | Open one of those stores > Operations > Suppliers > Goods and tap another supplier | A lock line says the chain sets this; the option does not switch | | NOT TESTED | | |
| T9T.3 | Chain page > "Each store decides" on the rule, confirm | Rule block disappears; the store can switch its supplier again; stores keep the provider they had | | NOT TESTED | | |
| T9T.4 | Chain of restaurants, own cleaning company in the same city but one restaurant in another city (or an own company with no spare capacity): set the cleaning rule to the own company | The far store (or all stores when the cleaner is full) is listed under the rule as keeping its own with the reason; the rest switch | | NOT TESTED | | |
| T9T.5 | A franchised unit inside the chain when the rule is set | The unit is not switched and the rule text says franchised units decide themselves | | NOT TESTED | | |
| T9T.6 | Open a new store into the chain after a rule is set | The new store follows the rule (or a note says why not) | | NOT TESTED | | |
| T9T.7 | Hotel buys cleaning from your own company > Cleaning > Payment terms > 30 days | Confirmation explains the invoice; later the hotel's Finance > what falls due lists "Invoice · <supplier>" rows by due date; the balance sheet shows the debt on the hotel and a customer debt on the cleaner | | NOT TESTED | | |
| T9T.8 | Let the hotel's account run dry before an invoice falls due | Message "Late payment"; the invoice grows with interest each week; when money is back it is paid and the lines go | | NOT TESTED | | |
| T9T.9 | Cafe with a supplier you know well > Goods > Payment terms | 60 days is offered only to close contacts (greyed with the reason otherwise); cash on delivery shows a small discount, longer terms a small charge | | NOT TESTED | | |
| T9T.10 | Cafe on 30-day terms, stop paying for 6+ weeks | Supplier cools (relationship falls), the negotiated price is withdrawn, then "Suppliers want cash", then "Suppliers stop delivering"; paying and keeping to terms later restores normal delivery | | NOT TESTED | | |
| T9T.11 | Goods > an outside supplier > "2% off" in the row | The supplier accepts, counters with its own figure (Accept / Counter / Walk away appear under the row) or refuses; asking far too much ends the talks and shows when they will talk again | | NOT TESTED | | |
| T9T.12 | Same ask to a supplier you know well and to a stranger | The friend gives more and listens for more rounds | | NOT TESTED | | |
| T9T.13 | Own company as supplier | No price talk is offered (the price is the mode you pick) | | NOT TESTED | | |
| T9T.14 | Company with a business customer > Customers | The customer's line shows what they still owe; a slow payer shows "paid late n times in a row"; cash comes in weeks after the sale | | NOT TESTED | | |
| T9T.15 | Save and reload with invoices open, a negotiated deal and a chain rule | All three are still there and the books balance | | NOT TESTED | | |

### 9.M Money and supply: delivery, intercompany VAT, repair terms, franchise supplier locks (fix/money-supply)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9M.1 | Cafe or restaurant > Ways to sell > switch on the delivery app | The row says the lift applies only to delivered orders (a % now) and that the courier is set under Suppliers | | NOT TESTED | | |
| T9M.2 | Same company > Operations > Suppliers > "Delivery to customers" | Outside courier is current, with its reliability and cost per delivered order; with an own courier company in the same city it is offered with Market price / Cost + 10% / At cost | | NOT TESTED | | |
| T9M.3 | Switch delivery to your own courier company; look a few weeks later | The row shows % delivered; the courier books revenue; customers follow the delivered share; switching the add-on off ends the cost | | NOT TESTED | | |
| T9M.4 | Courier company closes or is full | Delivery falls back to the outside courier's reliability; fewer customers from the add-on | | NOT TESTED | | |
| T9M.5 | Bakery, hardware shop, webshop with an own courier company | "Parcel delivery" is listed under Suppliers for each | | NOT TESTED | | |
| T9M.6 | Hotel buys cleaning from your own company (VAT country); check both companies' VAT | Supplier owes VAT on the transfer, the registered hotel reclaims it; a hotel below the VAT threshold shows it as a cost | | NOT TESTED | | |
| T9M.7 | Cafe with a repair supplier you know well > Repairs and upkeep > Payment terms | Cash on delivery / 30 / 60 days like goods; upkeep appears as "Invoice" under what falls due; terms lapse with a message if the relationship falls | | NOT TESTED | | |
| T9M.8 | Hotel owes your own cleaning company on 30-day terms and cannot pay for 4+ weeks | Message "<buyer> is short-paying <supplier>"; the cleaning option shows a risk line and delivers less; paying clears it | | NOT TESTED | | |
| T9M.9 | Start a franchised cafe/restaurant/bakery from a regional or bigger brand | Goods > lock line names the brand and its approved supplier; other suppliers do not switch; the approved one is current | | NOT TESTED | | |
| T9M.10 | Start a franchised gym or a local (tier 1) food brand | No supplier lock | | NOT TESTED | | |

### 9.B Life stories and what you can fund (stage 2, background)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9.B1 | Start screen: pick a country, read "Your story" | Start-up loan and Heir each show cash, debt and monthly repayment (or "no debt"), business owned, credit; numbers change with the country | | NOT TESTED | | |
| T9.B2 | Choose Heir, pick the family cafe city, Begin | Game opens with an open cafe in that city, a small team, only the savings in your account, no loan on the Finance screen | | NOT TESTED | | |
| T9.B3 | Heir: play one month | No errors; the cafe trades; statement shows the inheritance lines once | | NOT TESTED | | |
| T9.B4 | Choose Start-up loan (default), Begin | Same as before: loan equals the cash, no company | | NOT TESTED | | |
| T9.B5 | Quit to menu, Continue an Heir game | Loads with the cafe, story unchanged | | NOT TESTED | | |
| T9.B6 | Phone > New company at game start | Leads with trades you can fully fund, cheapest first, each with its start cost; a line says how much you have | | NOT TESTED | | |
| T9.B7 | Turn on "Show everything" | Every trade listed; unaffordable ones show "X short"; banned ones show the reason; none is disabled | | NOT TESTED | | |
| T9.B8 | Open an unaffordable trade | Detail cost equals the list cost (same size and form); registering is still allowed | | NOT TESTED | | |
| T9.B9 | Search a trade name | Finds it whether or not it is affordable | | NOT TESTED | | |
| T9.B10 | Add savings (or earn money), reopen New company | More trades appear in the funded list | | NOT TESTED | | |

### 9.N Negotiation: counter offers, patience, automatic hiring (stage 2, negotiation)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9.N1 | Company > Team > Find workers, open a candidate | Row shows "going rate a month" (never their asking wage); offers 90 / 100 / 115 / 130% of it | | NOT TESTED | | |
| T9.N2 | Offer 90% to a strong (high claimed skill) candidate | They answer with their own figure and buttons Accept <amount>, Counter, Walk away. Text says "would take the job for this much" | | NOT TESTED | | |
| T9.N3 | Tap Accept on the counter | Hired at exactly that wage; the wage appears on the staff row; money booked once | | NOT TESTED | | |
| T9.N4 | Tap Counter, pick an amount; repeat until the text says "as low as they will go" | Each round is answered (hired, a new counter, or a flat no); the last counter is marked final | | NOT TESTED | | |
| T9.N5 | After "as low as they will go" offer less again | "<name> lost patience and took another job"; the candidate disappears from the list | | NOT TESTED | | |
| T9.N6 | Offer far below the going rate (the 25% Counter amounts after a high counter) | "took that as an insult and named no figure"; a round of patience is used | | NOT TESTED | | |
| T9.N7 | Over several candidates, note counters far above the going rate | Now and then a counter is much higher than the going rate (unrealistic); the player can still refuse it or walk away | | NOT TESTED | | |
| T9.N8 | Team > a vacant department head (executive search, hire); Group > executive posts; Main office roles | Same row: going rate shown, counter / accept / walk away. A senior post (group managing director) takes more rounds before the person walks away than a worker | | NOT TESTED | | |
| T9.N9 | Store manager (Company > Management), assistant manager, head-office data analyst (Market map) | Going rate shown and counters work the same way | | NOT TESTED | | |
| T9.N10 | Make a counter, close the app, reopen, offer the same again | The talk continues (same round); after about 8 game weeks without talking it starts afresh | | NOT TESTED | | |
| T9.N11 | Automatic replacement on, let a worker leave, advance a few weeks | A replacement is hired within the week, at or below the going rate for their skill; the note names them. A store with a strong manager hires cheaper / better than one run by the owner | | NOT TESTED | | |
| T9.N12 | Inbox: a worker asks for a raise (superseded by 9.C10-9.C13: employees no longer refuse a raise) | See 9.C | | NOT TESTED | | |
| T9.N13 | Sell a company: open a buyer, name a price above their offer several times | Buyer stretches, now and then refuses outright; after a few rounds it walks away (patience dots fall) | | NOT TESTED | | |
| T9.N14 | Meet a rival owner, offer to buy at a low multiple several times | Counters, then "ends contact for now" and the owner does not answer for about half a year | | NOT TESTED | | |

### 9.G Group and Projects (stage 3, groupprojects)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9G.1 | Group > Structure with 3+ companies, some in a chain, a holding, a franchise, some alone | "Stand alone" lists only companies in none of those, each with trade, city, health, value and yearly profit; tap opens the company; Back returns to Group | | NOT TESTED | | |
| T9G.2 | 9+ stand-alone companies | Search box appears; list shows 8 with "Show all"; worst profit first | | NOT TESTED | | |
| T9G.3 | Franchisor with applicants: Group > Structure > Franchises | Applicants listed under the franchisor row; tapping opens the same talk as Company > Chain; an offer there shows in both places | | NOT TESTED | | |
| T9G.4 | Projects tab with a builder, event agency or developer | "Under way" rows show milestone dots, next date, what blocks; tender closing within 2 weeks and held jobs appear under "Needs you" | | NOT TESTED | | |
| T9G.5 | Open a project row | Detail shows contract/cost so far or paid so far, milestones with dates, what is in the way, "If it runs late" with the money at stake; "Open company > Projects" works and Back returns | | NOT TESTED | | |
| T9G.6 | Developer: advance through zoning, build, sell | Stage dots and dates follow the engine; a delayed build shows the held-up message | | NOT TESTED | | |
| T9G.7 | No project company | Real empty state; a project company with nothing booked shows the "nothing under way" text | | NOT TESTED | | |
| T9G.8 | Group > Giving back > pick city, Give | Confirmation names cost, standing and legacy gain, always asks; after confirming cash drops once, mark appears, toast reports; same gift in same city shows "Done" | | NOT TESTED | | |
| T9G.9 | Giving back with too little cash | Button disabled with "Short by ..." | | NOT TESTED | | |
| T9G.10 | Start a foundation, advance a year | Confirmation warns it is permanent; Foundation shows endowment and given; a message arrives yearly | | NOT TESTED | | |
| T9G.11 | Market > Groups > Open profile | Rival group profile shows owner, strategy, ambition, sites, cash/debt words, trades, countries, overlap with your companies, moves; Back returns to Market | | NOT TESTED | | |

### 9.V Navigation, labels and money text (stage 3, nav)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9V.1 | Inbox > a message with "Open <company> ->"; then Back | Company opens on the Inbox's own stack; Back returns to the Inbox at the same place, not the Company list. Automated: NavigationBackTests.testBackFromInboxCompanyLinkReturnsToInbox (skipped if the showcase game has no such message) | | NOT TESTED | | |
| T9V.2 | Projects > Work > a row; then Back | Company opens on its Projects section; Back returns to Projects. Automated: testBackFromProjectsReturnsToProjects (skipped in the showcase game: no project company) | | NOT TESTED | | |
| T9V.3 | Company tab (Home) > a suggestion that opens a company; then Back | Back returns to Home. Automated: testBackFromHomeSuggestionReturnsToHome (skipped if no such suggestion) | | NOT TESTED | | |
| T9V.4 | Team > a vacancy, a decision or a company row; then Back. Group > a chain or holding row; Back. Group > Money > Reports > a company line; Back | Each returns to the screen it was opened from | | NOT TESTED | | |
| T9V.5 | Company tab > a suggestion or "Read the full report" (goes to Group > Money); and Company > Needs you > Decide (goes to Inbox) | The destination tab shows "Back to Company" at the top; tapping it returns to the Company tab where you were. Switching tabs by hand removes the bar | | NOT TESTED | | |
| T9V.6 | More > News > a company link | The More sheet closes and the company opens on the tab behind it; Back returns there | | NOT TESTED | | |
| T9V.7 | Group > Money | Screen title is "Group money" (not "Money"); the segment is still "Money" | | NOT TESTED | | |
| T9V.8 | Home key figures vs Group > Money > Overview (T6.4/T4.7) | Home says "Personal cash" (cash + savings). Money says "Cash across group" and, under it, "of which personal cash and savings" equal to Home's figure; the difference is the cash in your companies. Company > Finances says "Company cash" | | NOT TESTED | | |
| T9V.9 | Read Inbox messages and News with amounts over 10,000 | Written "£11k", "£2.5M", never "£11 k"; names such as "Mr M Smith" unchanged | | NOT TESTED | | |
| T9V.10 | iPad sidebar | Team's icon lines up with the other tabs' titles | | NOT TESTED | | |

### 9.C Company screens: creation flow, insurance, advisers, payroll, working from home (stage 3, company)
| ID | Steps | Expected | Actual | Result | Sev | Notes |
|---|---|---|---|---|---|---|
| T9.C1 | Company > + > pick a cafe | Top figures: start-up cost, what you have, and "Left for you" (or "Short by"). Below: city, legal form, size, name, premises, cost lines, risks, then "Review and start" | | NOT TESTED | | |
| T9.C2 | In Premises pick the cheapest place, then the dearest; switch Rent to Buy | Premises line and total change each time; Buy shows price, down payment and the 15-year mortgage; "Left in your accounts" falls | | NOT TESTED | | |
| T9.C3 | Review and start with a rented place | Confirmation states total, cash into the company, what you keep, the place, and the risk. After Start the company opens with that place (Equipment > Premises shows it) | | NOT TESTED | | |
| T9.C4 | Same with Buy | Company owns the place (no rent), a commercial mortgage appears under its Loans | | NOT TESTED | | |
| T9.C5 | Sole trader with very little cash | "Short by" shown, risk text says opening waits for money; if the account cannot cover registration and capital the button is disabled with the amount missing | | NOT TESTED | | |
| T9.C6 | New company for a home trade (consultancy, plumber) | Premises says it starts at home with no rent; no place list | | NOT TESTED | | |
| T9.C7 | A trade with franchise brands: open it, tab "Under a brand" | Brands for that trade with fee, strength, units; Apply, Meet, Start with this deal work as in Franchises; start screen shows left-over cash, risks and asks to confirm | | NOT TESTED | | |
| T9.C8 | Company > Operations > Insurance and advisers (no insurer) | Policies are locked with "choose an insurer first"; tapping one shows that message | | NOT TESTED | | |
| T9.C9 | Hire an insurer, switch on a policy, switch it off | Each asks first with the monthly cost; summary figures and the Operations row update; dropping the insurer asks and warns | | NOT TESTED | | |
| T9.C10 | Hire a law firm and change the accountant (also a firm of your own, if you own one) | Fee per month shown before confirming; old one is dropped; accountant no longer appears as a separate block in Operations | | NOT TESTED | | |
| T9.C11 | Operations of a home-trade company with 4+ people working at home | "Where you work" warns that morale and quality slip; "Find a workshop/office" lists places with rent, deposit, price | | NOT TESTED | | |
| T9.C12 | Rent one with enough company cash; try with too little cash | Confirmation lists what leaves now; after: "Rented ..." and the section shows the place. With too little cash the button is disabled with "needs X more" | | NOT TESTED | | |
| T9.C13 | Work from home again | Confirmation states the deposit returned (or sale value less mortgage); cash changes by that amount | | NOT TESTED | | |
| T9.C14 | Finances > Payroll and bills, owner-run company with staff | "Payroll run" shows next pay day, amount, cash; "Approve this month's payroll" asks, then says approved; the same Inbox approval message does not pay twice | | NOT TESTED | | |
| T9.C15 | Change who runs payroll to the accountant, then manager (company without a manager) | Fees shown per month; manager is locked with "Needs a manager first"; change confirmed and reported | | NOT TESTED | | |
| T9.C16 | Let pay day pass without approving, then Run payroll now | Staff are paid, result reports amount paid and any shortfall | | NOT TESTED | | |

### 9.C Contract discussion (stage 2, contracts) — screens NOT TESTED by hand (engine tests: ContractTalkTests)
| ID | Steps | Expected | Result | Status | Date | Notes |
|---|---|---|---|---|---|---|
| T9.C1 | Company > Team > open a worker > "Contract discussion…" | One sheet with the topics Pay rise, Promotion, Hours, Pay basis, Bonus plan, Benefits, Notice, Move; unavailable ones are greyed with the reason. No separate raise menu, Promote or Contract and pay buttons remain on the profile | | NOT TESTED | | |
| T9.C2 | Pay rise 3% / 6% / 10% | "What it means" shows cost a month with employer charges, chance they hand in notice within a year before and after, the country's minimum pay. Confirm: they take it at once, never refuse | | NOT TESTED | | |
| T9.C3 | Promotion: choose a post, offer about half of what they ask | They answer with a higher figure (never a refusal); after a few rounds they take the post at what you offered and are unhappy | | NOT TESTED | | |
| T9.C4 | Hours: set hours, offer full time to a part-timer, change seasons | Preview shows pay and hours; a person who wants part time says why in words | | NOT TESTED | | |
| T9.C5 | Pay basis (seller): fixed, salary and commission, commission only | Commission only shows base 0; a security-minded person is warned they may resign | | NOT TESTED | | |
| T9.C6 | Bonus plan: manager profit share, seller commission rate | Shows the monthly cost at recent profit; a profit share cannot be cut here | | NOT TESTED | | |
| T9.C7 | Benefits: switch a perk on, give an estate agent an own car | Preview says it covers the whole company, shows cost and fewer people leaving; mileage cost for the car | | NOT TESTED | | |
| T9.C8 | Notice: +4, +8, +12 weeks; later let the person go without cause | Dismissal confirmation shows the extra notice pay | | NOT TESTED | | |
| T9.C9 | Move: a worker to another store of the chain, a manager to a company without one | Pay moves with them; the cost is unchanged; the old store is left short | | NOT TESTED | | |
| T9.C10 | Inbox: a worker asks for a raise / promotion / shorter hours | Three buttons only: Agree, Delay, Decline. Agree gives what they ask | | NOT TESTED | | |
| T9.C11 | Decline a request | The preview first showed the higher chance they leave; afterwards the profile mood says turned down | | NOT TESTED | | |
| T9.C12 | Delay a request and do not answer for 4 weeks | They feel turned down (note in the activity log) | | NOT TESTED | | |
| T9.C13 | Open a request, answer with a lower figure, close the app, reopen | The talk is still open at the same round | | NOT TESTED | | |
| T9.C14 | Manager with authority level 1: "Leave it to the manager" on a request above and below the pay limit | Above: it stays with you with the reason; below: the manager agrees it and a note says so | | NOT TESTED | | |
| T9.C15 | Manager card | Profit share has no change menu (a link opens the discussion); no Give a raise, Move to… buttons | | NOT TESTED | | |

<<<<<<< HEAD
### 9.P Staff pay and benefits (branch fix/staff-pay) — screens NOT TESTED by hand (engine tests: StaffPerkCatalogueTests, WorkerBonusTests, StaffExpensesTests, PayPlansTests, ManagedRequestsTests, FixedTermTests)
| ID | Steps | Expected | Result | Status | Date | Notes |
|---|---|---|---|---|---|---|
| T9.P1 | Company > Team > Perks card | Each perk shows cost, "fewer leave among those it covers"; perks that can go to several groups show one chip per role group (manager and team leads, sellers, everyone else) with the head count; the company car only has the manager group | | NOT TESTED | | |
| T9.P2 | Switch lunch on for one group, then for the others | Each switch asks first with cost, benefit and risk; the cost line follows the people covered; with every group on the card shows the plain "On" | | NOT TESTED | | |
| T9.P3 | Open a worker's profile with perks on | Mood lists "looked after: ..." and the Record shows Perks with what they are worth a month | | NOT TESTED | | |
| T9.P4 | Contract discussion > Benefits | Perks, a perk for this person's group only, and the expense items that exist for their job (phone, uniform, training, travel); preview shows the cost and that expenses are not wages | | NOT TESTED | | |
| T9.P5 | Contract discussion > Bonus plan on a barista | None / Standard / High with a likely monthly cost; a warning if the company has no monthly targets; confirm, the profile shows the plan | | NOT TESTED | | |
| T9.P6 | Play to a month end with targets met | Inbox/activity shows targets; the staff profile shows "paid this year"; payroll cost includes employer charges on the bonus | | NOT TESTED | | |
| T9.P7 | Hire a seller: pay plan row (Salary / Salary and commission / Commission only) and commission share | Shown only for jobs that sell on commission in this trade; a security-minded candidate may say no to commission only | | NOT TESTED | | |
| T9.P8 | Hire a candidate: Contract row (Permanent / 26 / 52 / 104 weeks) | Fixed term shows the end week in the profile; a candidate who wants security declines it | | NOT TESTED | | |
| T9.P9 | Hiring row after a counter: "Your figure" stepper, "Type an exact figure", the 25/50/75% menu | Any figure can be sent; the answer appears under the row | | NOT TESTED | | |
| T9.P10 | Contract discussion, an open request or their last word | "Meet them part way" quarter/half/three-quarter buttons fill the editor; the stepper or field takes an exact figure | | NOT TESTED | | |
| T9.P11 | Contract discussion > Contract term | Permanent / fixed term / renew; preview says what ending costs under the country's rules (nothing where the data lists none) | | NOT TESTED | | |
| T9.P12 | Four weeks before a fixed term ends | Inbox asks: renew or let it end; letting it end removes them on the date with the cost shown | | NOT TESTED | | |
| T9.P13 | Company with a manager: a tired worker | An hours request is decided by the manager inside their authority (activity note), or reaches the Inbox naming the manager | | NOT TESTED | | |
=======
| T9.MS1 | Company > Operations > How you sell: tap another single choice | Confirmation shows changeover cost and weeks first, then an estimate for the next 8 weeks (customers wanting to buy, customers served, average sale, sales, left after direct costs) as low-to-high ranges with the average, a "ranges overlap" warning when it may change little, and "No guarantee" | | NOT TESTED | | |
| T9.MS2 | Same, on a trade with no weekly sales model (property, finance) | "No estimate is available for this kind of business" and the on-paper data lines instead | | NOT TESTED | | |
| T9.MS3 | Switch an add-on on then off | Each shows the estimate and a Drop/Add button; an add-on needing a licence says the figures assume it is approved | | NOT TESTED | | |
| T9.MS4 | Change a choice, then watch the company for the quoted weeks | Reduced-capacity note lasts exactly the quoted weeks, gone the week after | | NOT TESTED | | |
| T9.MS5 | A company abroad: add an add-on that needs a licence | The weeks shown for the licence are the slower abroad figure and match when it is approved | | NOT TESTED | | |
| T9.MS6 | Start a franchised unit of a regional, national or global brand; open How you sell | The choices the brand fixes (menu, format, price tier) are locked with "Your franchise agreement with X fixes this"; add-ons stay free | | NOT TESTED | | |
| T9.MS7 | Franchisee Marketing tab: a national-brand unit tries a channel outside its list; a global-brand unit tries any channel | Locked line with the reason ("does not allow local campaigns on this channel" / "reserves local marketing to the brand"); stopping a campaign still works | | NOT TESTED | | |
| T9.MS8 | National-brand unit with no local campaign for a few weeks | Weekly payment to the franchisor includes the required local share as extra brand-fund contribution; spending locally reduces it | | NOT TESTED | | |
| T9.MS9 | Chain page > rules: add-ons of a multi-choice knob | Tap add-ons into the chain's set; confirmation says every store offers exactly this set; stores that could not follow are listed under the knob | | NOT TESTED | | |
| T9.MS10 | Barber with "hair products at the till": rating very low vs high | Extra sales follow the rating, none for a badly rated shop | | NOT TESTED | | |
>>>>>>> origin/native-swiftui

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
