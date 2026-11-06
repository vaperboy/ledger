# Headless play-test bot

A bot that plays the real game through the same public `GameEngine` calls the app's `GameStore` makes (new game, one-page company start,
Setup screen steps, hiring talks, decisions, loans, equipment, chains, holdings ...) and checks invariants every day and week. Everything here is
inert unless `LEDGER_PLAYTEST=1`, so the normal suite is unaffected. No game source file is touched.

## Files

| File | What |
| --- | --- |
| `PlaytestSupport.swift` | env switches, `Findings` collector (aggregates by key, writes TSV), crash log, state hash |
| `PlaytestBot.swift` | `PlayBot`: policies (competent, reckless, passive), scenarios, daily/weekly invariant checks |
| `PlaytestSweepTests.swift` | the sweeps: every trade x country x policy x seed, scenarios, determinism, single-job repro |
| `PlaytestToursTests.swift` | 16 scripted feature tours (hire/fire/talk, manager, loans, equipment, suppliers, pricing, campaigns, insurance, marketplace, dealer, board, chain, ventures, luxury, goals, reports, investments, holding/close/football, every country starts) |
| `PlaytestReworkTours.swift` | 17 tours of the rework: owner meetings per position, advisory round, CEO replacement (solo, majority, minority with failed vote and 8-week block), every sale route (handshake, broker, auction, buyout, merger, stake tiers, group, master franchise, IPO refusal), payroll-short routing, gift codes, unlocks following the player, flood count. Run: `LEDGER_PLAYTEST=1 swift test --skip-build --filter PlaytestReworkTours` |
| `run_shards.sh` | runs one sweep in N processes, finds and skips jobs that crash the process (Swift trap) and writes them up as findings |
| `run_all.sh`, `aggregate.py` | everything in turn, then one ranked list |

## Run

```sh
cd native/Engine
export PATH=/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH
swift build --build-tests

# quick: tours only (about 30 s)
LEDGER_PLAYTEST=1 swift test --skip-build --filter PlaytestToursTests

# one job, with a weekly debug line per company (LEDGER_PT_DEBUG=1)
LEDGER_PLAYTEST=1 LEDGER_PT_COUNTRY=UK LEDGER_PT_TRADE=cafe LEDGER_PT_SEED=1 LEDGER_PT_POLICY=competent LEDGER_PT_SCENARIO=single \
  swift test --skip-build --filter PlaytestSweepTests/testRepro

# whole sweep, 4 processes (about 1.5 h on 4 cores), then the ranked list in $LEDGER_PT_OUT/ranked.txt
Tests/LedgerTests/Playtest/run_all.sh 4
```

`run_shards.sh` takes the module-qualified filter, e.g. `run_shards.sh LedgerTests.PlaytestSweepTests/testSweepRework 4 rw` (the `rework` scenario plays a manager, owner meetings, a CEO change and one sale route per seed). `swift test --filter Playtest` with `LEDGER_PLAYTEST=1` also works but runs one process and a trapped runtime error ends it; prefer `run_shards.sh`.

Narrow a sweep with `LEDGER_PT_COUNTRIES=UK,NO`, `LEDGER_PT_TRADES=cafe,tutor`, `LEDGER_PT_SEEDS=1,2`, `LEDGER_PT_POLICIES=competent,reckless,passive`,
`LEDGER_PT_SCENARIOS=multi,chain,holding,startup,football`, `LEDGER_PT_YEARS=3`. Output goes to `LEDGER_PT_OUT` (default `/tmp/claude-0/s/playtest`):
`findings-<tag>.tsv` (severity, key, count, title, one-line repro, suspected file), `titles-<tag>.tsv` (message counts by normalised title, for spam),
`runs-<tag>.tsv` (one line per job with end state and state hash), `progress-*.log`, `log-*.txt`.

## What is checked

Daily/weekly, per run, each finding carries seed, country, trade, week and a repro command:

- `Ledger.gaps` empty; NaN/inf anywhere in company records; negative inventory, wages, loan balances; reputation/quality/awareness out of range
- net worth jumps with no bot action; company never opens or sits in setup for 20+ weeks; open company with zero revenue or zero capacity for weeks;
  trading company with profit exactly 0 for 3 months; selling units with zero stock
- decisions with no options, answers that return false or leave the message open, decisions born expired, decisions expiring unseen
- message spam: 30+ messages a week, 8+ bad-tone messages a week, the same title 3+ times a week, 8+ open decisions at once, "you bought ..." messages the
  bot did not cause
- hiring dead ends: empty searches, offers that are never accepted, needed vacancies that stay open, manager gone within 6 weeks
- bot-competent games ending in bust or game over
- determinism (same seed twice, same state hash) and save/load round trip at weeks 26 and 90 (state equality, then 4 more weeks must stay equal)

## Bot policies

- `competent`: app route (`startCompanyChoosingPremises`, then the Setup checklist: documents, premises, equipment, stock cash, open), hires the minimum team and
  keeps it, completes paperwork, buys limiting equipment, keeps cash safe (personal money, bank loan through `applyForLoan`, and as a last resort an outside
  "rescue" which is counted and reported as a balance finding), answers every decision daily with the cheapest sensible option.
- `reckless`: full team, extreme prices, big campaigns, spends everything on stocks, random answers.
- `passive`: quick-set-up shortcut, then only advances time and never answers.

## Adding a check

Call `find(severity, key, title, suspectedFile, detail)` from `PlayBot`; the key decides what is merged (put the trade or message kind in it when the
finding should be counted per kind). Severity 1 = game-breaking/dead end/corruption, 2 = broken flow or spam, 3 = odd.
