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

## 1 Nov 2026 (evening), owner feedback batch from testing 1.0.9 (to be built before any new stage)
- ONE IN-GAME POPUP SYSTEM replaces the iOS confirmation dialog EVERYWHERE (iOS confirmationDialog/alert removed as a whole): an in-game 'Are you sure' popup that says what it does (cost, effect, risk), same look and logic for everything. Used only for big spends (above the player's 'Ask before spending' limit) and irreversible/destructive actions (fire, sell, close, convert...). Everything else applies immediately and can be changed back. Inbox decisions follow the same rule (today some are unanswerable because they ask an iOS confirmation for unimportant answers).
- Perks and rules: a popup list of perks, each chosen/unchosen for ALL workers, active immediately in the popup with its cost shown while active; closes by the small x or tapping outside. 'Rules' moves into Company Stats as its own box under legal and ownership.
- Company Manage: remove 'Statements' (Accounting has more); no reroute. Stats Finances: no title on 'Owed' (right under revenue/costs etc.); remove the 'Money matters' title and keep one clean box with the remaining items. 'Your time' is read-only (not editable). Suppliers: each supplier in its own closed box with a clear title and what it supplies; remove the 'Sourcing' box.
- Premises and 'Where you work' merge into ONE Phone app (Airbnb-like): listings sorted by offices, stores etc. with monthly cost and building type; tap opens the place's info page with a Rent button; rented places appear under an 'Active rents' tab where the player assigns the company that operates and pays (the CHOSEN COMPANY rents it; reassignable) and the accounting account that gets the receipt.
- Equipment and Software merge into ONE Phone app that looks like a website store (tabs for equipment and fleet removed): shows for every company type what each store type usually needs, sorted by software, tools, cars etc.; buying like Luxury: choose which store buys (which account is charged, which accounting account gets the receipt); an owned shipping company delivers (own delivery); otherwise the player pays shipping and picks EXPRESS or STANDARD; REAL DELIVERY DAYS (items arrive on the delivery date); basket -> checkout screen: choose account, 'autofill bank details' button filling the account's REAL name + number (from the Bank), 'remember me' (remembers the chosen account per store for next checkout), checkout -> thank-you screen with the delivery date.
- Insurance becomes a Phone app (existing coverage UI moved as is; rebuilt later).
## Stage 7 and 8 implementation notes (1 Nov 2026)
- Reports: daily = a chip beside the week bar; weekly, monthly and yearly = one sheet read with one tap before the next day runs; a year covers its month and week.
- Rewards: trophies, ambition milestones, finished first steps and the mission appear as a queued popup with the real reward.
- Inbox confirmation: only spends (subject to the player's size setting) and irreversible answers (sales, court settlements, ransoms, dismissals) ask once.
- Court judgments are a liability (payables "legal") paid from cash above wages owed; wages come first.
- Home: the profit and due cards were removed to fit the command centre; that information stays in the Bank app and in Top priorities when a shortfall exists.

## 1 Nov 2026 (night), owner reference images for the three new Phone apps
Reference images: `native/design/mockups/phone_apps/01_home_screens.png`, `02_checkout_flows.png`. Follow their styles, each app with its own colours.
- **Atlas Insurance** (blue): home with total coverage card, policy list, "all up to date", Get a quote; checkout (insured company with Change, period, coverage included, payment method, Confirm purchase); Insurance Activated (policy number, period, Go to My Insurance).
- **AirStay** (red): Offices / Shops / Retail search, recommended listings (price per month, type, rating), property info page with Rent button; instead of a delivery screen, a "Choose company" screen (which company rents it) then the in-game confirmation screen; Rent confirmed screen. Tabs Explore / Saved / Rented (active rents) / Messages / Profile as fits.
- **TechPro Store** (green): categories Software / Hardware / Tools / Office, popular products, add to cart, checkout (items, delivery method, totals), Pay securely, Order placed (order number, delivery date).
- Payment details screen (all apps): saved account, Autofill from Bank (real account name + number), remember me, Continue.
- The reference sheet is stretched to fit one picture: lay out to real iPhone proportions in our project.

## 1 Nov 2026 (night), owner reference pictures: photos, icons, buttons
Files: `native/design/mockups/photos/` (vehicles_a/b, premises_retail/offices/storage), `icons_moodboard.jpg`, `software_screens.jpg`, `button_popup_system.jpg`.
- **Photos**: premises listings (AirStay) use the retail, office and storage/warehouse pictures, small to large by size tier; vehicles pictures for fleet/cars in the Equipment store. Bundled as downsized assets only for what is used.
- **Icons**: flat, desaturated, outline-style icons on squircle bases for every Phone app (Bank, Accounting, Inbox, News, Weather, Stats, Goals, World, Luxury, Ventures, Rich list, Reports, Market, Reviews, Achievements, Settings, Airfly/AirStay, Techpro, Atlas, Support).
- **Buttons and popups**: one game-wide system from the Private Banking mood board (basic/secondary, important gold, expensive gold-foil with amount, popup cards with Cancel | Apply, alert banners), at current phone sizes, not wide, clean.
- `software_screens.jpg`: reference for what software looks like in the TechPro software category (old ERP vs modern CRM/analytics tiers).

## 1 Nov 2026 (night), popup system answers
- "Ask before spending" default for new players: step 2 (2,000 at reference level).
- Always ask even when small: loans, sponsor signings, equity rounds, holding moves, emergency board decisions (as built).
- Rent/Buy is a real choice popup, always shown.
- "Your time" is read-only; hours follow from role choices only.
