# Audit of the original game

Done first, on the real files (`Game.zip`), before any native code was written. The originals are untouched: `Game.zip`,
`Game.ipa` and `ledger-v1.0.0.zip` are still in the repository root.

## What the original is

* **One HTML application**, about 48,000 lines of JavaScript (2.8 MB when built), wrapped for iPhone with Capacitor (WKWebView) plus a
  small native plugin (`LedgerNativePlugin.swift`, 13 KB). Built and published by `.github/workflows/main.yml`.
* **Architecture:** one global state object `S`; rules in functions; features added as *steps* in named *pipelines*
  (`addStep`, `runSteps`, `runChecks`, `runPhased`, `pipeView`). Later "rounds" of the game patch earlier behaviour by adding
  steps, so the final behaviour is the sum of a core and many patches. 179 such pipelines were inventoried.
* **Size of the game:** 23 countries, 67 trades in 11 families, 133 random events (+50 strategic decisions, +10 family events),
  105 screens, 557 actions, 43 company tabs, 77 permits, 97 job roles, 34 marketing channels, 10 stocks, 5 cryptos, 3 funds, 17 achievements.
* **Time:** the game advances a week at a time; "day mode" works the week out at once and releases it over seven days, with real daily
  retail trade and payday / bills on real calendar dates (round 29).
* **Randomness:** `mulberry32` seeded generator in the state (`S.rs`), and `hrng(string)` (FNV-1a → mulberry32) for stable per-thing
  randomness.
* **Money:** an internal accounting unit priced like the Norwegian krone; every country has an exchange rate `fx` and a monthly drift;
  euro countries move together.
* **Saves:** JSON, optionally compressed with lz-string (`LZ1:` 15-bit, `LZ64:` 6-bit); `VERSION = 5`; browser storage keys
  `ledger-v3:slot:N` and `:auto`; upgrade chain in `UPGRADE`.

The full inventory is `docs/data/original_inventory.json` (made by `tools/ref/snippets/inventory.js`).

## Risks found

| Risk | What was done |
|---|---|
| Behaviour is spread across hundreds of patches | Ported by *system*, each with a differential test where the original can produce the same inputs; `PARITY_CHECKLIST.md` says what is and is not done |
| Random draws cannot match number for number | Exact tests for deterministic parts; statistical comparison (`BALANCE_PARITY.md`) for the rest |
| Numbers frozen at different times | Stored as data (`trades.json`), documented in `KNOWN_GAPS.md` |
| Undefined variable `wage0` in the loan limit | Kept as a fixed floor so offers match; listed as a candidate correction |
| Existing players' saves | Lossless import; the original text is kept (see `SAVE_FORMAT.md`) |
| 48k lines cannot be ported in one pass | Migration order below; the native game is a working subset today |

## Migration order (and where it stands)

1. Foundations: random numbers, calendar, money, countries, taxes — **done, verified**
2. Trades as data, demand, capacity, price — **done, verified on the original's states**
3. Finance: payments, loans, credit, personal tax, net worth — **done, verified**
4. Company week and daily trade for service, venue, retail, production, logistics — **done, statistical parity, gaps listed**
5. People: hiring, wages, payday, quitting, paperwork — **partly** (no poaching, promotions, assistants)
6. Marketing, quality, complaints, word of mouth, equipment wear — **done in a simplified form**
7. Events and inbox decisions with previews — **133 of the library done; strategic decisions not**
8. Investments — **done**
9. Saves and import — **done, tested**
10. Native app — **written, not yet seen running** (needs a Mac)
11. Remaining families (projects, rental, finance, energy, holdings, clubs), groups, managers, chains, franchises, estates — **not started**
