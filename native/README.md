# Ledger (native)

A native iPhone and iPad business simulation in SwiftUI. Double-entry books, countries with their own tax and labour rules, companies, groups, hiring, banking and more.

## Folders

- `Engine/`: Swift package with all rules (pure Swift, no UI). Tests in `Engine/Tests`.
- `App/`: the SwiftUI app (`App/Ledger`, project generated from `App/project.yml` with xcodegen). Views are thin and read the engine through `GameStore`.

## Build and test

Engine tests (Linux or macOS, Swift 6):

```sh
cd native/Engine
swift test --skip BalanceProbe      # full run takes a long time; use --filter <Suite> for quick checks
```

App (macOS with Xcode only):

```sh
cd native/App && xcodegen generate
set -o pipefail && xcodebuild -scheme Ledger -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build | xcbeautify
```

## CI and release

- Pushing to `native-swiftui` runs the engine tests and the app build on macOS (`.github/workflows/native-ios.yml`).
- A green app build on a push that touches `native/**` publishes an unsigned IPA as a GitHub Release and updates `apps.json`, the AltStore source.
- Update `RELEASE_NOTES.md` at the repository root before pushing; it becomes the release notes and the AltStore "what's new".
- `.github/workflows/native-testflight.yml` is a manual TestFlight upload and needs the App Store Connect secrets set in the repository.

## CONTENT: add things without code

All game content is JSON. Edit the file, push, and CI checks it (`ContentValidationTests`). A wrong id, colour or reference fails CI with a plain message naming the file and the entry. Ids never change once players have them (saves use them); to retire an item, leave it in and do not hand it out.

Folders (paths below start at `native/`):
- `Engine/Sources/Simulation/Resources/Content/<kind>/`: boxes, cards, artifacts, cosmetics, season, progression, pricing.
- `App/Ledger/Resources/Content/<kind>/`: avatars (profile icons), trade_icons.
- `Engine/Sources/<Businesses|Countries|Events>/Resources/`: trades, countries, events, decisions, supplies, luxury and the other game-world files.

Pictures: drop a PNG named `<kind>.<id>.png` into `App/Ledger/Resources/Content/art/`. The app uses it when it exists and draws the symbol or colours when it does not. Kinds: `avatar`, `artifact`, `theme`, `backdrop`, `namePlate`, `tradePlate`, `flair`, `badge`, `box`, `trade`. Logos use the `asset` name in their entry (`logo.mark.png`), equipment uses `equipment.<id>.png`. The older way (an image set named `art.<kind>.<id>` in `Assets.xcassets/Art`) still works and wins if both exist.

