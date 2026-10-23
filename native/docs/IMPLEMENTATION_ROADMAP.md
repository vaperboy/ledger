# Implementation roadmap (master tracker)

The one place that says what is still to do and why. It does not replace the inventories: `SCREEN_MIGRATION_INVENTORY.md` (screens),
`docs/data/action_status.json` (all 557 original actions), `MASTER_CHECKLIST.md` (status log), `TAX_SOURCES.md` (rule data),
`BALANCE_REPORT.md` (balance), `DESIGN_RULES.md` (design rules). This file points at them; it does not copy them.

Updated: 23 Oct 2026, at commit 1da0ac8 (native-swiftui). Source of every item: the engine/screen audits of this session, the agent
reports, and the "missing" list of 23 Oct. Items marked UNVERIFIED were not re-checked after the UI pass.

**Classes**
- **KEEP**: build it as the original/owner intends.
- **ADAPT**: build it, but differently from the original (reason given).
- **REMOVE**: delete or merge; it is dead or a duplicate.
- **DEFER**: not now; waits for a decision, data or another item.
- **ALREADY DONE**: was on an earlier missing list and is now built and checked (how it was checked is stated).

**Stages** (from the owner's plan): 0 trackers · 1 remove duplication, settle architecture · later stages are proposed here and wait for the owner's go-ahead.

## A. Duplication and architecture (Stage 1)
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| A1 | Dismissal: `Hiring.fire` and `StaffProfile.dismiss` (warnings, unfair-dismissal rules) are two paths | ADAPT | One source of truth: dismissal rules (warning, notice, severance by `LabourRules`, unfair-dismissal claim) live in one engine function; every caller (staff profile, layoffs, manager fire, roster let-go) uses it. | none |
| A2 | Severance booking copied in `Hiring` and `ManagerPeople` | REMOVE | Same rule twice; `World.terminationPayments` already computes notice/severance/fine, so only the booking should be shared. | A1 |
| A3 | `Satisfaction.answerComplaint` is a dead copy of `Complaints.answer` | REMOVE | Verified dead in the audit; delete after a grep for callers. | none |
| A4 | Lunch/meeting rule exists in four copies | ADAPT | One helper for "meet a counterpart" (cost, mood, cooldown); callers pass the kind. Tests must pin the current numbers first so the merge changes nothing. | none |
| A5 | Executive-search fee (15000 scaled) defined in three places | REMOVE | One constant/function (`ManagerModel.searchFee`). | none |
| A6 | Candidate hiring: two engine `hire` overloads (PlayerActions.swift, MiscActions.swift) both used; UI copies remain in "Find workers", `CandidateSheet`, `FundManagerCard` | ADAPT | Worker hire (terms: part-time, seasonal, trial week) keeps its own sheet but must call one engine `hire`; the fund-manager flow differs (not a `Person`) and stays. | A1 |
| A7 | Confirm all UI branches merged without duplicate screens | ALREADY DONE | Checked 23 Oct: every `ui/*`, `fin-engine` and `worktree-agent-*` branch has 0 commits ahead of native-swiftui; CI green on the merged branch (run 40001739437) and on final-audit (run 40006199007). Temporary branches `ui/company-s1`, `ui/company-s2` are duplicates and can be deleted. | none |
| A8 | Dead views: `MoneyView`, `GroupSummary`, `HireOptionsMenu`, `CompanyFranchise`, `Ring`, `MiniBars`, `ScreenHeader`, `AmbientLight` | REMOVE | Unused per grep; delete only with a green macOS build after each removal. | A6 |
| A9 | Engine month/year-end runs after chains, ventures, rivals (original: right after the company loop) | DEFER | Effect unverified; needs a differential test against the original before changing. | none |

## B. Original features not ported
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| B1 | Trade unlocks (all 67 trades open from day one) | KEEP | Original progression; gives a starting path. Needs the life stories to decide what is open at the start. | B2 |
| B2 | Life stories: heir, laid off, student, kid (1 of 5 exists) | KEEP | Start-of-game choice with different cash/trades/age. | none |
| B3 | Prime-time TV channels (23 of 34 marketing channels) | ADAPT | One per country; keep the original's cost/reach but use `country_traits` data rather than 23 hard-coded ids. | none |
| B4 | Campaign planner: length and age-group targeting | KEEP | Marketing must be "odds, not guarantees"; needs the targeting inputs. | B3 |
| B5 | How-you-sell changeover: cost, capacity penalty, multi-select, document check | KEEP | Today a field write; the change must cost something. | none |
| B6 | Deal of the week | KEEP | Small original feature, low risk. | none |
| B7 | Manager focus plans (`setfocus`) | KEEP | Delegation depth. | none |
| B8 | Change pay day (`pr29day`) | KEEP | Interacts with payroll and cash-flow timing. | none |
| B9 | Confirm-before-spend setting (`setconf`) | ADAPT | The app already confirms consequential actions; make it a global threshold setting rather than the original's toggle. | none |
| B10 | Web analytics (`gaon`/`gaoff`) | REMOVE | Original-only telemetry toggle; no gameplay. | none |
| B11 | Tender trades `cons`, `farm` | DEFER | Original gives farm no demand; `cons` needs a decision on whether construction uses the project order book. | none |
| B12 | Ledger Pro store and skins (11 ids) | DEFER | Commercial layer; owner's decision. | Apple account |
| B13 | Crisis centre, org chart, payroll and bills page, personal rival screen, business paper screen | UNVERIFIED | Listed missing in the screen inventory; the UI pass added bills/payroll report, paper and weather pages. Re-check each before building. | none |

## C. Engine works, screen missing or thin
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| C1 | Payroll mode and payroll run | KEEP | Belongs in Company > Finances; engine exists. | none |
| C2 | Insurance toggles and advisers | KEEP | Belongs in Company; engine exists. | none |
| C3 | Giving back / foundation | KEEP | Group or personal; engine exists. | none |
| C4 | Work-from-home flow | KEEP | Company Operations; engine exists. | none |
| C5 | Rival group profile (`grp27`) | KEEP | Market screen. | none |
| C6 | `setReports`, `toggleOfficeAssignment` (head office) | DEFER | Value meaning unclear; read the engine first. | none |
| C7 | New-company: brand/franchise step, premises picker | KEEP | Part of "create a company" flow. | none |
| C8 | Project milestone views (`CompanyProjects`) | KEEP | Projects tab promise: time-bound work with milestones. | none |
| C9 | Settings, Stats, Achievements, Rich list, Activity not reworked | DEFER | Work today; revisit after the hands-on tests. | H-tests |
| C10 | Properties: renovate cost preview | DEFER | Engine exposes no quote. | engine |
| C11 | Company, loan, finance, ownership, abroad, software, boards, head office screens | ALREADY DONE | Built in the UI pass; checked by macOS build and screenshots only, NOT by hand: see HANDS_ON_TEST_PLAN. | H-tests |

## D. UI and navigation
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| D1 | Back from Projects/Inbox/Home company link returns to Company list | ADAPT | Push the company onto the originating tab's stack instead of switching tab. | none |
| D2 | Energy/club/finance-book/properties: summary-first layout, empty and locked states | KEEP | Design rules. | none |
| D3 | Group "Stand alone" lists companies; franchise applicants reachable from Group | KEEP | Group should not bounce to Company. | none |
| D4 | iPad tab switch loses each tab's scroll/sub-navigation | DEFER | Trade-off accepted to fix the toolbar leak; revisit if testing shows it hurts. | H-tests |
| D5 | Cosmetics: "Money" title in Group; Team sidebar icon offset | KEEP | Small. | none |
| D6 | Engine-written text "£11 k" | ADAPT | Tidy at display (message text), not in `Currency.short` (pinned by golden tests). | none |
| D7 | Money overview "Cash available" vs Home "Cash" | ADAPT | Relabel to say what it includes. | none |
| D8 | Deep links and every new screen tried on a device | KEEP | Only code-read/compiled/screenshotted so far: this is the hands-on plan. | HANDS_ON_TEST_PLAN |

## E. Rules and data to verify
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| E1 | Mexico: UMA value 117.31/day, IMSS component rates | KEEP | Came from an agent, not the owner's list; verify. | owner |
| E2 | Unverified tax: MX corporate/IVA/dividend, LT VAT 21%, FI dividend/contribution | KEEP | Logged in TAX_SOURCES.md. | sources |
| E3 | Unverified 2026 minimum wages (MX, KR, BR, FR, DE, UK, IE, US) and several notice/severance statutes | KEEP | Logged in TAX_SOURCES.md. | sources |
| E4 | FX on repatriating foreign profit | REMOVE | The original has no such mechanic; cash is held in accounting units. | none |
| E5 | Overtime paid to hourly staff only; hours/notice per country not traced for all 23 | DEFER | Check after the dismissal merge (A1). | A1 |

## F. Economy and balance (owner: not yet)
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| F1 | Car dealer structural loss (about −14% mean over 18 seeds) | DEFER | Owner said no balancing yet; analysis exists (BALANCE_REPORT). | owner go |
| F2 | High seed variance (grocery, hardware, courier, 3PL, car repair) | DEFER | Bound single-event losses as the farm fix did. | owner go |
| F3 | Balance guard checks only 2 seeds | DEFER | Use 5+ seeds and the median. | F1 |
| F4 | Kiosk returns may be too easy; airline ~4% with large first-year loss | DEFER | Review with F1. | F1 |
| F5 | Rival-run energy firms, oil/salmon fairs, club investors | REMOVE | Do not exist in the original; nothing to port. | none |
| F6 | Tender draws change the shared random stream | DEFER | Re-check golden baselines when balancing. | F1 |

## G. Process and tooling
| ID | Item | Class | Rationale | Depends on |
|---|---|---|---|---|
| G1 | `tools/parity_map.py` / `gen_parity.py` stale | REMOVE | `docs/data/action_status.json` is the current record; delete or regenerate from it. | none |
| G2 | `SCREEN_MIGRATION_INVENTORY.md` counts predate the UI pass | ADAPT | Update status columns only (no second inventory). | H-tests |
| G3 | Screenshot tour covers few screens | KEEP | Extend the UI tour to staff profile, loans, acquisition, ventures, boards. | none |
| G4 | Apple release: icon, bundle id, signing, installable build | DEFER | Needs the owner's Apple account. | owner |
| G5 | CI fixed: engine tests as release on macos-15, app-build parallel | ALREADY DONE | Run 40001739437 green (engine, app, 3 screenshot tours). | none |
