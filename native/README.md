# Ledger — native SwiftUI version

A native iPhone and iPad version of the Ledger business tycoon game, replacing the HTML + Capacitor wrapper. The game rules were
re-implemented in Swift (not a web view) and compared with the original game, which is kept untouched at the repository root.

**Status, honestly:** the engine is built and tested (45 tests, on Linux and on macOS in CI). The SwiftUI app is written but has not yet
been seen running by its author; it is built by CI on macOS. The native game is a *subset* of the original (50 of 67 trades; see
[docs/KNOWN_GAPS.md](docs/KNOWN_GAPS.md) and [docs/PARITY_CHECKLIST.md](docs/PARITY_CHECKLIST.md)). Read those two before trusting anything.

## Build, test, run

Engine (any machine with Swift 5.9+; Linux and macOS):

```sh
cd native/Engine
swift build
swift test                       # all tests, including comparisons with numbers produced by the original game
```

App (needs a Mac with Xcode 15.3+; Xcode 16 recommended):

```sh
brew install xcodegen
cd native/App
xcodegen generate                # creates Ledger.xcodeproj from project.yml
open Ledger.xcodeproj            # choose an iPhone or iPad simulator, press Run
```

or from the command line:

```sh
xcodebuild build -project Ledger.xcodeproj -scheme Ledger -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

More: [docs/MAC_STEPS.md](docs/MAC_STEPS.md) (device, signing, TestFlight).

CI: `.github/workflows/native-ios.yml` runs the engine tests on macOS, builds the app for the simulator on every push to
`native-swiftui` that touches `native/`. It does not touch the existing web / IPA workflows.

## Playing

Start screen: *Continue*, *New game* (name, home country), or *Bring a save from the web game* (file or pasted text; the original is kept).
Home shows net worth with today / week change, what needs you, cash / invested / companies with their histories, a first-steps guide,
and the **Next day** button above the tab bar (the small button next to it skips ahead until something needs you).
Companies, Group, Phone (new company, bank, invest, tax, news, stats, activity, settings) and Inbox are the other tabs.

## Where to read next

| | |
|---|---|
| [docs/AUDIT.md](docs/AUDIT.md) | what the original is, risks, order of migration |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | modules, rules, order of a day |
| [docs/PARITY_CHECKLIST.md](docs/PARITY_CHECKLIST.md) | every system, trade, screen and action: ported / verified / not ported |
| [docs/BALANCE_PARITY.md](docs/BALANCE_PARITY.md) | numbers against the original, and what differs |
| [docs/SAVE_FORMAT.md](docs/SAVE_FORMAT.md) | native saves, backups, import from the HTML game |
| [docs/ADDING_CONTENT.md](docs/ADDING_CONTENT.md) | how to add a country, trade, event, formula, action, screen |
| [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | colours, type, components, motion, haptics |
| [docs/KNOWN_GAPS.md](docs/KNOWN_GAPS.md) | what is missing, unverified, or different |
| [docs/MAC_STEPS.md](docs/MAC_STEPS.md) | the steps that need a Mac |
| [CHANGELOG.md](CHANGELOG.md) | what changed |

## Comparing with the original

`tools/ref` runs the original in headless Chromium (needs Node and Playwright): `ev.js` runs a script inside the game and prints the
result; `snippets/` holds the scripts that made the golden files in `Engine/Tests/LedgerTests/Golden` and the statistics in
`docs/BALANCE_PARITY.md`. `tools/gen_parity.py` regenerates the parity checklist.
