# Design rules for screen work (binding for every design agent)

Owner's rules, collected in one place. Each agent works on ONE category only and reads this file first.

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
