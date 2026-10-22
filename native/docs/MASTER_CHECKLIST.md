# Master checklist (single source of truth)

Status words: **DONE** (logic works and was quick-checked), **PARTIAL** (works, listed gaps), **NOT STARTED**, **BLOCKED** (waits on the user or an outside thing).
"Different names": things that exist in code under another name are counted DONE/PARTIAL, not missing (see `MISSING_ACTIONS.md` for the exact missing ids).

Stages, in order: **1 Finish mechanics → 2 Connect all features → 3 Redesign UI (one screen at a time) → 4 Final testing, bug fixing and realistic balancing.**
No deep tests, no balancing and no screen design before their stage.

## Stage 1 — Finish mechanics

| Group | Status | What is left |
|---|---|---|
| Core: RNG, calendar, currency, 23 countries, taxes, VAT, loans, banking, net worth, ledger, saves and web-save import | DONE | Verified against the original; 3 tax figures unsure (FI, LT, MX) → stage 4 |
| 50 service / venue / retail / production / logistics trades | DONE | Balance → stage 4 |
| Project trades (6), rental (3), finance (3) | DONE | Balance → stage 4. Reviews now shared system |
| Energy (2), salmon, holding company, football club | DONE | Holding: exchange listing and selling shares not ported (see Startups) |
| Reports: weekly, monthly, yearly | DONE | Year view also shows the personal income tax estimate for the year in progress (`GameEngine.yearInProgress`) |
| Managers, assistant managers, promotions, poaching | PARTIAL | Boards/CEO/MD/regional managers, profit bonus, manager proposals for equipment/vehicles/premises, promotion duties/authority/bonus/shares, assistant monthly suggestion and insurance, "no team from home" check, poaching after a course |
| Strategic decisions, trophies, awards, rich list, selling a company | PARTIAL | 13 decisions (s_acqoffer, g_location, g_franinq, e_merger, e_distress, t_ipo, t_pe, t_hostile, t_antitrust, t_activist, t_auction, c_JP_succ, c_US_vc); trophies that need missing systems; awards by revenue vs rivals; selling part of your shares; funding rounds |
| Equipment market, premises choice, luxury, estates | PARTIAL | Supplier discounts (vdisc), per-person equipment rules, fleet extras (mileage, fuel by van size, taxi class demand, work-car choice), premises extras (home workshop, franchise rent discount, landlord income, carallow), luxury perks/risk checks |
| Chains, franchises, branches, intercompany supply | PARTIAL | Rival supply, protection of supply-from-inside against outside supplier events. Done: board with seats/votes, price requests, group loans, 3-week opening wait, 25% own-bank cap |
| Customers and competition: reviews, key accounts, rivals, price wars, lawsuits, cyber, market map | DONE (engine, flat screens) | Analyst roles (mktan hired in a company, ana in the head office), rival price-fixing calls and fines, group poaching / supplier purchase / bids for your companies, ranking of the biggest companies (feeds awards), price-move forecasts, 6% manager price steps, manager picks IT level, tourist reviews, key accounts share a full shop with a trade profile, weight in the economy. Left: see KNOWN_GAPS (account supply links, vendor choice, national financial players in the ranking) |
| Misc actions: rename, close/reopen, wind up, convert to limited, 3 switches | DONE (engine) | No screen trigger yet → stage 3 |
| Startups, private equity, stakes in other groups, IPO/listing, crisis centre, 13 decisions above | NOT MERGED (WIP saved, branch `worktree-agent-ad8655a07a9bc6da6`, 43 actions) | Finish, build-check, merge |
| Boards, CEO, head office, meetings, academy, manager and chain gaps above | NOT MERGED (WIP saved, branch `worktree-agent-a63b07bec1d9760c6`, 65 actions) | Finish, build-check, merge |
| Advisers, abroad, company insurance, suppliers, gifts, complaints, staff profile, weather/world, fleet/luxury leftovers | NOT MERGED (WIP saved, branch `worktree-agent-a62df16577d42dde6`, 28 actions) | Finish, build-check, merge |
| Real-life population, income and demand by city (luxury in LA vs small town) | NOT MERGED (WIP saved, branch `worktree-agent-a6c6bbcca8ea1d325`) | Finish, build-check, merge; golden changes must be listed |
| 27 unowned actions: part-time/seasonal/hours staff types, discount campaigns, trial week, complaint handling, goals, development projects, lending a worker between chain stores | NOT STARTED | Assign to an agent |
| World around you: public image, contacts and favours network, maps screen; software products from your own startup | NOT STARTED | After Startups merges |
| 27 "other" actions: part-time/seasonal/hours staff types and pay model, discount campaigns, trial week, complaint handling, daily goal / first-step rewards / ambitions, development projects, lending a worker between chain stores, own-car allowance, give up premises, change accountant | DONE (engine + flat app rows) | Ambition perks are not yet applied to loan margin, abroad fees, quality and rival prices; ambition facts that need missing systems (market share rank, world rank) count as 0; pay plan chosen at hire for sellers; screens month30, paper40, wx56, pacct, registry and tabs demandLevel, route stay open; real screen design → stage 3 |
| Remaining trophies (need acquisitions, chains, startups, PE, luxury, R&D, listed holdings) | NOT STARTED | After the systems above |

