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
## Popup, perks and stats implementation notes (1 Nov 2026)
- One in-game popup (`GamePopup`, `ConfirmPopup`, `ConfirmRule`): shown only for a spend at or above "Ask before spending" and for irreversible actions (`destructive`) or a commitment of unstated size (`alwaysAsk`); every other `PendingAction` runs at once. A spend must pass `amount` and `currency`. New players start at step 2 (2,000 at the reference level); step 0 still means "always ask a spend".
- Button system (owner mock-up): `PlainTextButtonStyle`, `ImportantButtonStyle` (gold fill), `FoilButtonStyle` (expensive, amount in label), `PopupFooter` (Cancel | Apply), `InlineMessage`, `AlertBanner`; compact phone sizes, no wide buttons.
- Perks: popup with a switch per perk for all workers; labour Rules moved into Stats under Legal and ownership; Statements row removed; Owed and Money matters titles removed; Your time read-only; each supplier in its own closed box, Sourcing box removed.
- iOS alerts removed too: the error alert and the chain rename use the same popup.

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

## 1 Nov 2026 (night), Stage 4 answers
- Careful company start holds back one month of rent and loan instalments before any hire.
- Startups: first support hire is part of the default founding team.
- Startups require the accountant and registration fee at founding like any limited company.
- A holder selling their stake: the player gets a right-of-first-refusal prompt to buy it first.
## 1 Nov 2026 (night), the three Phone apps built (AirStay, TechPro Store, Atlas Insurance)
- **AirStay** (red): Premises and Where you work are one app. Explore lists the places of every trade and city among your companies (offices, shops, retail and storage; monthly cost, kind of building, no invented ratings; photos from `AppPhotos` cut from the premises sheets), the information page has Rent (and Buy instead), then Choose company (any company with the same kind of place in the same city; its account pays; another company's Accounting can take the receipt), the in-game confirmation (only above the Ask-before-spending size, always for a purchase) and Rent confirmed with a reference. Rented holds the active rents; a lease can move to another company (the deposit and fit-out go with it; the first company is left without a place), and a home trade can work from home again. The old Where you work page and its move screen are gone; Operations rows open the app.
- **TechPro Store** (green): Equipment and Software are one shop (Software, Hardware, Tools, Vehicles, Office). The store front shows what that kind of business usually needs (missing first). Items go to a basket; checkout asks which store buys (the company whose account is charged), where the receipt goes, and the delivery: your own delivery company (an open logistics company of yours; free, a day quicker), else standard or express shipping paid by the store. Delivery days are the engine's: a lead time by kind and price (software at once, a vehicle longest), one day either way from a hashed roll, express half. The goods reach the company on the delivery day (`StoreOrders.runDay` in the daily step). Payment details: Autofill from Bank fills the company account's real holder and number (a stable number made from the seed and the company), a typed account must match it, "remember me" is kept per store on the device. Then Order placed with the order number and delivery date. The old buy screens are replaced by the store; "What this company owns" (units, service, selling, fleet, software) stays as the old Equipment screen and links to the store.
- **Atlas Insurance** (blue): the coverage screen moved as it was behind "Insurer, advisers and security". Home shows what cover costs a year, your policies (with the policy number the engine recorded when the policy went on), a banner and Get a quote; the checkout shows the company, period, what is covered, payment and receipt; Insurance activated shows the policy number and start date. There is no invented "total coverage" figure: the engine has premiums, not sums insured.
- Receipts (orders, leases, policies) are filed with the chosen company and show in its Accounting documents. Phone icons: flat desaturated outline on a squircle in a per-app tint.

## 2 Nov 2026, Phone apps answers
- Atlas home shows annual premium and policies in force (no invented sum insured).
- Own delivery company books a delivery fee as revenue; the buying company pays it (built: 70% of the standard fee, none when the buyer is the carrier itself).
- AirStay: a company can take a listing of its own kind of place in the same city.
- Insurance stays "from today until switched off"; lease-finance loan uses the delivery-day price.

## 2 Nov 2026, owner test feedback on 1.0.11 (all to be fixed)
Navigation: swipe back steps back to the previous screen/menu inside the new apps too (not leave the app).
Manage cleanup: "What the company owns" moves INSIDE TechPro (equipment and fleet removed from Manage); Insurance and advisers and Premises tabs removed from Manage (Atlas / AirStay own them).
Your time: removed. Hours adjust automatically from how much help each business needs; in Management a small box next to the player's name says whether the player works here. Running alone: work as much as demand needs, capped at 80 h (as now), burnout from 65 h.
Notifications: the banner/toast at the top is removed everywhere (looks dated). Important info becomes a popup. A decision with immediate effect notifies at once (popup).
Top priorities decisions on Home resolve as a popup on the main screen (not by opening Inbox). Inbox uses game colours, not green; deciding inside Inbox also uses popups, not a bottom banner.
Reports: weekly, monthly, yearly reports are clean popups (no bottom banner). Every day also shows a short daily popup (what went well, sales count, important staff messages).
Goals/rewards: resolve in place with a "Claim reward" button and a rewarding reaction (animation, haptic), not "go to Goals to collect".
Atlas: policies can be removed (cancelled); never linked to a company tab.
TechPro: show ALL items; website-like with sort by price up/down; discounts follow real-life logic: biggest discounts sometimes, small discounts regularly, Black Friday nearly everything heavily discounted (game calendar).
AirStay: each listing keeps its own picture locked to the location (no same picture for all small offices), realistic-sounding location names.
Layout bug: some screens move loosely side to side and up and down when content fits the screen; they must not scroll/bounce when not scrollable.

- (2 Nov) Owner hours may go under 40: they follow demand in 5 h steps (floor 5). Subscriptions get no sales, only a standing 8% volume discount on the biggest plan; used items never carry a sale.
- (2 Nov) TechPro lists EVERY item in the game (all trades), buyable by any company. Owned items are rebuilt inside TechPro as a "My items" shelf (condition, warranty, sell/replace), replacing the old Equipment screen.
- (2 Nov) Typed prices: single-product trades type a price per unit/hour (kept inside the market range by the engine); shops (retail family) set one markup percent on all items. Suppliers in Accounting and chain/franchise applications in Documents already exist.
