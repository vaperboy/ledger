# Architecture

```
native/
  Engine/            Swift package "LedgerEngine": the whole game without any screen. Builds and tests on Linux, macOS and iOS.
    Sources/
      GameCore       state models, seeded random numbers, calendar, JSON helpers, the small formula language
      Countries      the 23 countries (data), currency and exchange rates, taxes, text tokens
      Employees      staff skills, wages, quitting, tiredness
      Finance        the cash ledger, payments, loans and credit, personal tax
      Businesses     trades (data), demand, capacity, price, daily trade, marketing, hiring, setup, valuation
      Investments    stocks, crypto, funds, savings, deposits
      Events         the event library, firing, answering, previews, special events
      SaveSystem     native saves, backups, import from the HTML game
      Simulation     GameEngine: the order of a day and a week; player actions; read models for screens
    Tests/LedgerTests unit, differential (against the original), simulation and save tests; Golden/ holds the originals' numbers
  App/               SwiftUI app: only screens. project.yml is the XcodeGen definition.
    Ledger/Design    colours, type, cards, buttons, charts, haptics (one place)
    Ledger/Core      GameStore: owns the engine and the save files
    Ledger/Features  Root, Home, Companies, Group, Phone (bank, invest, tax, news, stats, activity, settings, new company), Inbox, Start
  tools/ref/         scripts that run the ORIGINAL game in headless Chromium to produce golden numbers and statistics
  docs/              this folder
```

## Rules that keep it maintainable

* **No game rule lives in a view.** A screen reads from `GameEngine` (its `state`, `netWorth`, `suggestions()`, `quotes()`, …) and
  changes the game only through a function of `PlayerActions.swift`. Every button is therefore one call that a test can make.
* **Balance and content are data.** Numbers that a designer would change are in JSON under `Sources/*/Resources`: countries,
  trades, tables (roles, premises, vehicles, seasons, documents), balance, weather, sales ways, marketing and insurance, events.
* **The state is a record, not a class tree.** Models such as `Company` are typed accessors over the raw JSON of the original save
  (`JSONRecord`). Fields the native code does not use yet are carried unchanged, so an imported save loses nothing.
* **Randomness is explicit.** `DeterministicRandom` is the original's generator (`mulberry32`) and lives inside the state; the same
  seed and the same actions give the same game. `HashedRandom` is the original's `hrng(string)` for things that must not depend on
  the order of play (a person's character, a listing).
* **Money is `Double` in the game's accounting unit**, as in the original, so results can be compared. Display goes through
  `Currency` (exchange rate, tidy rounding, grouping).
* **The books must balance.** `Ledger.gaps(state)` checks that the cash of the player and of every company equals what was booked.
  Tests run it after months of play.

## Order of a day (documented in `GameEngine.swift`)

Monday to Saturday: the day number moves on; every open company trades the day; payroll and bills due today are paid; the
week's already-worked-out money flows release a slice of themselves.
Sunday to Monday: the whole week is worked out in this order, then released over the next seven days:

1. economy, stock markets, competitors, funds, investments;
2. for each company: documents, nobody-works check, customers and sales, books, costs, staff, equipment, marketing, quality,
   events, complaints, word of mouth, buzz, reach;
3. unanswered decisions expire;
4. month end (every company, then you) and year end;
5. companies that cannot pay are declared bankrupt;
6. net worth history, bank checks, game over.

Payday and monthly bills fall on the real calendar date (`Payday`), not on week numbers.

## Where things are

| I want to change … | Look at … |
|---|---|
| a tax rate, VAT, wages, rent of a country | `Countries/Resources/countries.json` |
| a business (price, costs, staff, equipment, documents) | `Businesses/Resources/trades.json` |
| seasons, roles, premises, vehicles, documents | `Businesses/Resources/tables.json` |
| how demand is formed | `Businesses/Demand.swift` (one step per line, named as in the original) |
| a random event | `Events/Resources/events.json` |
| what a button does | `Simulation/PlayerActions.swift` |
| the Home screen | `App/Ledger/Features/Home` |
| colours and type | `App/Ledger/Design/Theme.swift` |
