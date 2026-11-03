# Missions and awards audit

Cause of "seven awards right after the first company": every popup comes from one queue (`Celebrations`, `rest["cele"]`). Before the rework, setup alone queued: first steps "Start a business", "Hire your first worker", "Open the doors" (3 popups, each with a cash or reputation reward on claim), trophies "First customer" and "First employee" (2), the daily goal "Open your first business" or "Hire someone" (1), and a net-worth milestone when the player funded the company (1). All fired in the first game week.

Rewards are unchanged per tier (first-step rewards, daily reward, legacy points, trophies carry no cash).

## Sources

| Source | Code | Reward | Popup before | Popup now |
|---|---|---|---|---|
| First steps (10) | `PlayerGoals.stepList` | small cash/credit/awareness, claimed in Goals | all 10 | only `profit`, and `mgr` once a manager runs a company that made money 3 months running |
| Daily goal (5) | `PlayerGoals.dailyIDs` | cash, grows with streak | all | only `cmp`, `grow`; `start` and `hire` no longer offered; `weeks` silent |
| Net-worth milestones | `Milestones` | none (popup) | yes | unchanged (separate ladder; needs real wealth) |
| Profitable-week streak 4/8/13/26/52 | `Milestones` | none | yes | unchanged (4 weeks minimum) |
| Ambition milestones/tiers | `Ambitions.check` | legacy points | yes | unchanged (need a chosen path and results) |
| Trophies | `Trophies.all`, `TrophiesMore` | none (brand value points) | yes | see below |

## First steps

| id | Triggers when | First fire | Trivial? | Now |
|---|---|---|---|---|
| co | a company exists | day 0 | yes | silent (still claimable) |
| staff | any employee | day 0 | yes | silent |
| open | a company is open | first days | yes | silent |
| week | a week report exists | day 7 | yes | silent |
| sell | price level or knob changed | day 0 | yes | silent |
| ad | any ad budget | day 0 | yes | silent |
| inbox | answered a decision | first days | yes | silent |
| pay | owner salary or dividend set | day 0 | yes | silent |
| profit | a profitable month | first month end | no | announced |
| mgr | manager or assistant | day 0 | yes | announced only after a quarter of profit with a manager |

## Daily goals

| id | Trigger | Now |
|---|---|---|
| start | a business is open (offered only with none) | removed from offers (trivial) |
| hire | staff count rose | removed from offers (trivial) |
| weeks | two weeks played | offered, no popup (passive) |
| cmp | open complaints answered | announced |
| grow | net worth +1% | announced |

An old save with `start` or `hire` already picked keeps it, claimable, without a popup.

## Trophies changed (ids kept, so earned ones stay earned)

| id | Was | Now |
|---|---|---|
| cust | first customer served | 10+ sales a week, at least 4 weeks after opening |
| emp | first employee | a company with staff that has a profitable month |
| mgr | first manager | manager runs a company with 3 profitable months in a row |
| branch | second company of one trade | second company of one trade, both with a profitable month |
| year | one year since first company | one year, and a company open with a profitable month |
| ten | 10 jobs | 10 jobs and a profitable month |

## Trophies added

| id | Trigger |
|---|---|
| q3 | any company with 3 profitable months in a row |
| debt0 | had a loan (`rest["ach28d"]` marker), none now, and a profitable month |
| bv25, bv50, bv75 | group brand value reaches 25, 50, 75 and a quarter profitable |

All other trophies (net worth, dividends, tax, portfolio, jobs 25+, managers, company counts, trades, countries, years 5+, awards, listed, founder, exit, PE, luxury, chains, franchises, ranks, markets) need money, time or scale and were left as they are.

## Counts

Awards total: 10 first steps + 5 daily + 2 milestone kinds + 6 ambition paths (x tiers) + `Trophies.all` (existing) + 4 new trophies.
Trivial: 11 (9 first steps, 2 daily goals) plus 2 trophy setup triggers (`cust`, `emp`) and 2 loose ones (`mgr`, `branch`).
Removed from offers or popups: 9 first-step popups, 2 daily goals, 1 daily popup kind (`weeks`).
Reworked: 6 trophies (table above). Added: 4 (q3, debt0, bv ladder of 3 counted as one rule).

## Reads

`GameEngine.pendingAwards() -> [AwardInfo]` (id, title, detail, tier, artKey) maps the existing queue; `Celebrations.add` takes optional `art` and `tier` (stored only when given, so older saves and goldens are unchanged; old entries read back with `art` = kind and tier 1).
