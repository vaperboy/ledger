# Owner decisions (running log)

## 31 Oct 2026, before Stage 2 (finance)
- Share capital on conversion: the OWNER pays it personally; the company pays only the fee. The fee payer (personal or company account) is chosen by the player with balances shown.
- Loans after conversion: the personal guarantee stays; the player can renegotiate through a bank discussion.
- Goodwill on conversion: value-neutral (remove the 0.85 sole-trader goodwill discount).
- Banking Payroll/Tax/Savings per company: display-only reserves computed from what is owed (no real sub-accounts).
- Share capital amount: the country minimum (as today); the owner can add capital later.
- Accounting access: NAMED USERS ONLY (nobody has access unless the owner adds them, including the accountant). Owner has full access.
- Payroll responsibility: replace the player-chosen modes with the derived rule (qualified accountant, else suitable manager without fee, else the player).
- Employer cost shown includes paid-leave cover (one authoritative number).

## 1 Nov 2026, remaining decisions (all asked via buttons)
Structure: merge Premises + "Where you work" into one Premises screen keeping all functions (home trades get a working-from-home view if useful); Upkeep: rename and split by owner (equipment upkeep under Manage > Equipment, stock policy under Inventory); five tabs stay (Home, Team, Group, Projects, Phone); Home quick boxes CONFIGURABLE (player picks up to four shortcuts); Ventures live ONLY as a Phone app (Projects tab keeps projects; remove other entries to Ventures); trade-specific sections stay sub-pages of Manage / Stats.
Employment: never auto-assign an accountant at creation (only if the legal form requires); after hiring an employee may refuse hour cuts, role changes and pay-plan downgrades, never a pay rise, with likelihood by the person's temperament; candidate asks centred on market pay with spread by skill/experience; age-tier ask multipliers removed (asks from experience and qualifications); the employer-cost preview must equal what payroll books (no change to booked wages); the two-page hiring negotiation replaces the one-page flow for ALL hires (workers, managers, executives, office, analyst).
Startups/investment: a founded startup becomes a real Company; shares are real integer counts with a price per share; cancelling a product refunds the unspent part; buying a rival transfers staff, equipment and customers WITH integration costs (and a loyalty dip).
Payroll/pricing/gates/order: manual payroll alert only when wages are late or unapproved on the pay date; typed prices use a PER-TRADE price range from data (a balance task); chain/franchise gates: real requirements (capital, cash, stores open, reputation, documents) plus a short review time, pure waiting-time gates dropped; daily event order: keep current and document it (revisit in Stage 8).
Release: exclude the five unused art sheets from the release build (files stay in the repo); disable main.yml and yesmain.yml but keep the files. No deletions approved.

## 1 Nov 2026, Company screens batch (owner feedback from testing)
Pricing: one pushed screen, no price-level picker, no Market > Pricing. How you sell: popup only, choices and cost only; Ways to sell live in it. Develop something new: per trade, only where the engine has trade-specific projects (families prod, venue, retail, svc); hidden for project, logistics, rental, finance, energy, club and holding. Projects: a part of Sales for project businesses only. Customers: a part of Stats (Finances / Customers); reviews in the Reviews app; Security with insurance. Market: Phone app with a business selector; the share graph only with a data or market analyst. Awareness and reputation are words, ratings stars out of 5 (`StandingWords`). Owner: capacity, weekly profit and demand stay at the top of Manage; no Performance part. Typed prices stay in Stage 5. Rival review lines are labelled typical comments.
## 1 Nov 2026, Stages 7-10 additions (owner)
- Motion and feel: add animations and fluid mobile movement: swipe left-to-right to go back (re-enable the interactive pop gesture everywhere), swipe between sub-tabs/segments, restrained meaningful animations, pressed feedback; Reduce Motion respected.
- Reward feedback: after simulating a day, completed missions, awards and milestones appear as a CELEBRATORY POPUP with a light haptic on the main page (queued after the day, real reward shown), animated and respecting Reduce Motion.
- Reports pacing: DAILY = small summary chip; WEEKLY, MONTHLY and YEARLY = a report sheet the player reads and dismisses with one tap before the next day runs (a natural pause, not a timer). Real figures only; no arbitrary waiting periods; routine reports must not repeat or overlap.

## Stage 7 and 8 implementation notes (1 Nov 2026)
- Reports: daily = a chip beside the week bar; weekly, monthly and yearly = one sheet read with one tap before the next day runs; a year covers its month and week.
- Rewards: trophies, ambition milestones, finished first steps and the mission appear as a queued popup with the real reward.
- Inbox confirmation: only spends (subject to the player's size setting) and irreversible answers (sales, court settlements, ransoms, dismissals) ask once.
- Court judgments are a liability (payables "legal") paid from cash above wages owed; wages come first.
- Home: the profit and due cards were removed to fit the command centre; that information stays in the Bank app and in Top priorities when a shortfall exists.
