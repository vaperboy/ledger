# Design rules for screen work (binding for every design agent)

**Owner rule, 27 Oct 2026 (amends the two apps rule above): Bank and Inbox are outside apps too.** Inbox is a messages app like SMS (its own look: message threads, bubbles, its own palette). Bank is a bank's app made by someone else (its own muted palette and look) UNLESS the player owns a bank and uses it as their main bank: then the Bank app follows the game's own colours and style. Only the apps that are truly the player's own (Stats, Goals, Achievements, Activity, Reports, Settings, and Bank when the player's own bank is the main bank) follow the game's style.


**Owner rule, 27 Oct 2026: outside apps are "fake apps by other creators".** Only the player's own (insider) apps follow the game's colours and style. Outside apps (Weather, News, Luxury, Ventures, World, Rich list) use their own muted palette that fits what they are (Weather blue, News newsprint and ink, Luxury black and brass, and so on): never loud, but not the champagne-on-charcoal of the game. Their launch screens use the same palette. The back button stays the same so the player can always leave.


**Owner rule, 27 Oct 2026: two kinds of phone apps.** Apps about the outside world (News, Luxury, Ventures, World, Rich list, Weather) have their own interfaces and imitate real apps of that kind. Personal apps (Bank, Inbox, Stats, Goals, Achievements, Activity, Reports, Settings) follow the game's own design and layout (bordered cards, icon circles, tables) but each still has a distinct look that suits its job.


**Owner rule, 27 Oct 2026: one screen at a time, never generic.** Every page is designed on its own: its own layout, its own menus or tabs where they make sense, its own graphs and icons, all strictly inside these rules and the approved new-look mockups. Do not build a page by swapping the same section helper into an old screen, and do not bundle screens into one look-alike template. A screen's structure follows its content (a chart or figure strip where numbers matter, a table where things are compared, a timeline where dates matter).


