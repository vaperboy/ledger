# Steps that need a Mac

Everything in `native/Engine` runs anywhere Swift runs. The app needs Xcode (15.3 or newer, Xcode 16 recommended).

## First run

```sh
brew install xcodegen
cd native/Engine && swift test            # the engine: all tests
cd ../App && xcodegen generate
open Ledger.xcodeproj
```

In Xcode: pick the *Ledger* scheme, an iPhone or iPad simulator, and Run. The first thing to check is that it compiles; the app was
never compiled by its author (see `KNOWN_GAPS.md`). The GitHub workflow `native-ios.yml` does the same on every push to `native-swiftui`
and shows the compiler's messages.

## Before a real device or TestFlight

1. Select the target *Ledger* › Signing & Capabilities, choose your team, and change the bundle identifier
   (`com.example.ledger` in `project.yml`, key `PRODUCT_BUNDLE_IDENTIFIER`).
2. Add the app icon: put a 1024 × 1024 PNG into `App/Ledger/Assets.xcassets/AppIcon.appiconset` (the original's icon is in
   `Game.zip` › `Ledger/ios-app/assets/AppIcon.appiconset`).
3. Product › Archive, then Distribute App › App Store Connect. Fill in the privacy answers (the app collects nothing and has no
   network access).
4. If the old Capacitor app used the same bundle identifier, decide whether the new app replaces it; saves from the old app cannot
   be read by the new one (see `KNOWN_GAPS.md`).

## What to look at first on a device

* Home on iPhone SE, iPhone 15 Pro Max and iPad (portrait and landscape): the *Next day* button above the tab bar, long numbers in the
  net worth card, Dynamic Type at the largest size.
* Keyboard with the money fields (Done button, scrolling).
* Haptics (Settings › Haptic feedback).
* Import a save from the web game.
