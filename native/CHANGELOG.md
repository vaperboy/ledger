# Changelog

## Unreleased — native migration (branch `native-swiftui`)

### Stage 1: navigation and the Company hub (31 Oct 2026)
* One navigation owner: `GameStore` holds the route stack of every tab and one pending request for the app a link opened (replaces seven loose request slots). Choosing the open tab again returns it to its root; a link to a record already on the stack goes back to it instead of stacking a copy; Back from a screen a cross-tab link pushed returns to the tab the link came from and leaves nothing behind; a pushed screen has exactly one Back control.
* Company is a hub of six rows (Overview, People, Operations, Sales & Market, Stats & Information, Projects); each is a pushed screen. Price, How you sell and Marketing moved from Operations to Sales & Market; Plant, Fish, Club, Chain, Book and Holding are reachable from the section they belong to. Company Projects exists for every company. Overview is cash-first with three parts (Overview, Performance, Insights).
* `SectionTabs` no longer scrolls sideways: a fixed row, or the first three plus a More menu when titles do not fit.
* Nothing was removed; save files are not touched.

### New look foundation (27 Oct 2026)
* Shared pieces for the approved new look in `Design/NewLook.swift` (icons from the mockups' SVG paths, `AppHeader` with a round back button, `StatStrip`, `ActionTile`, `ChoiceCard`, `SegmentedPill`, sharp table, `QuietButton`, `SmallOutlineButton`, `RedBubble`, floating `PillTabBar`) and a bordered `Card`; Theme colours and radii set to the mockups.
* Tabs are Home / Team / Group / Projects / Phone. The Phone tab is an app grid (`PhoneHome`) with red bubbles and a banner for the top alert; Inbox, Bank, News, Stats, Goals, World, Luxury, Ventures, Rich list, Reports, Achievements and Settings open from it. The More sheet is removed.

### Added
* Contract discussion (`ContractTalk.swift`, `ContractDiscussionView`): one surface per employee for pay rise, promotion, hours, pay basis, bonus plan, benefits, notice and moving, opened by you or by their request. Cost, quit risk, effect on others and the country's labour rules are shown before you confirm. Nobody refuses a pay rise; declining or delaying a fair request has shown consequences. Commission-only has no base pay at all. The old raise, promote and contract buttons are gone.
* Negotiation (`Negotiation.swift`, data `negotiation.json`): every hire (worker, manager, assistant, department head, chain and group executive, head office, data analyst) opens at the going rate with the person's ask hidden, and the person answers with a counter, a refusal or, when patience is gone, takes another job; higher posts are more patient; some counters are unrealistic. Pay-raise requests, the sale of a company and the purchase of a rival use the same module. Automatic hiring (`AutoHire.swift`) bargains from low, weighs several candidates and reads real skill; the better the manager, the cheaper and better the hire.
* Country labour rules (data: `labour` in `country_traits.json`, `LabourRules`): minimum wage (offers and raises are lifted to it, pay follows it with inflation), standard week with overtime premium and tiredness, notice and severance by years of service for dismissals, layoffs and managers (one helper), probation and at-will rules, and a read-only Labour rules card in Company > Team.
* Management and people: general managers (executive search, interviews, references, hire, what they may decide, pay review, proposals and yearly raise in the Inbox, resignation with notice, rival offers, move, replace, ask for changes, meetings), assistant managers with two jobs, promotions with a pay talk, and the best worker as the target of a poaching offer. Company > Team has the manager card, hiring and the promotion sheet.
* Rental and finance trades: residential rentals, commercial property, parking and self-storage (`RentalModel`), insurance company, bank and investment fund (`FinanceModel`), with Properties and Book sections in the company screen; compared with the original on a saved game.
* `native/Engine`: the game engine in Swift — seeded randomness identical to the original's, calendar, 23 countries as data, taxes,
  currency and exchange rates, 67 trade definitions as data, demand / capacity / price models, daily retail trade, payroll on real
  dates, VAT, month and year end, loans and credit, personal tax and net worth, marketing and awareness, hiring and staff dynamics,
  133 random events with answers, stocks / crypto / funds / savings / deposits, bankruptcy and game over.
* Saves: native envelope with versioning and migrations, atomic writes, previous-save fallback, rolling backups, import of the HTML game's
  JSON / LZ1 / LZ64 saves with the original text kept.
* Player actions as single functions (`PlayerActions`), read models for screens, home suggestions and first steps, daily history for
  charts, consequence previews for event options, text tokens per country.
* `native/App`: SwiftUI app — design system, Home (net worth, change indicators, quick actions, summaries with real histories, first
  steps, Next day), Companies (overview, team, money, operations, marketing, setup), Group, Phone (new company with full cost, bank, invest,
  tax, news, stats, activity, settings), Inbox with decisions, start screen with import, iPad sidebar layout, haptics.
* Tests: 45, including exact comparisons with numbers produced by the original game.
* `tools/ref`, `tools/gen_parity.py`, CI workflow `native-ios.yml`, documentation.

### Premium upgrade (this round)
* Finance & taxes screen (Overview / Taxes / Expenses / Reports): upcoming payments with a covered/short check, taxes owed, cost breakdown
  as a chart, country rule card labelled "Estimate" (`dataBasis` in country data), per company or for the whole empire.
* Company dashboard: value, 12-month revenue and profit, growth, cash, debt, team, health label, revenue / profit / cash charts, operation rings
  (capacity used, demand met, rating), plain-language insights worked out from the company's own numbers.
* Owner policies (Settings, "How much I decide"): routine payroll approved automatically when the company can pay, cash reserve before
  marketing, automatic dividends. Big decisions still come to the inbox.
* Marketing is prepaid and pauses instead of running a company into debt; a limited company is never valued below zero.
* Inbox tabs (All / Decisions / Risks / Updates), compact rows for routine news; Home "Coming up" card.

### Balance and realism (balance probe, see docs/BALANCE_REPORT.md)
* Every supported trade played for three years in three scenarios; no trade makes you rich quickly; investments return market-like rates.
* Fixed: vehicle trades could never open (vans financed or leased now); hired teams had zero capacity when a support role was empty;
  people who quit were never replaced; complaints went unanswered without a manager; automated hiring overpaid; owner-run companies
  were valued as if the owner's own work were profit; everyday shops were as unknown as niche boutiques.
* New owner policies: replace people who leave, staff answer routine complaints (Settings, both on by default).
* Net worth chart with 1W / 1M / 3M / 1Y / All, scaled to the period; weekly history kept for the long view.

### Design (concept colours, Liquid Glass)
* Colours sampled from the design concept; title-case card headings; icon rows; pill tabs; Liquid Glass on floating controls and the
  hero box of each screen (real `glassEffect` when built with the iOS 26 SDK, drawn glass before); every screen moved to the new style.

### Fixed while comparing with the original
* Awareness, reputation, fines, hype, idle closure, `{eq}` placeholders, equipment breakdowns (see `docs/BALANCE_PARITY.md`).

### Known
* See `docs/KNOWN_GAPS.md`. The app has not been run by its author; 17 of 67 trades and most of the original's screens and actions are not ported.
