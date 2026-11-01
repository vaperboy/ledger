# Next day: what runs, in what order (Stage 8A)

Owner decision (1 Nov 2026): keep the current order and document it. The order below is the engine's real order
(`GameEngine.nextDay`, `tradeAndPay`, `advanceWeek`, `MiscWeekly`); it is NOT the order of the master spec's list (wages, bills, sales,
production, market, loans, applications, board). Changing it would re-baseline every trade, so it stays until the owner asks for a change.

## One press of Next day

1. **The app** (`GameStore.nextDay`): ignored while a day is already running (`isAdvancing`), while a week / month / year report sheet is
   waiting to be read, or while a reward popup is on screen. Otherwise the button shows a spinner and "Running", a 40 ms pause lets that
   state paint, then the engine runs once. Pressing twice can never advance two days.
2. **An ordinary day (days 1 to 6 of the week)** (`GameEngine.nextDay`):
   1. `DailyTrade.runDay`: sales, stock use, production for the day.
   2. `ProjectWeek.runDay`: project milestones.
   3. `Payday.onDay`, in this order inside it: court judgments left unpaid are settled from cash above the wages owed
      (`LegalDebts.settle`); then for each company the pay day (payroll runs, or is late), late-payroll handling and back pay, the
      seven-day payroll reminder, rent and supplier bills on the last day of the month, loan instalments and the other dated bills.
   4. `releaseDay`: the week's money that was worked out in advance is released to the accounts for that day.
   5. `recordDay`: the day's net worth / cash figures (the day chip reads these).
3. **The day that ends the week (day 7 to day 1 of the next week)**:
   1. `closeReportPeriods`: the week report is written; the month report too if the week ends a month; the year report if it ends a year.
   2. `stageWeek` runs `advanceWeek`, in this order: economy, markets, competitors and leagues, brokerage and fund managers, luxury;
      then per company `CompanyWeek.run` (wages accrue, costs, sales for the week) and that company's random events; rivals, price moves,
      lawsuits (court dates), cyber attacks, market map, software, tenders, auto-staffing, follow-ups of earlier events, expiry of
      unanswered decisions, strategic decisions, ventures (startups, private equity, owners), awards, special trades, chains and
      franchises (applications, supply), then the small weekly systems (`MiscWeekly`: staff record, contract talks, ambitions,
      first-step celebrations, giving, stories, press, weather), month end and year end closing, manager targets, failure checks
      (bankruptcy), portraits sweep, snapshot, game-over check.
   3. The first day of the new week is then traded and paid like an ordinary day (2.1 to 2.3).
4. **After the engine** (`GameStore.advanceOneDay`): the daily mission is checked once (`celebrateDailyGoal`), celebrations earned during
   the day are taken from the save into the popup queue, the report sheet to read is prepared (`pendingReportDigest`), the day is saved
   (with a backup every fourth week), and the day chip (net worth and cash change of that day) is set.

## What the player sees after a day

- **Ordinary day**: the week bar fills one segment, and the line above it reads "Day n of 7  ▲ £x net worth" (real change of that day).
- **Week, month or year closed**: a report sheet (revenue, profit, cash, debt, payroll, taxes, major changes, risks, decisions) that is
  dismissed with one tap before the next day can run. A year that ends also ends a month and a week: one sheet, not three.
- **Rewards**: trophies, ambition milestones, finished first steps and the day's mission appear one at a time as a popup (light haptic,
  animation skipped under Reduce Motion) once the report sheet is dismissed. The reward shown is the real one.
- **No duplicate notifications**: a decision is announced once, in the Inbox. It is no longer also written into the weekly report's
  "What happened" list (the report shows outcomes, not pending decisions). Decisions a manager has authority for are settled by the
  manager and never reach the owner's Top priorities.

## Payroll alerts (Stage 7E, owner decision)

A manual-payroll alert appears only when wages are late (wages really owed) or unapproved on the pay date. Seven days before pay day the
Inbox asks for approval; that is a decision, not an alert. A "late for cash" payroll with no wages left owed clears itself.