| To add | Edit file | Fields to fill | Picture |
|---|---|---|---|
| Profile icon | `App/Ledger/Resources/Content/avatars/avatars.json` | id, title, tier, unlock (+ value), symbol, top, bottom, ink, motif | `avatar.<id>.png` |
| Trade picture | `App/Ledger/Resources/Content/trade_icons/trade_icons.json` | id (a trade id), symbol, family | `trade.<id>.png` |
| Artifact | `Engine/Sources/Simulation/Resources/Content/artifacts/artifacts.json` | id, name, collection, rarity, note, symbol | `artifact.<id>.png` |
| Artifact collection | same file, `collections` | id, name, blurb, reward (a cosmetic id), look | none |
| Profile or company card | `.../Content/cards/cards.json` | id (card.p.x or card.c.x), kind, name, rarity, colors, motion, logo (company) | `artifact.<id>.png` |
| Card given at a level | same file, `levelRewards` | level, card | none |
| Theme, name plate, backdrop, trade plate, flair, save slot | `.../Content/cosmetics/gold_cosmetics.json` | id, kind, title, detail, rarity, source (store, box, collection), colors | `<kind>.<id>.png` |
| Company badge or app colour theme | `.../Content/cosmetics/badges_themes.json` | badge: id, title, symbol, premium. theme: id, title, red, green, blue, premium | `badge.<id>.png` |
| Season pass reward | `.../Content/season/season_1.json` | id, tier (1 to 30), premium (true or false), kind, title, detail, colors; card: card; box or gold: amount | `<kind>.<id>.png` |
| Box odds, name | `.../Content/boxes/boxes.json` | title, rows (rarity, prize, weight, amount); weights add to 10000 | `box.<id>.png` |
| Any price (box, cosmetic, save slot, gold pack, service, store tier) | `.../Content/pricing/prices.json` | gold prices in gold (1 gold is about 1 NOK); App Store tiers in US cents; per-currency table | none |
| Feature unlock level | `Engine/Sources/Businesses/Unlocks.swift`, `FeatureUnlocks.table` | feature, level (one feature per level), title, gives | none |
| Company logo | `Engine/Sources/Businesses/Resources/logo_catalogue.json` | id, name, how (free, level:N, box:rarity), asset | the `asset` name plus `.png` |
| Country | `Engine/Sources/Countries/Resources/countries.json` | copy the `NO` block and change every value; then add the code to `city_market.json` and `country_traits.json` | none |
| Country news | `Engine/Sources/Events/Resources/country_events.json` | cc, head, text, fx, tone | none |
| Random event | `Engine/Sources/Events/Resources/events_pack.json` | area, tone, sev, w, t, b, cool, exp, fx; limits: tr, notTr, fam, cc | none |
| Decision (choice popup) | `Engine/Sources/Events/Resources/decisions.json` | t, b, opts (l, d, fx), w, def, tone; limits: fam, notTr | none |
| Trade (job or business type) | `Engine/Sources/Businesses/Resources/trades.json` | copy the nearest trade and add its id to `order`; then add it to `trade_icons.json`, `supply_catalogue.json` and the item files that list the nearest trade | `trade.<id>.png` |
| Supplies a trade buys | `Engine/Sources/Businesses/Resources/supply_catalogue.json` | lines, families, trades | none |
| Luxury item (car, watch, art, yacht, jet, home) | `Engine/Sources/Businesses/Resources/luxury.json` | id, name, detail, price, upkeep, growth, volatility | image set in `Assets.xcassets` |
| Equipment, items, jobs, rentals, recipes, courses, brokers | the matching file in `Engine/Sources/Businesses/Resources/` (each starts with an `about` line explaining its fields) | copy a neighbour entry | `equipment.<id>.png` |

Minimal entries (copy, paste, change):

```json
{"id": "av.rocket", "title": "Rocket", "tier": "rare", "unlock": "level", "value": "4", "symbol": "airplane", "top": "5C86C4", "bottom": "1F3866", "ink": "D7E5FB", "motif": "rays"}
{"id": "ledger", "name": "Brass ledger", "collection": "counting", "rarity": "common", "note": "Kept by hand.", "symbol": "book.fill"}
{"id": "card.p.dune", "kind": "profile", "name": "Dune card", "rarity": "common", "colors": ["C9A24A", "4A3812"], "motion": "none", "logo": ""}
{"id": "gold.plate.jade", "kind": "namePlate", "title": "Jade plate", "detail": "A green name plate.", "rarity": "rare", "source": "store", "colors": ["8FBF9F", "1F2E26"]}
{"id": "plate.new", "tier": 12, "premium": false, "kind": "namePlate", "title": "New plate", "detail": "A plain plate.", "colors": ["D6B889", "2A2A2C"]}
{"feature": "auctions", "level": 2, "title": "Auctions", "gives": "sell your artifacts"}
{"id": "phoenix", "name": "Phoenix", "how": "box:legendary", "asset": "logo.phoenix"}
```

Rules of thumb: colours are six hex digits without `#`; `symbol` is an SF Symbol name (Apple's icon names); `rarity` is common, rare, epic or legendary; keep a comma between entries and none after the last one.

Still in code (a new one needs a developer): trophies and achievements (`Events/Trophies*.swift`), a brand new box type or a new level-gated feature (the lists are data, the features are code), daily goals and the goal ladder (`PlayerGoals.swift`), career ranks (`Career.swift`), board and unlock rules (`Unlocks.swift`), staff face sheets (`FaceCatalog.swift`), and the store products (`App/Ledger/Core/Purchases`).
