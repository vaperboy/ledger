# Changelog

## Unreleased — native migration (branch `native-swiftui`)

### Added
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

### Fixed while comparing with the original
* Awareness, reputation, fines, hype, idle closure, `{eq}` placeholders, equipment breakdowns (see `docs/BALANCE_PARITY.md`).

### Known
* See `docs/KNOWN_GAPS.md`. The app has not been run by its author; 17 of 67 trades and most of the original's screens and actions are not ported.