## REVISION 27 Oct 2026 (owner, NEW LOOK) - supersedes the 26 Oct revision and any older line where they conflict
Reference mockups with exact colours, radii, spacing and icons: `native/design/new-look-2026-10/` (open the `.dc.html` files; README there). Build screens from the shared pieces in `App/Ledger/Design/NewLook.swift` and `Components.swift`, never with ad-hoc boxes or SF Symbols for house icons.
- **Cards and icons are the house style.** Content sits in bordered `Card`s (#151617 surface, #2B2C2E border, radius 16 for big summary boxes, 14 standard, 12 compact rows, 8 for sharp tables and fields). Icons are the mockups' outline icons (`Glyph`, drawn by `GlyphView` / `IconCircle` / `AppIconTile`), champagne on the dark surface. The "no unnecessary cards" line of the 26 Oct revision is withdrawn; still no decorative card that holds nothing.
- **Back button is round** (`RoundBackButton`, 40 pt, grey outline) on every screen outside Home, and every such screen has its own `AppHeader` (serif title, grey subtitle). Pushed screens get both through `.appScreen(title:subtitle:)`.
- **Title and "Hello, name" appear only on Home** (`HomeHeader`). Other tabs' roots use an `AppHeader` without the app name or greeting.
- **Only Next Day is a filled button.** Everything else is an outline: `QuietButton` (champagne outline, 8 pt), `SmallOutlineButton` ("New company": small grey outline, replaces the plus), `ChoiceCard` / `SegmentedPill` for selection. `GoldButtonStyle` is reserved for Next Day.
- **Tabs:** Home (route name `.company`), Team, Group, Projects, Phone (`.phone`), in a floating pill tab bar (`PillTabBar`) with the selected tab in a champagne pill and red bubbles. **Inbox is an app inside Phone, not a tab.** The Phone tab bubble is the total waiting count (open decisions + payroll alerts). Everything that used to be in More is an app on the Phone grid.
- **Red bubbles** (`RedBubble`) carry counts only (Inbox decisions; the Bank app and a company's account row when no manager or accountant approves payroll).
- Money stays through the store/currency formatters; tables (`SharpTable`) take already formatted strings.

## REVISION 26 Oct 2026 (owner) - superseded where it conflicts with the 27 Oct new look above; design/STYLE_IVORY_LEDGER.md likewise

### 1. Visual identity
- Ivory Ledger: dark page, flat sections, hairline dividers, restrained champagne accents, serif titles and hero figures, small champagne section labels, tabular numerals.
- Flat is the default. NO UNNECESSARY cards or boxes: a compact card or bordered container is allowed for genuinely independent entities, financial summaries, warnings or complex comparisons when it improves scanning. Never a decorative card to fill space.
- Colour carries meaning (green gain, red loss, amber warning, champagne primary action) and never alone: pair with a sign, icon or word.
- Next Day is the only persistent primary navigation/game-advance control with the filled champagne treatment. Selected, destructive, disabled and urgent states get their own distinct treatments. Do not make every button equally important.
- Clear contrast, legible text, sensible tap targets, iPhone and iPad layouts. Same design system, not identical screens: a balance sheet, employee profile, franchise agreement and inbox have different needs.

### 2. Where things live
- Company: one company's operations, finances, performance and company-local workforce. Company-local staff and operations are distinct from group-level executives, shared services and chain/franchise oversight.
- Team: the people and management hierarchy the player is responsible for (roles, delegation, authority, scope). It must not dump every employee into the management overview, but ordinary workers and profiles stay reachable where the user needs to manage them.
- Group: ownership and structure: holdings, chains, franchises, boards, stakes, genuine group finances and services.
- Projects, Inbox, Money keep their own destinations. Never a tab named Assistant, Regional, Chief or similar. Do not invent destinations or duplicate systems to expose a feature.
- One underlying person record; role, employer and scope shown accurately; views filter to the relevant people by default; never duplicate records.
- Default, not absolute: people decisions under Team, local operations under Company, structure under Group. Resolve edge cases by the scope of the task and the entity managed (a store manager's day-to-day staffing sits under that store; hiring a group executive or changing chain-wide authority sits under Team or Group by scope).
- Business scope: company actions affect one company; chain actions only that chain; franchise rules follow the agreement; group actions only the entities they govern. Do not assume separate chains share employees, policies, suppliers or marketing without an explicit arrangement. Several entry points to one action must use the same engine action and the same validation and consequences.

### 3. Navigation
- No side-scrolling menus. Company overview: Overview, Team, Finances, Operations, secondary under More. Adapt spacing/layout to device size instead of squeezing a row.
- Keep navigation history, tab state and scroll position where practical; clear ways back; returning from a task never lands on an unrelated default.

### 4. Screen quality and interaction
- Most decision-relevant first: cash and liquidity, performance, material risks, overdue obligations, decisions needed. Do not turn screens into dashboards of equally loud numbers. Secondary data compact; headings selective.
- Interactive rows are distinguishable (chevron/button style/accent), whole intended tap target works, accessible labels and states.
- Confirmation depends on risk and reversibility: required for material spending, borrowing, firing, closing a business, ownership changes and irreversible actions; NOT for routine reversible tasks. Always show relevant cost, consequence and risk before the user commits.
- Every action handles success, refusal and failure honestly (show success only after success, explain refusals). Plain navigation needs no toast.
- Empty/locked/unavailable states are real, explain why and what unlocks them; never fabricate balances, staff, opportunities or results.
- Money: always the central currency/number formatters, in the currency of the relevant company, account, country or transaction (not always the home currency); never build money strings or hardcode symbols.
- Support accessibility settings and text scaling; layouts must survive long figures and companies with many staff and locations.

### 5. Gameplay and architecture
- Game rules, validation, calculations and financial effects live in the engine, never in views. Views render state and send existing actions.
- A visual redesign must not silently change mechanics, saves, engine actions or calculations.
- Business type decides which operating systems apply; chain, franchise and group add only their own rules.

### 6. Economics
- No arbitrary growth floors/caps, no guaranteed profit from upgrades or sales methods; outcomes emerge from decisions, management, demand, competition, costs, capital and modelled constraints. Every operating choice has realistic costs, requirements, trade-offs and uncertainty and may be unsuitable. No hidden rubber-banding; fix the economic error instead of masking it. Test strong and weak outcomes across businesses and seeds; unusual results are signals to investigate.

### 7. Implementation
- Inspect before declaring missing/broken; integrate into the existing system; no duplicate implementations or needless wrappers; focused changes; no overlapping agents on the same files; preserve saves and uncommitted work; report real changes, verified tests, remaining issues and untested areas.

---
(Older rules follow; where they conflict with the revision above, the revision wins.)


Owner's rules, collected in one place. Engine behaviour, balance and sales methods are also bound by `SIMULATION_RULES.md`. Each agent works on ONE category only and reads this file first.

## Where things live (one primary home per feature)
- **Company** (tab): the company list (with comparisons) and one company's operations: overview, store operations, its finances, its own staff.
- **Company > Team**: employees of that company only: wages, hiring, promotion, contracts, performance, dismissal. Its manager, assistant and the management roles of that company.
- **Team** (tab): management hierarchy, delegated responsibility, vacancies, exceptions and decisions that need the owner. Not a roster of every worker in every store; a search across all employees is optional and opens the owning company.
- **Group** (tab): chains, franchises, holdings, head office, group executives, boards, regional management, shared policies, and group money (bank, investments, taxes, costs, reports) in one place.
- **Projects** (tab): time-bound projects, milestones, expansion work, ventures.
- **Inbox** (tab): messages, offers, warnings, approvals and decisions; each links to the record it concerns.
- Never a tab or root screen named Assistant, Regional, Chief or Managers-vs-Assistants. Distinct engine role ids still show as one list with a role + scope badge (store | chain | region | group). When unsure: people under Team, structure under Group, no third place.
- Multiple entry points are fine only if they open the same record and call the same engine action. Never duplicate hiring, firing, appointments, chain management or money transactions.

## Responsibility and scale
- Design around the player's responsibilities, not the data type. With 10+ stores, show managers, delegated authority, performance, exceptions, vacancies and decisions, not every employee.
- Delegation comes from the engine (`decisionChain`, manager authority levels, `teamOverview()`); do not invent mechanics in views.
- Company-level screens show company-level data; group-level screens show group-level data.
- Screens must respond to the number of companies, staff, projects and other entities (search, filters, grouping, summaries).

## Reuse versus unique
- Shared templates for genuinely similar screens: company overviews, financial summaries, staff lists, market listings, candidate hiring, confirmations (`PendingAction` + `.confirmAction`), `LedgerSection`, `FlatRow`, `KeyFigures`, `SectionTabs`.
- Own layouts where the workflow differs: acquisitions, board decisions, franchise management, financing, major projects.
- Inspect shared components and their callers before changing them.

## Usability and realism
- Most important decisions and figures first; no unnecessary tabs, oversized lists, redundant metrics or extra navigation levels.
- Actions in context, with cost, benefit, risk and timing shown before confirming; confirmation for consequential decisions; every action reports the engine's result (no silent buttons, no success message that ignores a refusal).
- Real empty, loading, error, locked and unavailable states. Never fake functionality or placeholder data shown as real.
- Navigation is contextual: show the current company, store, chain or group; deep links open the exact record and section (`GameStore.openCompany(id, section:)`, `CompanyRoute.companyAt`); Back works; no state leaks between companies.

## Safeguards and verification
- Preserve gameplay mechanics, calculations, save compatibility and working features. No game rules in views.
- Small, testable stages. Engine: `cd native/Engine && swift test --filter ...` (Swift 6.0.3 at /opt/swift). App: only builds on macOS CI (`.github/workflows/native-ios.yml`, jobs app-build and screenshots; screenshots are published to branches `ui-shots-*`).
- Before finishing, check navigation, buttons, data updates and cross-screen links together. Report what changed, what was tested, and what remains; never claim success for anything not verified.

## Scanning and tap cues (owner's rules, 25 Oct 2026)
- **Dense screens must be easy to scan.** The game carries far more information than a normal finance app. Small uppercase section headings and thin dividers look refined, but too many of them make a long screen tiring. Give critical figures, warnings and decisions a stronger hierarchy (size, weight, colour, position); keep secondary data compact; do not give every group its own heading and divider.
- **Interactive rows are unmistakable.** Minimal is fine, but the player must always know what can be tapped. A row that opens a company, hires a manager, changes a policy or reveals a report needs a clear cue (chevron, button style or accent), distinct from plain information rows. Important actions show their cost, consequences and the confirmation before committing (see Usability above).