Counts (original has 557 actions): 235 done and used by a screen, 17 engine only, 130 presentation-only (no gameplay), 175 not ported, all owned by the four unmerged branches above. Screens: 64 done, 38 not ported, 3 presentation. Company tabs: 24 done, 9 not ported, 10 presentation.

## Stage 2 — Connect all features (NOT STARTED)

- **De-duplicate systems ported twice by parallel agents** (keep one, delete the other, repoint callers): big meeting and co-owner buy-back (`ManagerStakes.swift` vs `Events/BigMeeting` + `Events/Shareholders`; dividend policy key `dp27` is now only set via `Shareholders.setPolicy`, its quarterly payout must be checked); promotion talk (`ManagerPeople` vs boards agent version); any second review/market/rival code paths.

- DONE: country codes moved out of code into data (lint `CountryNeutralityTests` passes): `Countries/Resources/country_traits.json` (hemisphere, data-protection law, storm names, manager titles, paper names, group words, franchise brand origins; read via `CountryTraits` / `Country.traits`) and `Events/Resources/country_events.json` (country news items and which country each hand-written country decision belongs to; `CountryEvents`). Keep new country-specific content in these files, never in Swift.

- Wiring audit: every engine action is reachable from the game (engine API or Inbox decision); every weekly/monthly model is called from the turn; no orphan code; new weekly random streams do not disturb the main stream.
- Save format: version migration for all new state (reports, rivals, reviews, chains, luxury, equipment, decisions queue); old saves still load.
- ~~Scale the remaining reference-level money amounts per country (bank/insurer capital, premium bases, developer land price, default rental price, rental loss bookings, caretaker wage)~~ DONE: scaled with `Currency.scaledPrice` / the wage level, removed from the `MoneyLiteralLintTests` allow-list; RentalFinance, Project and SpecialTrades differential tests still pass. Trade-catalog traits (`capital`, `premium`, `price`) are still written at the reference level.
- Engine text formatting (no "£220 k", no NBSP) at the source.
- Refresh `PARITY_CHECKLIST.md` and `MISSING_ACTIONS.md` after each merge; refresh STATUS/KNOWN_GAPS.
- Full CI compile of everything merged since the last passing app build (CI last saw commit e7dc1b0: engine tests passed, app build had 2 errors that are fixed in later commits, later merges unbuilt on CI).

## Stage 3 — Redesign UI, one screen at a time (NOT STARTED)

**UI grouping rules (binding for Stage 3; never invent a tab because the HTML game had one):**
- **Management = one Team / People surface.** Store manager, assistant, regional, chain, chief and department head are rows in one list with a role + scope badge (store | chain | region | group). No tab or root screen called Assistant, Regional, Chief or Managers-vs-Assistants. Hire, promote, fire and pay are sheets or rows on that list, not sibling tabs. Distinct engine role ids still show as one list.
- **Status (unbuilt, no Swift toolchain in the cloud session):** company section is now "Team"; `CompanyTeamRoster` lists MD, department heads and regional manager (role + scope badge, search/hire/authority/let go) under the manager and assistant cards. Still to do: fold manager/assistant cards into the same list; chain/group posts (`hireExecutive` etc.) have no UI yet; Group should link into Team with scope=chain.
- **Group = ownership and structure only** (chains, franchises, boards, stakes). A region chief or chain manager lives under Group, in that chain's people (or links into Team with scope=chain). No parallel "Regional managers" area.
- When unsure: people go under Team, structure goes under Group. No third place.

Current screens are **first versions**, functional only. Ivory Ledger style is chosen (`design/STYLE_IVORY_LEDGER.md`); other four styles are kept in `design/mockups` for later purchase.
- Designed and shipped in Ivory Ledger (first pass, to be reviewed): Home, Group, company overview, Bank, Money overview, Settings, Inbox, Start.
- First-version, undesigned: company sections (Projects, Properties, Book, Plant, Fish, Holding, Club, Chain, Franchise, Customers, Market, Equipment, Team/manager), Reports, Achievements, Rich list, Luxury, market/reviews/rivals, franchise brands, sale.
- Screens that do not exist yet (39 not ported + new ones for the unmerged systems).
- Each screen with more than one or two choices gets its own design pass with you.

## Stage 4 — Final testing, bug fixing, realistic balancing (NOT STARTED / BLOCKED)

- BLOCKED until you confirm: balance retune (capital-heavy trades were tuned before the rent fix; kiosk 51%, hardware 62%, grocery 40%, carrepair 44%, shipping 36%; new trades too profitable: salmon 86%, fund 197%, electrician 40%; finance trades lose money early; courier cash −9–15%).
- Full engine test suite (126+ tests; 1 known failure: kiosk return) and deep probes; compare the other 42 trades with the original; gym/restaurant realism flags.
- Demand realism check across all 23 countries once the population/demand branch is merged.
- iPad screenshot tour failure (deferred, iPhone first); iPhone screenshot review of all new screens.
- Tax: confirm FI, LT, MX figures.
- BLOCKED on you / Apple: app icon, bundle id, signing, installable build.
