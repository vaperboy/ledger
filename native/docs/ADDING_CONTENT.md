# Adding content

Most additions are data. After any change run `swift test` in `native/Engine`; several tests count items on purpose (for example
"67 trades"), so update the expected number in the same change.

## A country

1. Copy an entry of `Engine/Sources/Countries/Resources/countries.json` (the UK entry is a good template) and change `code`, `name`,
   `flag`, `currency`, `symbol`, `fx` (accounting units per one local unit), `population`, `economy`, `start` (start-up loan and
   years), `tax` (corporate, dividend, employer contributions, income tax brackets, wealth tax), `vat`, `companies` (legal forms,
   share capital, fees), `work` (paid leave), `authorities` (names used by `{auth:..}` tokens), `documents`, `banned` (trades not
   allowed), `cities` (population in thousands, rent, wage, demand and price levels), `names`, `titles`, `tourism`, `media`,
   `providerNames`, `economyIndex`.
2. Euro countries move together against the others; list the currency code `EUR` and nothing else is needed.
3. The golden `countries_derived` (checked in `FoundationTests`) pins the derived numbers: regenerate it only if you meant to change them.

## A business (trade)

1. Add an entry to `Engine/Sources/Businesses/Resources/trades.json` under `trades`, and its id to `order`. Copy a similar business:
   `fam` (family: svc, venue, retail, prod, logi run today), `ticket` (price of one sale), `cogs` (cost of sales share), `D` (normal
   demand; 0 lets the game derive it), `std` (standard staff), `eq` (equipment: price, life in years, flags `r` required,
   `c` limits capacity, `q` affects quality), `prem` (premises kind and m²), `docs` (permits), `knobs` (choices the owner makes),
   `tw` (traits such as `sub` for memberships, `perish`, `shrink`).
2. Add kinds for its equipment in `tables.json` › `EQ_KINDS` (`mach`, `tool`, `it`, `pos`, `furn`, `soft`, `svc`).
3. Run `swift test`. `TradeCatalogTests` checks the catalogue; add a line to `SimulationSmokeTests.testEveryNativeFamilyRunsWithoutErrors`
   so the new trade is played for ten weeks with the books checked.
4. A trade of a family that is not simulated yet (see `CompanyWeek.isSupported`) cannot be started.
5. A new project trade (family `project`) also needs a row in `ProjectModel.specs` (hour value, size classes, what is sold, mix per focus,
   price and demand calibration); the developer is the trade with `tw.dev`.

## A random event

Add an entry to `Engine/Sources/Events/Resources/events.json` › `events`:

```json
"g_break": { "id": "g_break", "w": 0.022, "t": "{eq} has broken down at {n}.",
  "opts": [ { "l": "Repair now", "d": "Pay for a quick fix.", "fx": { "cash": { "expr": "-max(2500, eqv * 0.04)" }, "fixeq": 1 } } ],
  "cat": "prop", "tone": "bad", "exp": 2, "cond": { "expr": "1 + (1 - co.eqc) * 1.5" } }
```

* `w` is the weekly chance; `cond` (optional, always written as `{ "expr": "…" }`) multiplies it. `exp` is the number of weeks to answer; an unanswered
  decision takes the cheapest option. `cat` is the insurance category.
* `t` may use `{n}` (company), `{eq}` (a machine it owns), `{auth:key}` and `{m:amount}`.
* `fx` keys: `cash`, `loss` (insurable), `fine`, `rep`, `aware`, `q`, `dem`/`cap`/`price`/`cogsUp` as `[multiplier, weeks]`, `pr` (price level
  step), `fixeq`, `brk`, `quit`, `warn`, `coord`, `gamble` `{p, ok, bad}`. A number can be a formula `{ "expr": "…" }` with `wk` (weekly
  revenue), `pay` (weekly payroll), `eqv` (equipment value), `co.eqc`, `co.q`, `co.rep`, `co.payGap`; operators `+ - * /`, `max`, `min`.
* The inbox shows what each option does before the player chooses (`EffectPreview`); adding an effect key means adding its line there.

## A formula or rule

Put the number in the data file if a designer would tune it; otherwise change the Swift function and add a differential test in
`Tests/LedgerTests` using a golden produced by `tools/ref` from the original (see below).

### Making a golden from the original

```sh
node tools/ref/ev.js path/to/ledger.html tools/ref/snippets/your_script.js > out.json
```
`ev.js` opens the original in headless Chromium and prints what the script returns. Put `out.json` in `Tests/LedgerTests/Golden/`
and read it with `Golden.load("name")`.

## An action (something the player can do)

1. Add a function to `Simulation/PlayerActions.swift` that changes the state through `update { s, data, ctx in … }` and returns a
   result the screen can explain.
2. Test it in `PlayerActionsTests`.
3. Call it from a view through `store.act { $0.yourAction(…) }`; show the result with `store.show(...)` and a haptic.

## A screen

1. Add a folder under `App/Ledger/Features`.
2. Read from `store.engine`; never compute money in the view. Use `Card`, `Stat`, `DeltaPill`, `Sparkline`, `SectionLabel`, `GoldButtonStyle`,
   `QuietButtonStyle` from `Design/Components.swift` and colours from `Theme`.
3. Reach it from an app of the Phone (a new `PhoneApp` case with its `Glyph`, opened in `PhoneAppScreen`) or from the tab it belongs to, and from a `Suggestion` if it should be offered
   on Home (`Simulation/Advisor.swift`).
4. Add its row in `tools/gen_parity.py` and regenerate `PARITY_CHECKLIST.md`.
